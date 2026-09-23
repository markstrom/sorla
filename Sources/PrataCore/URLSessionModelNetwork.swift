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
        configuration.httpAdditionalHeaders = ["User-Agent": "Prata"]
        configuration.timeoutIntervalForRequest = 60
        return configuration
    }

    static func checkStatus(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response)
        return data
    }

    public func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let tracker = DownloadTaskTracker()
        let poller = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if let received = tracker.bytesReceived {
                    progress(received)
                }
            }
        }
        defer { poller.cancel() }

        let (temporaryURL, response) = try await session.download(from: url, delegate: tracker)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Self.checkStatus(response)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }
}

private final class DownloadTaskTracker: NSObject, URLSessionTaskDelegate, Sendable {
    private let task = OSAllocatedUnfairLock<URLSessionTask?>(initialState: nil)

    var bytesReceived: Int64? {
        task.withLock { $0?.countOfBytesReceived }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        self.task.withLock { $0 = task }
    }
}
