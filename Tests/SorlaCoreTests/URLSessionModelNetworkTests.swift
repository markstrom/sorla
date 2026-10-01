import os
import XCTest
@testable import SorlaCore

final class URLSessionModelNetworkTests: XCTestCase {
    private var directory: URL!
    private let url = URL(string: "https://models.test/pianissimo/resolve/0a1b2c/Encoder.mlmodelc/weights/weight.bin")!
    private let body = Data("hello world".utf8)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sorla-network-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        StubModelServer.reset()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        StubModelServer.reset()
    }

    private var destination: URL { directory.appendingPathComponent("weight.bin") }
    private var partial: URL { URLSessionModelNetwork.partialLocation(for: destination) }
    private let network = URLSessionModelNetwork(protocolClasses: [StubModelServer.self])

    private func download(maxBytes: Int64? = nil) async throws {
        try await network.download(from: url, to: destination, maxBytes: maxBytes ?? Int64(body.count), access: .any) { _ in }
    }

    private func contents(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    func testAWholeDownloadLandsAtTheDestination() async throws {
        StubModelServer.serve(body)

        try await download()

        XCTAssertEqual(contents(destination), "hello world")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertEqual(StubModelServer.ranges, [nil])
    }

    func testAPartialFileIsContinuedWithARangeRequest() async throws {
        StubModelServer.serve(body)
        try Data("hello ".utf8).write(to: partial)

        try await download()

        XCTAssertEqual(contents(destination), "hello world")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertEqual(StubModelServer.ranges, ["bytes=6-"])
    }

    func testAnInterruptedDownloadKeepsWhatArrivedAndTheNextAttemptContinuesIt() async throws {
        StubModelServer.serve(body, failingAfter: 5)

        do {
            try await download()
            XCTFail("expected the connection to drop")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }
        XCTAssertEqual(contents(partial), "hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        StubModelServer.serve(body)
        try await download()

        XCTAssertEqual(contents(destination), "hello world")
        XCTAssertEqual(StubModelServer.ranges, [nil, "bytes=5-"])
    }

    func testAServerThatIgnoresTheRangeStartsTheFileOver() async throws {
        StubModelServer.serve(body, honoursRange: false)
        try Data("hello ".utf8).write(to: partial)

        try await download()

        XCTAssertEqual(contents(destination), "hello world")
        XCTAssertEqual(StubModelServer.ranges, ["bytes=6-"])
    }

    func testARangeFromTheWrongPlaceDiscardsThePartialFile() async throws {
        StubModelServer.serve(body, contentRangeStart: 0)
        try Data("hello ".utf8).write(to: partial)

        do {
            try await download()
            XCTFail("expected a bad server response")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testAPartialFileAsLargeAsTheWholeIsStartedOver() async throws {
        StubModelServer.serve(body)
        try Data("garbage-garbage".utf8).write(to: partial)

        try await download()

        XCTAssertEqual(contents(destination), "hello world")
        XCTAssertEqual(StubModelServer.ranges, [nil])
    }

    func testAServerErrorKeepsThePartialFileForLater() async throws {
        StubModelServer.serve(Data(), status: 503)
        try Data("hello ".utf8).write(to: partial)

        do {
            try await download()
            XCTFail("expected a server error")
        } catch {
            XCTAssertEqual(error as? ModelNetworkError, .httpStatus(503))
        }
        XCTAssertEqual(contents(partial), "hello ")
    }

    func testADeclaredLengthOverTheLimitIsRefusedBeforeAnyBytesAreKept() async throws {
        StubModelServer.serve(body)

        do {
            try await download(maxBytes: 5)
            XCTFail("expected the download to be refused")
        } catch {
            XCTAssertEqual(error as? ModelNetworkError, .tooLarge)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testABodyThatOutgrowsTheLimitWithoutALengthIsCutOff() async throws {
        StubModelServer.serve(body, declaresLength: false)

        do {
            try await download(maxBytes: 5)
            XCTFail("expected the download to be cut off")
        } catch {
            XCTAssertEqual(error as? ModelNetworkError, .tooLarge)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testOnlyInexpensiveAccessKeepsOffHotspotsAndLowDataMode() {
        let inexpensive = URLSessionModelNetwork.makeConfiguration(access: .inexpensiveOnly)
        XCTAssertFalse(inexpensive.allowsExpensiveNetworkAccess)
        XCTAssertFalse(inexpensive.allowsConstrainedNetworkAccess)
        XCTAssertNil(inexpensive.httpCookieStorage)
        XCTAssertNil(inexpensive.urlCache)

        let any = URLSessionModelNetwork.makeConfiguration(access: .any)
        XCTAssertTrue(any.allowsExpensiveNetworkAccess)
        XCTAssertTrue(any.allowsConstrainedNetworkAccess)
    }

    func testReadsWhereAContentRangeStarts() {
        XCTAssertEqual(URLSessionModelNetwork.rangeStart(ofContentRange: "bytes 1000-1999/649181632"), 1000)
        XCTAssertEqual(URLSessionModelNetwork.rangeStart(ofContentRange: "bytes 0-10/11"), 0)
        XCTAssertNil(URLSessionModelNetwork.rangeStart(ofContentRange: "bytes */11"))
        XCTAssertNil(URLSessionModelNetwork.rangeStart(ofContentRange: nil))
        XCTAssertNil(URLSessionModelNetwork.rangeStart(ofContentRange: "items 0-1/2"))
    }

    func testSessionKeepsNoCookiesCacheOrCredentialsAndSendsNoIdentifiers() {
        let configuration = URLSessionModelNetwork.makeConfiguration()

        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(configuration.httpAdditionalHeaders?["User-Agent"] as? String, "Sorla")
        XCTAssertEqual(configuration.httpAdditionalHeaders?["Accept-Language"] as? String, "en")
    }

    func testOnlySuccessfulHTTPResponsesAreAccepted() throws {
        let url = URL(string: "https://models.test/x")!
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let missing = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)

        XCTAssertNoThrow(try URLSessionModelNetwork.checkStatus(ok))
        XCTAssertThrowsError(try URLSessionModelNetwork.checkStatus(missing)) { error in
            XCTAssertEqual(error as? ModelNetworkError, .httpStatus(404))
        }
        XCTAssertThrowsError(try URLSessionModelNetwork.checkStatus(nil)) { error in
            XCTAssertTrue(error is URLError)
        }
    }

    func testADownloadIsCutOffOnceItExceedsItsDeclaredSize() {
        XCTAssertFalse(URLSessionModelNetwork.exceedsLimit(received: 100, expected: 100, maxBytes: 100))
        XCTAssertFalse(URLSessionModelNetwork.exceedsLimit(received: 10, expected: -1, maxBytes: 100))
        XCTAssertTrue(URLSessionModelNetwork.exceedsLimit(received: 101, expected: -1, maxBytes: 100))
        XCTAssertTrue(URLSessionModelNetwork.exceedsLimit(received: 0, expected: 5_000, maxBytes: 100))
    }
}

// Answers every request like a file server: whole files, ranges, errors and dropped connections.
final class StubModelServer: URLProtocol {
    struct Plan: Sendable {
        var body: Data
        var status: Int
        var honoursRange: Bool
        var contentRangeStart: Int64?
        var declaresLength: Bool
        var failingAfter: Int?
    }

    private struct State {
        var plan: Plan?
        var ranges: [String?] = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func reset() {
        state.withLock { $0 = State() }
    }

    static func serve(_ body: Data, status: Int = 200, honoursRange: Bool = true, contentRangeStart: Int64? = nil, declaresLength: Bool = true, failingAfter: Int? = nil) {
        let plan = Plan(body: body, status: status, honoursRange: honoursRange, contentRangeStart: contentRangeStart, declaresLength: declaresLength, failingAfter: failingAfter)
        state.withLock { $0.plan = plan }
    }

    static var ranges: [String?] { state.withLock { $0.ranges } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let range = request.value(forHTTPHeaderField: "Range")
        let plan = Self.state.withLock { state -> Plan? in
            state.ranges.append(range)
            return state.plan
        }
        guard let plan, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        var status = plan.status
        var body = plan.body
        // A declared type keeps URLSession from holding back the first bytes to sniff one.
        var headers = ["Content-Type": "application/octet-stream"]
        if status == 200, plan.honoursRange, let range, range.hasPrefix("bytes="), range.hasSuffix("-"),
           let start = Int(range.dropFirst("bytes=".count).dropLast()), start < plan.body.count {
            status = 206
            body = plan.body.subdata(in: start..<plan.body.count)
            headers["Content-Range"] = "bytes \(plan.contentRangeStart ?? Int64(start))-\(plan.body.count - 1)/\(plan.body.count)"
        } else if status == 200, let start = plan.contentRangeStart {
            status = 206
            headers["Content-Range"] = "bytes \(start)-\(plan.body.count - 1)/\(plan.body.count)"
        }
        if plan.declaresLength {
            headers["Content-Length"] = String(body.count)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let failingAfter = plan.failingAfter {
            client?.urlProtocol(self, didLoad: body.prefix(failingAfter))
            // A real connection drops some time after its last bytes, which have reached the delegate by then.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            }
            return
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
