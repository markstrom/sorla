import AppKit
import SwiftUI

@MainActor
final class RecordingIndicatorViewModel: ObservableObject {
    static let barCount = 24

    @Published private(set) var levels: [Float]

    init() {
        levels = Array(repeating: 0, count: Self.barCount)
    }

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func reset() {
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var viewModel: RecordingIndicatorViewModel
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(viewModel.levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 2, height: barHeight(for: level))
                }
            }
            .frame(height: 18)
            .animation(reduceMotion ? nil : .linear(duration: 0.08), value: viewModel.levels)
        }
        .padding(.horizontal, 16)
        .frame(width: RecordingIndicatorPanel.panelSize.width, height: RecordingIndicatorPanel.panelSize.height)
        .background(Capsule().fill(Color.black))
    }

    private func barHeight(for level: Float) -> CGFloat {
        let minimumHeight: CGFloat = 2
        let maximumHeight: CGFloat = 18
        return minimumHeight + CGFloat(level) * (maximumHeight - minimumHeight)
    }
}

@MainActor
final class RecordingIndicatorPanel: NSPanel {
    static let panelSize = NSSize(width: 220, height: 36)

    private let viewModel = RecordingIndicatorViewModel()

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentViewController = NSHostingController(
            rootView: RecordingIndicatorView(
                viewModel: viewModel,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLevel(_ level: Float) {
        viewModel.push(level)
    }

    func showNearMouse() {
        viewModel.reset()
        positionOnScreenContainingMouse()
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
        viewModel.reset()
    }

    private func positionOnScreenContainingMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let size = Self.panelSize
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 6
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
