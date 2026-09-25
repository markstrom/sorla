import SorlaCore
import XCTest
@testable import Sorla

final class MenuBarGlyphTests: XCTestCase {
    private static let marks: [MenuBarIconState.Mark] = [.ready, .notReady]
    private static let badges: [MenuBarIconState.Badge?] = [nil, .attention, .restart]

    func testTheGlyphIsATemplateImageSoItFollowsTheMenuBarAppearance() {
        for mark in Self.marks {
            for badge in Self.badges {
                let image = MenuBarGlyph.image(mark: mark, badge: badge, accessibilityDescription: "Sorla")
                XCTAssertTrue(image.isTemplate)
                XCTAssertEqual(image.size.height, 18)
            }
        }
    }

    func testTheImageCarriesTheStatesDescription() {
        let state = MenuBarIconState(mark: .ready, badge: .attention, accessibilityDescription: "Sorla (needs attention)")
        XCTAssertEqual(MenuBarGlyph.image(state).accessibilityDescription, "Sorla (needs attention)")
    }

    // A not-ready model must differ in shape from ready, not only in colour.
    func testTheMarksDrawDifferentPixels() throws {
        XCTAssertNotEqual(try pixels(.notReady), try pixels(.ready))
    }

    // #76: the badges are shapes of their own, told apart from each other and from no badge without colour.
    func testEachBadgeDrawsDifferentPixels() throws {
        let plain = try pixels(.ready)
        let attention = try pixels(.ready, badge: .attention)
        let restart = try pixels(.ready, badge: .restart)
        XCTAssertNotEqual(attention, plain)
        XCTAssertNotEqual(restart, plain)
        XCTAssertNotEqual(attention, restart)
        XCTAssertNotEqual(try pixels(.notReady, badge: .attention), try pixels(.notReady))
    }

    // Room for the badge in the corner, so it is cut free of the bars rather than drawn over them.
    func testABadgeWidensTheImage() {
        let plain = MenuBarGlyph.image(mark: .ready, accessibilityDescription: "Sorla").size.width
        for badge in [MenuBarIconState.Badge.attention, .restart] {
            XCTAssertGreaterThan(MenuBarGlyph.image(mark: .ready, badge: badge, accessibilityDescription: "Sorla").size.width, plain)
        }
    }

    private func pixels(_ mark: MenuBarIconState.Mark, badge: MenuBarIconState.Badge? = nil) throws -> Data {
        let image = MenuBarGlyph.image(mark: mark, badge: badge, accessibilityDescription: "Sorla")
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
