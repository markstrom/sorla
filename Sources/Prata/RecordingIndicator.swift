import AppKit
import PrataCore
import SwiftUI

struct IslandLayout: Equatable {
    var notchWidth: CGFloat
    var sideWidth: CGFloat
    var height: CGFloat

    static let compactWidth: CGFloat = 190
    static let compactCollapsedWidth: CGFloat = 36
    // A tab exactly as tall as the menu bar reads as a misalignment, so it hangs clearly below.
    static let depthBelowMenuBar: CGFloat = 6
    static let overshootMargin: CGFloat = 12
    static let notchBarCount = 5
    static let notchStatusSize: CGFloat = 16
    static let minBarHeight: CGFloat = 3
    static let barWidth: CGFloat = 3
    static let barSpacing: CGFloat = 3
    private static let notchContentPadding: CGFloat = 10
    private static let barHeightMargin: CGFloat = 12

    var size: NSSize {
        notchWidth > 0
            ? NSSize(width: notchWidth + 2 * sideWidth, height: height)
            : NSSize(width: Self.compactWidth, height: height)
    }

    // Notch screens collapse into the notch itself; others into a small pill at the top centre.
    var collapsedSize: NSSize {
        NSSize(width: notchWidth > 0 ? notchWidth : Self.compactCollapsedWidth, height: height)
    }

    var panelSize: NSSize {
        NSSize(width: size.width + 2 * Self.overshootMargin, height: height)
    }

    // Bars stay inside the tab with a small margin top and bottom.
    var maxBarHeight: CGFloat {
        max(Self.minBarHeight, height - Self.barHeightMargin)
    }

    static func forScreen(_ screen: NSScreen) -> IslandLayout {
        let notchHeight = screen.safeAreaInsets.top
        if notchHeight > 0,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        {
            let notchWidth = screen.frame.width - left.width - right.width
            return notchLayout(notchWidth: notchWidth, notchHeight: notchHeight)
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return compactLayout(menuBarHeight: menuBarHeight)
    }

    // Each side is just wide enough for its content plus a small pad on both edges.
    static func notchLayout(notchWidth: CGFloat, notchHeight: CGFloat) -> IslandLayout {
        let barsWidth = CGFloat(notchBarCount) * barWidth + CGFloat(notchBarCount - 1) * barSpacing
        let contentWidth = max(barsWidth, notchStatusSize)
        let sideWidth = contentWidth + 2 * notchContentPadding
        return IslandLayout(notchWidth: notchWidth, sideWidth: sideWidth, height: notchHeight + depthBelowMenuBar)
    }

    static func compactLayout(menuBarHeight: CGFloat) -> IslandLayout {
        let height = (menuBarHeight > 0 ? menuBarHeight : 30) + depthBelowMenuBar
        return IslandLayout(notchWidth: 0, sideWidth: 0, height: height)
    }
}

enum IndicatorMode {
    case recording
    case transcribing
}

@MainActor
final class RecordingIndicatorViewModel: ObservableObject {
    @Published private(set) var bands = SIMD8<Float>(repeating: 0)
    @Published private(set) var mode = IndicatorMode.recording
    @Published private(set) var isVisible = false
    @Published private(set) var isExpanded = false
    @Published private(set) var isShapeVisible = false
    @Published private(set) var isContentVisible = false
    @Published private(set) var layout = IslandLayout(notchWidth: 0, sideWidth: 0, height: 44)
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var smoother = BandSmoother()

    func push(_ spectrum: SIMD8<Float>) {
        guard mode == .recording else { return }
        bands = smoother.update(target: spectrum)
    }

