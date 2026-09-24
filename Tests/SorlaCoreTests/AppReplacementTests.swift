import XCTest
@testable import SorlaCore

// A disk the test rewrites by hand.
final class FakeFileIdentities: FileIdentityProviding {
    var identities: [URL: FileIdentity] = [:]
    private(set) var lookups = 0

    func identity(of url: URL) -> FileIdentity? {
        lookups += 1
        return identities[url]
    }
}

final class AppReplacementCheckTests: XCTestCase {
    private let executable = URL(fileURLWithPath: "/Applications/Sorla.app/Contents/MacOS/Sorla")
    private let disk = FakeFileIdentities()
    private let launched = FileIdentity(device: 1, inode: 100, size: 5_000, modificationDate: Date(timeIntervalSince1970: 1_000))

    private func makeCheck() -> AppReplacementCheck {
        disk.identities[executable] = launched
        return AppReplacementCheck(executableURL: executable, provider: disk)
    }

    func testTheAppAsLaunchedIsNotReplaced() {
        var check = makeCheck()
        XCTAssertFalse(check.check())
        XCTAssertFalse(check.isReplaced)
    }

    // Dragging a new version into Applications gives the executable a new inode.
    func testANewCopyAtTheSamePathIsAReplacement() {
        var check = makeCheck()
        disk.identities[executable] = FileIdentity(device: 1, inode: 200, size: 5_000, modificationDate: launched.modificationDate)
        XCTAssertTrue(check.check())
    }

    // A copy over the old file keeps the inode but not the date or size.
    func testAFileRewrittenInPlaceIsAReplacement() {
        var check = makeCheck()
        disk.identities[executable] = FileIdentity(device: 1, inode: 100, size: 5_000, modificationDate: Date(timeIntervalSince1970: 2_000))
        XCTAssertTrue(check.check())

        var other = makeCheck()
        disk.identities[executable] = FileIdentity(device: 1, inode: 100, size: 6_000, modificationDate: launched.modificationDate)
        XCTAssertTrue(other.check())
    }

    func testAMissingExecutableHasNothingToRestartInto() {
        var check = makeCheck()
        disk.identities[executable] = nil
        XCTAssertFalse(check.check())
    }

    func testWithoutAnIdentityAtLaunchNothingIsEverReported() {
        var check = AppReplacementCheck(executableURL: executable, provider: disk)
        disk.identities[executable] = launched
        XCTAssertFalse(check.check())
        XCTAssertFalse(AppReplacementCheck(executableURL: nil, provider: disk).isReplaced)
    }

    // The running code stays stale even if the old file came back, and no more disk reads are needed.
    func testOnceReplacedItStaysReplacedWithoutLookingAgain() {
        var check = makeCheck()
        disk.identities[executable] = FileIdentity(device: 1, inode: 200, size: 5_000, modificationDate: nil)
        XCTAssertTrue(check.check())
        let lookups = disk.lookups

        disk.identities[executable] = launched
        XCTAssertTrue(check.check())
        XCTAssertEqual(disk.lookups, lookups)
    }

    func testTheSystemProviderReadsARealFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaReplacement-\(UUID().uuidString)")
        try Data("a".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var check = AppReplacementCheck(executableURL: file)
        XCTAssertFalse(check.check())

        try FileManager.default.removeItem(at: file)
        try Data("bb".utf8).write(to: file)
        XCTAssertTrue(check.check())
    }
}

final class AppRelaunchTests: XCTestCase {
    private func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = AppRelaunch.shell
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }

    // Once the old Sorla is gone, the new copy is opened, whatever its path looks like.
    func testOpensTheAppOnceTheOldProcessHasExited() throws {
        let gone = Process()
        gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try gone.run()
        gone.waitUntilExit()
        let bundle = URL(fileURLWithPath: "/Applications/My \"Sorla\" $(echo x).app")

        let result = try run(AppRelaunch.arguments(waitingFor: gone.processIdentifier, thenOpen: bundle, opener: "/bin/echo"))

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, bundle.path + "\n")
    }

    // An old Sorla that won't exit must not end up running next to a new one.
    func testGivesUpWithoutOpeningWhenTheOldProcessOutstaysTheWait() throws {
        let stillRunning = ProcessInfo.processInfo.processIdentifier
        let bundle = URL(fileURLWithPath: "/Applications/Sorla.app")

        let result = try run(AppRelaunch.arguments(waitingFor: stillRunning, thenOpen: bundle, timeout: 0, opener: "/bin/echo"))

        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.output, "")
    }

    // After an install the helper opens the path only once it holds the new version, never the old app.
    func testWithAVersionOnlyThatVersionIsOpened() throws {
        let gone = Process()
        gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try gone.run()
        gone.waitUntilExit()
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaRelaunch-\(UUID().uuidString)/Sorla.app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "1.1.0"], format: .xml, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))

        let opened = try run(AppRelaunch.arguments(waitingFor: gone.processIdentifier, thenOpen: bundle, expectedVersion: "1.1.0", opener: "/bin/echo"))
        XCTAssertEqual(opened.status, 0)
        XCTAssertEqual(opened.output, bundle.path + "\n")

        let refused = try run(AppRelaunch.arguments(waitingFor: gone.processIdentifier, thenOpen: bundle, expectedVersion: "1.0.3", opener: "/bin/echo"))
        XCTAssertEqual(refused.status, 2)
        XCTAssertEqual(refused.output, "")
    }

    func testATranslocatedCopyCannotBeReopened() {
        XCTAssertTrue(AppRelaunch.canReopen(URL(fileURLWithPath: "/Applications/Sorla.app")))
        XCTAssertFalse(AppRelaunch.canReopen(URL(fileURLWithPath: "/private/var/folders/xy/T/AppTranslocation/1A2B/d/Sorla.app")))
    }

    func testTheWaitIsBounded() {
        let arguments = AppRelaunch.arguments(waitingFor: 42, thenOpen: URL(fileURLWithPath: "/Applications/Sorla.app"))
        XCTAssertEqual(Array(arguments.suffix(5)), ["42", "/Applications/Sorla.app", "300", "/usr/bin/open", ""])
    }
}
