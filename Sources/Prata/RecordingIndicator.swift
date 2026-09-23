import AppKit
import PrataCore
import SwiftUI

struct IslandLayout: Equatable {
    var notchWidth: CGFloat
    var sideWidth: CGFloat
    var height: CGFloat

    static let compactWidth: CGFloat = 240
    static let extraDepth: CGFloat = 14

    var size: NSSize {
        notchWidth > 0
            ? NSSize(width: notchWidth + 2 * sideWidth, height: height)
            : NSSize(width: Self.compactWidth, height: height)
    }

    static func forScreen(_ screen: NSScreen) -> IslandLayout {
        let notchHeight = screen.safeAreaInsets.top
        if notchHeight > 0,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        {
            let notchWidth = screen.frame.width - left.width - right.width
            return IslandLayout(notchWidth: notchWidth, sideWidth: 150, height: notchHeight + extraDepth)
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let height = (menuBarHeight > 0 ? menuBarHeight : 30) + extraDepth
        return IslandLayout(notchWidth: 0, sideWidth: 0, height: height)
    }
}

@MainActor
final class RecordingIndicatorViewModel: ObservableObject {
    @Published private(set) var smoothedLevel: Float = 0
    @Published private(set) var isVisible = false
    @Published private(set) var isExpanded = false
    @Published private(set) var layout = IslandLayout(notchWidth: 0, sideWidth: 0, height: 44)
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var smoother = LevelSmoother()

    func push(_ level: Float) {
        smoothedLevel = smoother.update(target: level)
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    func setLayout(_ layout: IslandLayout) {
        self.layout = layout
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
    private let maxBarHeight: CGFloat = 26
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 4
    private let barCount = 15

    var body: some View {
        let layout = viewModel.layout
        let size = layout.size
        let cornerRadius = min(size.height / 2, 20)
        let collapsed = !viewModel.isExpanded

        content(layout: layout)
            .frame(width: size.width, height: size.height)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius)
                    .fill(Color.black)
            )
            .scaleEffect(
                x: collapsed && !viewModel.reduceMotion ? 0.35 : 1,
                y: collapsed && !viewModel.reduceMotion ? 0.2 : 1,
                anchor: .top
            )
            .opacity(collapsed ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func content(layout: IslandLayout) -> some View {
        if layout.notchWidth > 0 {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    recordDot
                    micGlyph
                }
                .frame(width: layout.sideWidth)
                Color.clear.frame(width: layout.notchWidth)
                visualizer
                    .frame(width: layout.sideWidth)
            }
        } else {
            HStack(spacing: 10) {
                recordDot
                micGlyph
                visualizer
            }
        }
    }

    private var recordDot: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
    }

    private var micGlyph: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
    }

    @ViewBuilder
    private var visualizer: some View {
        Group {
            if viewModel.reduceMotion || !viewModel.isVisible {
                bars(time: 0)
            } else {
                TimelineView(.animation) { context in
                    bars(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(height: maxBarHeight)
    }

    private func bars(time: TimeInterval) -> some View {
        let heights = VisualizerBars.heights(
            level: viewModel.smoothedLevel,
            count: barCount,
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
    }
}

@MainActor
final class RecordingIndicatorPanel: NSPanel {
    private let viewModel = RecordingIndicatorViewModel()
    private var presentationID = 0

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: IslandLayout.compactWidth, height: 44)),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
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
        presentationID += 1
        let id = presentationID
        viewModel.refreshReduceMotion()
        viewModel.reset()
        viewModel.setExpanded(false)
        viewModel.setVisible(true)
        positionOnScreenContainingMouse()
        orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentationID == id else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                self.viewModel.setExpanded(true)
            }
        }
    }

    func hide() {
        presentationID += 1
        let id = presentationID
        withAnimation(.easeIn(duration: 0.18)) {
            viewModel.setExpanded(false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.presentationID == id else { return }
            self.orderOut(nil)
            self.viewModel.setVisible(false)
            self.viewModel.reset()
        }
    }

    private func positionOnScreenContainingMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else { return }

        let layout = IslandLayout.forScreen(screen)
        viewModel.setLayout(layout)
        let size = layout.size
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
