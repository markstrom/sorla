import SorlaCore
import XCTest
@testable import Sorla

final class ModelLoadingStatusTests: XCTestCase {
    func testLoadingShowsTheLoadingGlyphInEveryPhase() {
        for phase in [DictationPhase.idle, .recording, .transcribing] {
            XCTAssertEqual(ModelLoadingStatus.menuBarIcon(for: .loading, phase: phase).glyph, .loading)
        }
    }

    // The bug this fixes: a failed load must not leave the loading glyph showing forever.
    func testFailedEndsTheLoadingState() {
        let icon = ModelLoadingStatus.menuBarIcon(for: .failed, phase: .idle)
        XCTAssertNotEqual(icon.glyph, .loading)
    }

    // A failed load must differ in shape from ready, not only in colour.
    func testFailedShowsItsOwnGlyph() {
        XCTAssertEqual(ModelLoadingStatus.menuBarIcon(for: .failed, phase: .idle).glyph, .failed)
        XCTAssertEqual(ModelLoadingStatus.menuBarIcon(for: .failed, phase: .recording).glyph, .failed)
        XCTAssertNotEqual(MenuBarGlyph.failed, .ready)
    }

    func testReadyShowsTheMarkInEveryPhase() {
        for phase in [DictationPhase.idle, .recording, .transcribing] {
            XCTAssertEqual(ModelLoadingStatus.menuBarIcon(for: .ready, phase: phase).glyph, .ready)
        }
    }

    func testTheGlyphIsATemplateImageSoItFollowsTheMenuBarAppearance() {
        for glyph in [MenuBarGlyph.ready, .loading, .failed] {
            let image = glyph.image(accessibilityDescription: "Sorla")
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size.height, 18)
        }
    }

    func testTheFailedGlyphDrawsDifferentPixelsFromReady() throws {
        XCTAssertNotEqual(
            try pixels(of: .failed),
            try pixels(of: .ready)
        )
    }

    func testAccessibilityDescriptionsAreDistinctPerState() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .loading, phase: .idle).accessibilityDescription,
            "Sorla (loading model)"
        )
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .failed, phase: .idle).accessibilityDescription,
            "Sorla (model couldn't be loaded)"
        )
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, phase: .idle).accessibilityDescription,
            "Sorla"
        )
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, phase: .recording).accessibilityDescription,
            "Sorla (recording)"
        )
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, phase: .transcribing).accessibilityDescription,
            "Sorla (transcribing)"
        )
    }

    func testAPendingRestartBadgesTheIconInEveryState() throws {
        for status in [ModelLoadingStatus.ready, .loading, .failed] {
            let icon = ModelLoadingStatus.menuBarIcon(for: status, phase: .idle, restartPending: true)
            XCTAssertTrue(icon.restartBadge)
            XCTAssertEqual(icon.glyph, ModelLoadingStatus.menuBarIcon(for: status, phase: .idle).glyph)
            XCTAssertEqual(icon.accessibilityDescription, "Sorla (needs a restart)")
        }
        XCTAssertFalse(ModelLoadingStatus.menuBarIcon(for: .ready, phase: .idle).restartBadge)
        XCTAssertNotEqual(try pixels(of: .ready, restartBadge: true), try pixels(of: .ready))
        XCTAssertTrue(MenuBarGlyph.ready.image(accessibilityDescription: "Sorla", restartBadge: true).isTemplate)
    }

    private func pixels(of glyph: MenuBarGlyph, restartBadge: Bool = false) throws -> Data {
        let image = glyph.image(accessibilityDescription: "Sorla", restartBadge: restartBadge)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
