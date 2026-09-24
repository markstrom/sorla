import XCTest
@testable import SorlaCore

// The real file operations, in a scratch folder of their own; nothing near Applications.
final class AppInstallSystemTests: XCTestCase {
    private var root: URL!
    private var files: SystemAppFileOperations!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaInstallSystem-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        files = SystemAppFileOperations(root: root)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func makeApp(_ name: String, version: String) throws -> URL {
        let app = root.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func testThePrivateFolderIsOnlyTheUsers() throws {
        let directory = try files.makePrivateDirectory()
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        XCTAssertEqual(files.leftoverDirectories(), [directory])
    }

    func testReplacingKeepsThePathAndTheOldAppAsBackup() throws {
        let bundle = try makeApp("Sorla.app", version: "1.0.3")
        let staged = try makeApp(".Sorla-update.app", version: "1.1.0")

        try files.replace(bundle, with: staged, backupName: "Sorla 1.0.3.app")

        XCTAssertEqual(files.shortVersion(of: bundle), "1.1.0")
        XCTAssertEqual(files.shortVersion(of: root.appendingPathComponent("Sorla 1.0.3.app")), "1.0.3")
        XCTAssertFalse(files.exists(staged))

        try files.replace(bundle, with: root.appendingPathComponent("Sorla 1.0.3.app"), backupName: nil)
        XCTAssertEqual(files.shortVersion(of: bundle), "1.0.3")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Sorla.app"])
    }

    func testTheVersionIsReadFromDiskEachTime() throws {
        let app = try makeApp("Sorla.app", version: "1.0.3")
        XCTAssertEqual(files.shortVersion(of: app), "1.0.3")
        try FileManager.default.removeItem(at: app)
        _ = try makeApp("Sorla.app", version: "1.1.0")
        XCTAssertEqual(files.shortVersion(of: app), "1.1.0")
        XCTAssertNil(files.shortVersion(of: root.appendingPathComponent("None.app")))
    }

    func testOnlyARealFolderCountsAsADirectory() throws {
        let app = try makeApp("Sorla.app", version: "1.1.0")
        let link = root.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
        XCTAssertTrue(files.isDirectory(app))
        XCTAssertFalse(files.isDirectory(link))
        XCTAssertFalse(files.isDirectory(app.appendingPathComponent("Contents/Info.plist")))
        XCTAssertFalse(files.isDirectory(root.appendingPathComponent("None.app")))
    }

    func testAnUnsignedAppFailsTheSignatureCheck() throws {
        let app = try makeApp("Sorla.app", version: "1.1.0")
        XCTAssertThrowsError(try SecurityAppSignatureChecker().checkSignature(of: app, requirement: AppInstallPolicy.codeRequirement))
    }

    func testAPlainFolderIsNotAMountedImage() throws {
        let folder = root.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertFalse(HdiutilDiskImageMounter.isMounted(folder))
        XCTAssertFalse(HdiutilDiskImageMounter.isMounted(root.appendingPathComponent("missing")))
    }

    func testTheRunnerPassesArgumentsWithoutAShell() async throws {
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["$(whoami)", "a b"], timeout: 10)
        XCTAssertEqual(result, ProcessRunner.Result(status: 0, output: "$(whoami) a b\n"))
    }
}
