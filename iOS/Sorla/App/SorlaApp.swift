import SwiftUI

@main
struct SorlaApp: App {
    @StateObject private var modelSetup = ModelSetup()
    @StateObject private var benchmark = BenchmarkRunner()

    init() {
        DictationRuntime.shared.launch()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                DictationView(runtime: .shared, log: DictationRuntime.shared.log, modelSetup: modelSetup)
                    .tabItem { Label("Dictation", systemImage: "mic") }
                ModelView(setup: modelSetup)
                    .tabItem { Label("Model", systemImage: "shippingbox") }
                BenchmarkView(runner: benchmark)
                    .tabItem { Label("Benchmark", systemImage: "gauge.with.dots.needle.33percent") }
            }
            .task { await AutoBenchmark.runIfRequested(setup: modelSetup, runner: benchmark) }
        }
    }
}

// `-SorlaAutoBenchmark YES` as a launch argument installs the model if needed, runs the benchmark
// and saves the report, so a run needs no taps (Xcode scheme, or `simctl launch` in the simulator).
enum AutoBenchmark {
    static let argument = "SorlaAutoBenchmark"

    @MainActor
    static func runIfRequested(setup: ModelSetup, runner: BenchmarkRunner) async {
        guard UserDefaults.standard.bool(forKey: argument) else { return }
        if !PianissimoModel.isInstalled {
            await setup.runInstall()
        }
        await runner.run()
    }
}
