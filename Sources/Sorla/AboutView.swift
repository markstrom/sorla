import SwiftUI

struct AboutView: View {
    @State private var showsLicenses = false

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor))

            VStack(spacing: 4) {
                Text("Sorla").font(.title2.bold())
                Text(versionString).font(.caption).foregroundStyle(.secondary)
            }

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
