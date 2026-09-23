import AppKit
import PrataCore
import SwiftUI

@MainActor
final class RecordingIndicatorViewModel: ObservableObject {
    @Published private(set) var smoothedLevel: Float = 0
    @Published private(set) var isVisible = false
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var smoother = LevelSmoother()

    func push(_ level: Float) {
        smoothedLevel = smoother.update(target: level)
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
    }

    func refreshReduceMotion() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func reset() {
        smoother = LevelSmoother()
        smoothedLevel = 0
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var viewModel: RecordingIndicatorViewModel

    private let minBarHeight: CGFloat = 3
    private let maxBarHeight: CGFloat = 20
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 5

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            GeometryReader { geometry in
                visualizer(availableWidth: geometry.size.width)
            }
            .frame(height: maxBarHeight)
        }
        .padding(.horizontal, 16)
        .frame(width: RecordingIndicatorPanel.panelSize.width, height: RecordingIndicatorPanel.panelSize.height)
        .background(Capsule().fill(Color.black))
    }

    @ViewBuilder
    private func visualizer(availableWidth: CGFloat) -> some View {
        let count = VisualizerBars.recommendedBarCount(
            availableWidth: availableWidth, barWidth: barWidth, spacing: barSpacing
        )
        if viewModel.reduceMotion || !viewModel.isVisible {
            bars(count: count, time: 0)
        } else {
            TimelineView(.animation) { context in
                bars(count: count, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func bars(count: Int, time: TimeInterval) -> some View {
        let heights = VisualizerBars.heights(
            level: viewModel.smoothedLevel,
            count: count,
            time: time,
            minHeight: minBarHeight,
            maxHeight: maxBarHeight,
            reduceMotion: viewModel.reduceMotion
        )
        return HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(Color.white)
                    .frame(width: barWidth, height: height)
            }
        }
        .frame(maxWidth: .infinity)
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
        contentViewController = NSHostingController(rootView: RecordingIndicatorView(viewModel: viewModel))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLevel(_ level: Float) {
        viewModel.push(level)
    }

    func showNearMouse() {
        viewModel.refreshReduceMotion()
        viewModel.reset()
        viewModel.setVisible(true)
        positionOnScreenContainingMouse()
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
        viewModel.setVisible(false)
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
