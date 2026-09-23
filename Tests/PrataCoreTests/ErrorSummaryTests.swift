import XCTest
@testable import PrataCore

final class ErrorSummaryTests: XCTestCase {
    private enum SampleError: Error {
        case first
        case second(URL)
    }

    func testSummarizesByDomainAndCode() {
        XCTAssertEqual(ErrorSummary.of(URLError(.notConnectedToInternet)), "NSURLErrorDomain -1009")
        XCTAssertEqual(ErrorSummary.of(CocoaError(.fileNoSuchFile)), "NSCocoaErrorDomain 4")
    }

    func testNeverIncludesPaths() {
        let path = "/Users/someone/Library/Application Support/Prata/Models/x"
        let cocoa = CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: path])
        let swift = SampleError.second(URL(fileURLWithPath: path))

        XCTAssertFalse(ErrorSummary.of(cocoa).contains("someone"))
        XCTAssertFalse(ErrorSummary.of(swift).contains("someone"))
        XCTAssertTrue(ErrorSummary.of(swift).contains("SampleError"))
    }
}
