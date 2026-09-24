import SorlaCore
import SwiftUI

// Set by the status menu's "Check for Updates…" so the About window runs the check when it shows.
@MainActor
final class UpdateCheckRequest: ObservableObject {
    @Published var isPending = false
}

struct AboutView: View {
    @ObservedObject var updateRequest: UpdateCheckRequest

    private enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case failed(AppUpdateFailure)
    }

    @Environment(\.openURL) private var openURL
    @State private var showsCredits = false
    @State private var updateState = UpdateState.idle

    private var shortVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private var versionString: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "Version \(shortVersion ?? "—") (\(build))")
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("Sorla").font(.title.bold())
                Text("Talk. Release. Done.").font(.title3).foregroundStyle(.secondary)
                Text(versionString).font(.callout).foregroundStyle(.secondary)
                updateSection
            }

            VStack(spacing: 4) {
                Text("Speech recognition by [Klang Pianissimo](https://huggingface.co/KlangAI/pianissimo-sv) from Klang AI AB.")
                Text("Sorla is independent and not made by Klang AI AB.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Website", destination: URL(string: "https://sorla.zerolabs.se")!)
                Link("GitHub", destination: URL(string: "https://github.com/markstrom/sorla")!)
                Link("Privacy", destination: URL(string: "https://sorla.zerolabs.se/privacy")!)
            }
            .font(.callout)

            Divider()

            VStack(spacing: 6) {
                Button("Credits and Licenses…") { showsCredits = true }
                    .controlSize(.small)
                Text("Open source under the Apache License 2.0. © 2026 Anders Markström")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showsCredits) { CreditsView() }
        .onAppear(perform: runRequestedCheck)
        .onChange(of: updateRequest.isPending) { runRequestedCheck() }
    }

    private var updateSection: some View {
        VStack(spacing: 6) {
            Button("Check for Updates") { checkForUpdates() }
                .controlSize(.small)
                .disabled(updateState == .checking)

            switch updateState {
            case .idle:
                EmptyView()
            case .checking:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(String(localized: "Checking…"))
                    Text(String(localized: "Checking…")).accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            case .upToDate:
                updateMessage(String(localized: "You have the latest version."))
            case .available(let version):
                HStack(spacing: 8) {
                    updateMessage(String(localized: "Sorla \(version) is available."))
                    Button(String(localized: "Download")) {
                        openURL(AppUpdateCheck.downloadPageURL)
                    }
                    .controlSize(.small)
                }
            case .failed(let failure):
                updateMessage(failure.message)
            }
        }
    }

    private func updateMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .accessibilityLabel(text)
    }

    private func runRequestedCheck() {
        guard updateRequest.isPending else { return }
        updateRequest.isPending = false
        guard updateState != .checking else { return }
        checkForUpdates()
    }

    private func checkForUpdates() {
        updateState = .checking
        let current = shortVersion
        let source = URLSessionAppReleaseSource(appVersion: current ?? "dev")
        Task {
            let result = await AppUpdateCheck.check(currentVersion: current, source: source)
            let message: String
            switch result {
            case .upToDate:
                updateState = .upToDate
                message = String(localized: "You have the latest version.")
            case .available(let version):
                updateState = .available(version: version)
                message = String(localized: "Sorla \(version) is available.")
            case .failed(let failure):
                updateState = .failed(failure)
                message = failure.message
            }
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

// Everything Sorla builds on, with the full license texts, kept out of the main About view.
struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Credits and Licenses").font(.headline)

            creditRow(
                title: "Klang Pianissimo",
                detail: String(localized: "Speech model by Klang AI AB, CC BY 4.0. Converted to Core ML with unchanged weights; based on NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0)."),
                url: URL(string: "https://huggingface.co/KlangAI/pianissimo-sv")!
            )
            creditRow(
                title: "FluidAudio",
                detail: String(localized: "Runs the model with Core ML. Apache License 2.0."),
                url: URL(string: "https://github.com/FluidInference/FluidAudio")!
            )
            creditRow(
                title: "KeyboardShortcuts",
                detail: String(localized: "Custom keyboard shortcuts. MIT License."),
                url: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!
            )

            LicensesView()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func creditRow(title: String, detail: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Link(title, destination: url).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// Falls back to a plain message when run unbundled, where there are no license files to read.
struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                licenseSection(
                    title: "FluidAudio (Apache License 2.0)",
                    resource: "LICENSE",
                    extension: nil,
                    subdirectory: "Licenses/FluidAudio"
                )
                licenseSection(
                    title: "KeyboardShortcuts (MIT License)",
                    resource: "LICENSE",
                    extension: nil,
                    subdirectory: "Licenses/KeyboardShortcuts"
                )
                licenseSection(
                    title: String(localized: "Pianissimo model credit"),
                    resource: "Pianissimo",
                    extension: "txt",
                    subdirectory: "Licenses"
                )
            }
            .padding(8)
        }
        .frame(height: 220)
    }

    @ViewBuilder
    private func licenseSection(title: String, resource: String, extension ext: String?, subdirectory: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold())
            Text(Self.licenseText(resource: resource, extension: ext, subdirectory: subdirectory))
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private static func licenseText(resource: String, extension ext: String?, subdirectory: String) -> String {
        guard
            let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: subdirectory),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return String(localized: "License texts are included with the app.")
        }
        return text
    }
}
