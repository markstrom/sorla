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
    }

    func testOnlySuccessfulHTTPResponsesAreAccepted() throws {
        let url = URL(string: "https://models.test/x")!
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let missing = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)

        XCTAssertNoThrow(try URLSessionModelNetwork.checkStatus(ok))
        XCTAssertThrowsError(try URLSessionModelNetwork.checkStatus(missing))
        XCTAssertThrowsError(try URLSessionModelNetwork.checkStatus(nil))
    }
}
