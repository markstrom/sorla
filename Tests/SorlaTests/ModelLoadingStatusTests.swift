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

    private func pixels(of glyph: MenuBarGlyph) throws -> Data {
        let image = glyph.image(accessibilityDescription: "Sorla")
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
