import XCTest
@testable import Sorla

final class DictationResultTests: XCTestCase {
    func testOnlyATranscriptWithTextIsReadyToPaste() {
        let result = DictationResultEntity(.transcribed("Hej"))
        XCTAssertEqual(result.outcome, .transcribed)
        XCTAssertTrue(result.readyToPaste)
        XCTAssertEqual(result.text, "Hej")
    }

    func testNoOtherOutcomeCarriesTextOrAsksForACopy() {
        let outcomes: [DictationOutcome] = [.started, .nothingHeard, .cancelled, .busy, .transcribed("")]
            + DictationFailure.allCases.map { .failed($0) }
        for outcome in outcomes {
            let result = DictationResultEntity(outcome)
            XCTAssertFalse(result.readyToPaste, "\(outcome)")
            XCTAssertNil(result.text, "\(outcome)")
            XCTAssertFalse(result.message.isEmpty, "\(outcome)")
        }
    }

    func testAnEmptyTranscriptCountsAsNothingHeard() {
        XCTAssertEqual(DictationResultEntity(.transcribed("")).outcome, .nothingHeard)
    }

    func testTheOutcomeNamesNeverContainTheText() {
        XCTAssertEqual(DictationOutcome.transcribed("Hemligt").kind, "transcribed")
        XCTAssertFalse(DictationOutcome.transcribed("Hemligt").message.contains("Hemligt"))
        XCTAssertEqual(DictationOutcome.failed(.timedOut).kind, "failed.timedOut")
        XCTAssertEqual(DictationOutcome.failed(.silentInput).kind, "failed.silentInput")
        XCTAssertEqual(DictationResultEntity(.failed(.silentInput)).outcome, .failed)
    }
}

final class SpeechCheckTests: XCTestCase {
    func testNoAudioIsNothingToTranscribe() {
        XCTAssertEqual(SpeechCheck.assess([]), .nothingToTranscribe)
    }

    func testAudioShorterThanTheModelsMinimumIsNothingToTranscribe() {
        let samples = Array(repeating: Float(0.2), count: SpeechCheck.minimumSampleCount - 1)
        XCTAssertEqual(SpeechCheck.assess(samples), .nothingToTranscribe)
    }

    func testExactZerosAreASilentInput() {
        XCTAssertEqual(SpeechCheck.assess(Array(repeating: 0, count: 32_000)), .silentInput)
    }

    func testResidueBelowMinus90dBFSIsASilentInput() {
        var samples = Array(repeating: Float(0), count: 32_000)
        samples[100] = 3e-5
        samples[200] = -3e-5
        XCTAssertEqual(SpeechCheck.assess(samples), .silentInput)
    }

    func testShortSilenceIsNothingToTranscribeRatherThanASilentInput() {
        XCTAssertEqual(SpeechCheck.assess(Array(repeating: 0, count: SpeechCheck.minimumSampleCount - 1)), .nothingToTranscribe)
    }

    func testQuietButRealAudioIsTranscribed() {
        var samples = Array(repeating: Float(0), count: 32_000)
        samples[100] = 0.001
        XCTAssertEqual(SpeechCheck.assess(samples), .transcribable)
    }
}

@MainActor
final class DictationLogTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "DictationLogTests")
        defaults.removePersistentDomain(forName: "DictationLogTests")
    }

    func testTheLogKeepsOnlyTheMostRecentEntries() {
        let log = DictationLog(defaults: defaults)
        for index in 0..<(DictationLog.capacity + 5) {
            log.append(DictationMetric(date: Date(timeIntervalSince1970: Double(index)), outcome: "started", appWasActive: false))
        }
        XCTAssertEqual(log.entries.count, DictationLog.capacity)
        XCTAssertEqual(log.entries.first?.date, Date(timeIntervalSince1970: 5))
    }

    func testTheLogSurvivesARelaunch() {
        DictationLog(defaults: defaults).append(DictationMetric(date: Date(), outcome: "cancelled", appWasActive: true))
        XCTAssertEqual(DictationLog(defaults: defaults).entries.map(\.outcome), ["cancelled"])
    }

    func testTheMarkdownHasOneRowPerEntry() {
        let log = DictationLog(defaults: defaults)
        log.append(DictationMetric(date: Date(), outcome: "transcribed", appWasActive: false, stopToResultMs: 412.34, audioSeconds: 9.8))
        let lines = log.markdown.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[2].contains("| transcribed | no |"))
        XCTAssertTrue(lines[2].contains("| 412.3 |"))
    }
}
