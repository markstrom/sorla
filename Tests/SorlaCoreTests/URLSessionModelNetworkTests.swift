import XCTest
@testable import SorlaCore

final class URLSessionModelNetworkTests: XCTestCase {
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
