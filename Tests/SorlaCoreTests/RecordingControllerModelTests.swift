import XCTest
@testable import SorlaCore

actor RecordingEngineSpy: TranscriptionEngine {
    private(set) var calls: [String] = []
    private var prepareFails = false

    func failPrepare() { prepareFails = true }

    func prepare() async throws {
        calls.append("prepare")
        if prepareFails { throw CocoaError(.fileNoSuchFile) }
    }

    func transcribe(_ samples: [Float]) async throws -> String { "" }

    func unload() async {
        calls.append("unload")
    }
}

@MainActor
final class RecordingControllerModelTests: XCTestCase {
    func testReloadUnloadsThenPreparesTheInstalledModel() async {
        let engine = RecordingEngineSpy()
        let controller = RecordingController(engine: engine, modelName: "test")
        var readiness: [Bool] = []
        controller.onModelReadyChange = { readiness.append($0) }

        let loaded = await controller.reloadModel()

        XCTAssertTrue(loaded)
        XCTAssertTrue(controller.isModelReady)
        XCTAssertEqual(readiness, [false, true])
        let calls = await engine.calls
        XCTAssertEqual(calls, ["unload", "prepare"])
    }

    func testAFailedReloadLeavesReportingToTheCaller() async {
        let engine = RecordingEngineSpy()
        await engine.failPrepare()
        let controller = RecordingController(engine: engine, modelName: "test")
        var issues: [SorlaIssue] = []
        controller.onIssue = { issues.append($0) }

        let loaded = await controller.reloadModel()

        XCTAssertFalse(loaded)
        XCTAssertFalse(controller.isModelReady)
        XCTAssertEqual(issues, [])
    }

    func testAFailedPrepareAtLaunchReportsTheModelAsNotLoaded() async {
        let engine = RecordingEngineSpy()
        await engine.failPrepare()
        let controller = RecordingController(engine: engine, modelName: "test")
        var issues: [SorlaIssue] = []
        controller.onIssue = { issues.append($0) }

        controller.prepare()
        let deadline = Date().addingTimeInterval(5)
        while issues.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(issues, [.modelNotLoaded])
    }
}
