import Foundation
import os

public final class URLSessionModelNetwork: ModelNetwork {
    private let session: URLSession

    public init() {
        session = URLSession(configuration: Self.makeConfiguration())
    }

    // Nothing but the request itself leaves the Mac: no cookies, cache, credentials or detailed user agent.
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "Sorla", "Accept-Language": "en"]
        configuration.timeoutIntervalForRequest = 60
        return configuration
    }

    static func checkStatus(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw ModelNetworkError.httpStatus(http.statusCode) }
    }

    static func exceedsLimit(received: Int64, expected: Int64, maxBytes: Int64) -> Bool {
        received > maxBytes || expected > maxBytes
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response)
        return data
    }

    public func download(from url: URL, to destination: URL, maxBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let tracker = DownloadTaskTracker()
        // A response larger than the manifest says is cut off before it can fill the disk.
        let poller = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let (received, expected) = tracker.byteCounts else { continue }
                if Self.exceedsLimit(received: received, expected: expected, maxBytes: maxBytes) {
                    tracker.cancelForSize()
                    return
                }
                progress(received)
            }
        }
        defer { poller.cancel() }

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(from: url, delegate: tracker)
        } catch {
            throw tracker.wasCancelledForSize ? ModelNetworkError.tooLarge : error
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Self.checkStatus(response)
        let size = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size <= maxBytes else { throw ModelNetworkError.tooLarge }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }
}

private final class DownloadTaskTracker: NSObject, URLSessionTaskDelegate, Sendable {
    private struct State {
        var task: URLSessionTask?
        var cancelledForSize = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var byteCounts: (received: Int64, expected: Int64)? {
        state.withLock { state in
            state.task.map { ($0.countOfBytesReceived, $0.countOfBytesExpectedToReceive) }
        }
    }

    var wasCancelledForSize: Bool {
        state.withLock { $0.cancelledForSize }
    }

    func cancelForSize() {
        let task = state.withLock { state -> URLSessionTask? in
            state.cancelledForSize = true
            return state.task
        }
        task?.cancel()
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        state.withLock { $0.task = task }
    }
}
