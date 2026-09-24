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
        case failed
    }

    @Environment(\.openURL) private var openURL
    @State private var showsLicenses = false
    @State private var updateState = UpdateState.idle

    private var shortVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private var versionString: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "Version \(shortVersion ?? "—") (\(build))")
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Sorla").font(.title2.bold())
                Text(versionString).font(.caption).foregroundStyle(.secondary)
            }

            updateSection

            Text("Talk. Release. Done.").font(.headline)

            Text("Push-to-talk dictation for Mac. Runs entirely on your device.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Credits").font(.headline)

                creditRow(
                    title: String(localized: "Speech model: Klang Pianissimo"),
                    lines: [
                        String(localized: "By Klang AI AB"),
                        String(localized: "Converted to Core ML for on-device use; weights unchanged."),
                        String(localized: "Based on NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0)."),
                    ],
                    links: [
                        (String(localized: "Model"), URL(string: "https://huggingface.co/KlangAI/pianissimo-sv")!),
                        (String(localized: "License (CC BY 4.0)"), URL(string: "https://creativecommons.org/licenses/by/4.0/")!),
                    ]
                )

                creditRow(
                    title: "FluidAudio",
                    lines: ["Apache License 2.0"],
                    links: [(String(localized: "Project"), URL(string: "https://github.com/FluidInference/FluidAudio")!)]
                )

                creditRow(
                    title: "KeyboardShortcuts",
                    lines: ["MIT License"],
                    links: [(String(localized: "Project"), URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!)]
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(showsLicenses ? String(localized: "Hide Licenses") : String(localized: "Licenses")) {
                showsLicenses.toggle()
            }

            if showsLicenses {
                LicensesView()
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: runRequestedCheck)
        .onChange(of: updateRequest.isPending) { runRequestedCheck() }
    }

    private var updateSection: some View {
        VStack(spacing: 6) {
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
            case .failed:
                updateMessage(String(localized: "Couldn't check for updates. Check your internet connection."))
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
            case .invalid:
                updateState = .failed
                message = String(localized: "Couldn't check for updates. Check your internet connection.")
            }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    @ViewBuilder
    private func creditRow(title: String, lines: [String], links: [(String, URL)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            ForEach(lines, id: \.self) { line in
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(links, id: \.0) { label, url in
                    Link(label, destination: url).font(.caption)
                }
            }
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
