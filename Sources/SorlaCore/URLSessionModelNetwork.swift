import Foundation
import os

public final class URLSessionModelNetwork: ModelNetwork {
    private let session: URLSession
    private let inexpensiveSession: URLSession

    public convenience init() {
        self.init(protocolClasses: nil)
    }

    // Tests pass a URLProtocol here to answer requests without a network.
    init(protocolClasses: [AnyClass]?) {
        session = URLSession(configuration: Self.makeConfiguration(access: .any, protocolClasses: protocolClasses))
        inexpensiveSession = URLSession(configuration: Self.makeConfiguration(access: .inexpensiveOnly, protocolClasses: protocolClasses))
    }

    // Nothing but the request itself leaves the Mac: no cookies, cache, credentials or detailed user agent.
    static func makeConfiguration(access: ModelNetworkAccess = .any, protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "Sorla", "Accept-Language": "en"]
        configuration.timeoutIntervalForRequest = 60
        if access == .inexpensiveOnly {
            configuration.allowsExpensiveNetworkAccess = false
            configuration.allowsConstrainedNetworkAccess = false
        }
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return configuration
    }

    private func session(for access: ModelNetworkAccess) -> URLSession {
        access == .any ? session : inexpensiveSession
    }

    static func checkStatus(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // Only a body counts: a 204 or other empty success would leave nothing to verify.
        guard [200, 206].contains(http.statusCode) else { throw ModelNetworkError.httpStatus(http.statusCode) }
    }

    static func exceedsLimit(received: Int64, expected: Int64, maxBytes: Int64) -> Bool {
        received > maxBytes || expected > maxBytes
    }

    static func partialLocation(for destination: URL) -> URL {
        ModelStaging.partialLocation(for: destination)
    }

    // "bytes 1000-1999/649181632" starts at 1000.
    static func rangeStart(ofContentRange header: String?) -> Int64? {
        guard let header, header.hasPrefix("bytes ") else { return nil }
        let range = header.dropFirst("bytes ".count)
        guard let dash = range.firstIndex(of: "-") else { return nil }
        return Int64(range[..<dash])
    }

    public func data(from url: URL, access: ModelNetworkAccess) async throws -> Data {
        let (data, response) = try await session(for: access).data(from: url)
        try Self.checkStatus(response)
        return data
    }

    // Continues a partial file with an HTTP Range request; the installer's SHA-256 check covers the joined file.
    public func download(from url: URL, to destination: URL, maxBytes: Int64, access: ModelNetworkAccess, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let fileManager = FileManager.default
        let partial = Self.partialLocation(for: destination)
        let existing = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        // Everything arrived before the last attempt stopped: the caller verifies it like any finished download.
        if existing > 0, existing == maxBytes {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: partial, to: destination)
            progress(existing)
            return
        }
        let offset = existing > 0 && existing < maxBytes ? existing : 0
        if offset == 0 {
            try? fileManager.removeItem(at: partial)
        }
        var request = URLRequest(url: url)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let receiver = try PartialFileReceiver(file: partial, offset: offset, maxBytes: maxBytes, progress: progress)
        try await receiver.run(request, in: session(for: access))
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: partial, to: destination)
    }
}

// Writes a response body straight to disk, appending when the server answers a Range request with 206.
private final class PartialFileReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var offset: Int64
        var written: Int64 = 0
        var failure: Error?
        var discardsPartial = false
        var lastProgress = Date.distantPast
        var continuation: CheckedContinuation<Void, Error>?
    }

    private static let progressInterval: TimeInterval = 0.25
    private let file: URL
    private let handle: FileHandle
    private let maxBytes: Int64
    private let progress: @Sendable (Int64) -> Void
    private let state: OSAllocatedUnfairLock<State>

    init(file: URL, offset: Int64, maxBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) throws {
        if !FileManager.default.fileExists(atPath: file.path) {
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        }
        handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(offset))
        try handle.seekToEnd()
        self.file = file
        self.maxBytes = maxBytes
        self.progress = progress
        state = OSAllocatedUnfairLock(initialState: State(offset: offset))
    }

    func run(_ request: URLRequest, in session: URLSession) async throws {
        let task = session.dataTask(with: request)
        task.delegate = self
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    state.withLock { $0.continuation = continuation }
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            // The partial file stays, so the next attempt continues where this one stopped.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            try accept(response)
            completionHandler(.allow)
        } catch {
            state.withLock { $0.failure = $0.failure ?? error }
            completionHandler(.cancel)
        }
    }

    private func accept(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let offset = state.withLock { $0.offset }
        switch http.statusCode {
        case 206:
            // Bytes from anywhere but the end of the partial file would corrupt it, so it is started over next time.
            guard URLSessionModelNetwork.rangeStart(ofContentRange: http.value(forHTTPHeaderField: "Content-Range")) == offset else {
                state.withLock { $0.discardsPartial = true }
                throw URLError(.badServerResponse)
            }
        case 200:
            // The whole file came back instead of the rest of it.
            if offset > 0 {
                try handle.truncate(atOffset: 0)
                state.withLock { $0.offset = 0 }
            }
        case 416:
            state.withLock { $0.discardsPartial = true }
            throw ModelNetworkError.httpStatus(http.statusCode)
        default:
            throw ModelNetworkError.httpStatus(http.statusCode)
        }
        let start = state.withLock { $0.offset }
        let expected = response.expectedContentLength >= 0 ? start + response.expectedContentLength : -1
        if URLSessionModelNetwork.exceedsLimit(received: start, expected: expected, maxBytes: maxBytes) {
            state.withLock { $0.discardsPartial = true }
            throw ModelNetworkError.tooLarge
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let received = state.withLock { state -> Int64 in
            state.written += Int64(data.count)
            return state.offset + state.written
        }
        // A response larger than the manifest says is cut off before it can fill the disk.
        if URLSessionModelNetwork.exceedsLimit(received: received, expected: -1, maxBytes: maxBytes) {
            state.withLock {
                $0.failure = $0.failure ?? ModelNetworkError.tooLarge
                $0.discardsPartial = true
            }
            dataTask.cancel()
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            state.withLock { $0.failure = $0.failure ?? error }
            dataTask.cancel()
            return
        }
        let reports = state.withLock { state -> Bool in
            let now = Date()
            guard now.timeIntervalSince(state.lastProgress) >= Self.progressInterval else { return false }
            state.lastProgress = now
            return true
        }
        if reports { progress(received) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle.close()
        let (continuation, failure, discards, received) = state.withLock { state in
            let continuation = state.continuation
            state.continuation = nil
            return (continuation, state.failure ?? error, state.discardsPartial, state.offset + state.written)
        }
        if discards {
            try? FileManager.default.removeItem(at: file)
        }
        if let failure {
            continuation?.resume(throwing: failure)
        } else {
            progress(received)
            continuation?.resume()
        }
    }
}
