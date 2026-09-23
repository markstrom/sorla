import XCTest
@testable import SorlaCore

final class SemanticVersionTests: XCTestCase {
    func testParsesThreeComponents() {
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    func testMissingComponentsAreZero() {
        XCTAssertEqual(SemanticVersion("2"), SemanticVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(SemanticVersion("2.1"), SemanticVersion(major: 2, minor: 1, patch: 0))
    }

    func testRejectsNonNumericVersions() {
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion("1.x.0"))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
        XCTAssertNil(SemanticVersion("-1.0.0"))
    }

    func testComparesNumericallyNotLexically() throws {
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("1.10.0")), try XCTUnwrap(SemanticVersion("1.9.0")))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("2.0.0")), try XCTUnwrap(SemanticVersion("1.99.99")))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("1.0.10")), try XCTUnwrap(SemanticVersion("1.0.9")))
    }

    func testEqualVersionsAreNotNewer() throws {
        XCTAssertFalse(try XCTUnwrap(SemanticVersion("1.0.0")) < XCTUnwrap(SemanticVersion("1.0")))
        XCTAssertEqual(SemanticVersion("1.0.0"), SemanticVersion("1.0"))
    }

    func testDescription() {
        XCTAssertEqual(SemanticVersion("1.2")?.description, "1.2.0")
    }
}