    func setMode(_ mode: IndicatorMode) {
        self.mode = mode
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    func setShapeVisible(_ visible: Bool) {
        isShapeVisible = visible
    }

    func setContentVisible(_ visible: Bool) {
        isContentVisible = visible
    }

    func setLayout(_ layout: IslandLayout) {
        self.layout = layout
    }

    func refreshReduceMotion() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func reset() {
        smoother = BandSmoother()
        bands = SIMD8(repeating: 0)
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var viewModel: RecordingIndicatorViewModel

    private let compactBarCount = 15
    private let minBarHeight = IslandLayout.minBarHeight
    private let barWidth = IslandLayout.barWidth
    private let barSpacing = IslandLayout.barSpacing
    private let edgePadding: CGFloat = 14
    private let pulsePeriod = 1.2
    private let barGradient = LinearGradient(
        colors: [.white, Color(red: 0.84, green: 0.92, blue: 1)],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        let layout = viewModel.layout
        let size = layout.size
        let width = viewModel.isExpanded ? size.width : layout.collapsedSize.width
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: min(size.height / 2, 20),
            bottomTrailingRadius: min(size.height / 2, 20)
        )

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .frame(width: width, height: size.height)
                .opacity(viewModel.isShapeVisible ? 1 : 0)

            Group {
                if viewModel.isVisible && !viewModel.reduceMotion {
                    TimelineView(.animation) { context in
                        content(layout: layout, time: context.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    content(layout: layout, time: 0)
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(viewModel.isContentVisible ? 1 : 0)
            .mask(alignment: .top) {
                shape.frame(width: width, height: size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func content(layout: IslandLayout, time: TimeInterval) -> some View {
        if layout.notchWidth > 0 {
            HStack(spacing: 0) {
                statusIndicator(time: time)
                    .frame(width: layout.sideWidth, alignment: .center)
                Color.clear.frame(width: layout.notchWidth)
                bars(time: time, barCount: IslandLayout.notchBarCount, maxHeight: layout.maxBarHeight)
                    .frame(width: layout.sideWidth, alignment: .center)
            }
        } else {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    statusIndicator(time: time)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(viewModel.mode == .transcribing ? .white.opacity(0.4) : .white)
                        .frame(width: 14, height: 14)
                }
                Spacer(minLength: 0)
                bars(time: time, barCount: compactBarCount, maxHeight: layout.maxBarHeight)
            }
            .padding(.horizontal, edgePadding)
        }
    }

    // Pulsing red dot while recording; transcribing swaps it for a spinner in the same spot.
    private func statusIndicator(time: TimeInterval) -> some View {
        ZStack {
            if viewModel.mode == .transcribing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.white)
                    .environment(\.colorScheme, .dark)
            } else {
                recordDot(time: time)
            }
        }
        .frame(width: IslandLayout.notchStatusSize, height: IslandLayout.notchStatusSize)
    }

    private func recordDot(time: TimeInterval) -> some View {
        let phase = time.truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod
        return Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .opacity(0.775 + 0.225 * cos(2 * .pi * phase))
    }

    private func bars(time: TimeInterval, barCount: Int, maxHeight: CGFloat) -> some View {
        let transcribing = viewModel.mode == .transcribing
        let magnitudes = transcribing
            ? Array(repeating: Float(0), count: barCount)
            : VisualizerBars.magnitudes(bands: viewModel.bands, time: time, barCount: barCount, reduceMotion: viewModel.reduceMotion)
        let shimmer = transcribing
            ? VisualizerBars.shimmer(time: time, barCount: barCount, reduceMotion: viewModel.reduceMotion)
            : Array(repeating: Float(0), count: barCount)

        return HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let magnitude = Double(magnitudes[index])
                Capsule()
                    .fill(barGradient)
                    .frame(
                        width: barWidth,
                        height: VisualizerBars.height(
                            forMagnitude: magnitudes[index], minHeight: minBarHeight, maxHeight: maxHeight
                        )
                    )
                    .shadow(color: .white.opacity(0.6 * magnitude * magnitude), radius: 3)
                    .opacity(transcribing ? 0.3 + 0.55 * Double(shimmer[index]) : 0.35 + 0.65 * magnitude)
            }
        }
        .frame(height: maxHeight)
    }
}

@MainActor
final class RecordingIndicatorPanel: NSPanel {
    private let viewModel = RecordingIndicatorViewModel()
    private var presentationID = 0
    private var isPresented = false

    private static let expandAnimation = Animation.spring(response: 0.35, dampingFraction: 0.75)
    private static let contentFadeIn = Animation.easeOut(duration: 0.18).delay(0.15)
    private static let contentFadeOut = Animation.easeIn(duration: 0.1)
    private static let collapseAnimation = Animation.spring(response: 0.3, dampingFraction: 1).delay(0.06)
    private static let pillFadeIn = Animation.easeOut(duration: 0.08)
    private static let pillFadeOut = Animation.easeIn(duration: 0.1).delay(0.26)
    private static let reduceMotionFade = Animation.easeInOut(duration: 0.15)
    private static let collapseDuration: TimeInterval = 0.42
    private static let reduceMotionFadeDuration: TimeInterval = 0.17

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: IslandLayout.compactWidth, height: 36)),
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

    func updateSpectrum(_ spectrum: SIMD8<Float>) {
        viewModel.push(spectrum)
    }

    func showRecording() {
        viewModel.reset()
        guard !isPresented else {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.setMode(.recording)
            }
            return
        }
        showNearMouse()
    }

    func showTranscribing() {
        guard isPresented else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.setMode(.transcribing)
        }
    }

    private func showNearMouse() {
        presentationID += 1
        isPresented = true
        let id = presentationID
        viewModel.refreshReduceMotion()
        let reduceMotion = viewModel.reduceMotion
        let hasNotch = positionOnScreenContainingMouse()
        viewModel.setMode(.recording)
        viewModel.setExpanded(reduceMotion)
        viewModel.setShapeVisible(hasNotch && !reduceMotion)
        viewModel.setContentVisible(false)
        viewModel.setVisible(true)
        orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentationID == id else { return }
            if reduceMotion {
                withAnimation(Self.reduceMotionFade) {
                    self.viewModel.setShapeVisible(true)
                    self.viewModel.setContentVisible(true)
                }
                return
            }
            withAnimation(Self.pillFadeIn) {
                self.viewModel.setShapeVisible(true)
            }
            withAnimation(Self.expandAnimation) {
                self.viewModel.setExpanded(true)
            }
            withAnimation(Self.contentFadeIn) {
                self.viewModel.setContentVisible(true)
            }
        }
    }

    func hide() {
        presentationID += 1
        isPresented = false
        let id = presentationID
        let delay: TimeInterval
        if viewModel.reduceMotion {
            withAnimation(Self.reduceMotionFade) {
                viewModel.setShapeVisible(false)
                viewModel.setContentVisible(false)
            }
            delay = Self.reduceMotionFadeDuration
        } else {
            withAnimation(Self.contentFadeOut) {
                viewModel.setContentVisible(false)
            }
            withAnimation(Self.collapseAnimation) {
                viewModel.setExpanded(false)
            }
            if viewModel.layout.notchWidth == 0 {
                withAnimation(Self.pillFadeOut) {
                    viewModel.setShapeVisible(false)
                }
            }
            delay = Self.collapseDuration
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.presentationID == id else { return }
            self.orderOut(nil)
            self.viewModel.setVisible(false)
            self.viewModel.setShapeVisible(false)
            self.viewModel.setMode(.recording)
            self.viewModel.reset()
        }
    }

    // Returns whether the island sits in a notch, where the collapsed shape hides black-on-black.
    private func positionOnScreenContainingMouse() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else { return false }

        let layout = IslandLayout.forScreen(screen)
        viewModel.setLayout(layout)
        let size = layout.panelSize
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
        return layout.notchWidth > 0
    }
}
