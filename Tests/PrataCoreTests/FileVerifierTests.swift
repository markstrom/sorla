import XCTest
@testable import PrataCore

final class FileVerifierTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("prata-verifier-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // echo -n "hello" | shasum -a 256
    private let helloHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

    func testComputesTheSHA256OfAFile() throws {
        let url = try write("hello")

        XCTAssertEqual(try FileVerifier.sha256(of: url), helloHash)
    }

    func testHashesFilesLargerThanOneChunk() throws {
        let url = directory.appendingPathComponent("big")
        let data = Data(repeating: 0x61, count: 3 * 1_048_576 + 17)
        try data.write(to: url)

        XCTAssertEqual(try FileVerifier.sha256(of: url), "8cb91458835f2fefeb12cf01e67a7ea18523a0567d4835a974dc04c2ddbb955b")
    }

    func testMatchingSizeAndHashPasses() throws {
        let url = try write("hello")

        XCTAssertTrue(FileVerifier.matches(url, size: 5, sha256: helloHash))
    }

    func testWrongSizeFails() throws {
        let url = try write("hello")

        XCTAssertFalse(FileVerifier.matches(url, size: 6, sha256: helloHash))
    }

    func testWrongHashFails() throws {
        let url = try write("hellO")

        XCTAssertFalse(FileVerifier.matches(url, size: 5, sha256: helloHash))
    }

    func testMissingFileFails() {
        XCTAssertFalse(FileVerifier.matches(directory.appendingPathComponent("absent"), size: 5, sha256: helloHash))
    }

    private func write(_ string: String) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString)
        try Data(string.utf8).write(to: url)
        return url
    }
}
