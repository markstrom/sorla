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
    private let minBarHeight: CGFloat = 3
    private let maxBarHeight: CGFloat = 26
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3
    private let edgePadding: CGFloat = 18
    private let pulsePeriod = 1.2
    private let barGradient = LinearGradient(
        colors: [.white, Color(red: 0.84, green: 0.92, blue: 1)],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        let layout = viewModel.layout
        let size = layout.size
        let cornerRadius = min(size.height / 2, 20)
        let collapsed = !viewModel.isExpanded

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
    private func content(layout: IslandLayout, time: TimeInterval) -> some View {
        if layout.notchWidth > 0 {
            HStack(spacing: 0) {
                status(time: time)
                    .padding(.leading, edgePadding)
                    .frame(width: layout.sideWidth, alignment: .leading)
                Color.clear.frame(width: layout.notchWidth)
                bars(time: time)
                    .padding(.trailing, edgePadding)
                    .frame(width: layout.sideWidth, alignment: .trailing)
            }
        } else {
            HStack(spacing: 0) {
                status(time: time)
                Spacer(minLength: 0)
                bars(time: time)
            }
            .padding(.horizontal, edgePadding)
        }
    }

    private func status(time: TimeInterval) -> some View {
        HStack(spacing: 10) {
            recordDot(time: time)
            ZStack {
                if viewModel.mode == .transcribing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                        .environment(\.colorScheme, .dark)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 18, height: 18)
        }
    }

    private func recordDot(time: TimeInterval) -> some View {
        let opacity: Double
        if viewModel.mode == .transcribing {
            opacity = 0.45
        } else {
            let phase = time.truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod
            opacity = 0.775 + 0.225 * cos(2 * .pi * phase)
        }
        return Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .opacity(opacity)
    }

    private func bars(time: TimeInterval) -> some View {
        let transcribing = viewModel.mode == .transcribing
        let magnitudes = transcribing
            ? Array(repeating: Float(0), count: compactBarCount)
            : VisualizerBars.magnitudes(bands: viewModel.bands, time: time, barCount: compactBarCount, reduceMotion: viewModel.reduceMotion)
        let shimmer = transcribing
            ? VisualizerBars.shimmer(time: time, barCount: compactBarCount, reduceMotion: viewModel.reduceMotion)
            : Array(repeating: Float(0), count: compactBarCount)

        return HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<compactBarCount, id: \.self) { index in
                let magnitude = Double(magnitudes[index])
                Capsule()
                    .fill(barGradient)
                    .frame(
                        width: barWidth,
                        height: VisualizerBars.height(
                            forMagnitude: magnitudes[index], minHeight: minBarHeight, maxHeight: maxBarHeight
                        )
                    )
                    .shadow(color: .white.opacity(0.6 * magnitude * magnitude), radius: 3)
                    .opacity(transcribing ? 0.3 + 0.55 * Double(shimmer[index]) : 0.35 + 0.65 * magnitude)
            }
        }
        .frame(height: maxBarHeight)
    }
}

@MainActor
final class RecordingIndicatorPanel: NSPanel {
    private let viewModel = RecordingIndicatorViewModel()
    private var presentationID = 0
    private var isPresented = false

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
        viewModel.setMode(.recording)
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
        isPresented = false
        let id = presentationID
        withAnimation(.easeIn(duration: 0.18)) {
            viewModel.setExpanded(false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.presentationID == id else { return }
            self.orderOut(nil)
            self.viewModel.setVisible(false)
            self.viewModel.setMode(.recording)
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
