import SwiftUI
import UIKit

struct ModelView: View {
    @ObservedObject var setup: ModelSetup

    var body: some View {
        NavigationStack {
            List {
                Section("Installed") {
                    if let installed = setup.installed {
                        LabeledContent("Version", value: installed.version)
                        if let revision = installed.sourceRevision {
                            LabeledContent("Source revision", value: String(revision.prefix(12)))
                        }
                    } else {
                        Text("Not installed")
                            .foregroundStyle(.secondary)
                    }
                    if let downloaded = setup.downloadedPackages {
                        LabeledContent("Kept packages", value: "\(ByteFormat.megabytes(downloaded.logical)) MB")
                    }
                }

                Section {
                    switch setup.state {
                    case .idle:
                        Button(setup.installed == nil ? "Download and Install (~690 MB)" : "Reinstall (measures a fresh compile)") {
                            setup.install()
                        }
                    case .downloading(let fraction):
                        ProgressView("Downloading", value: fraction)
                    case .preparing:
                        ProgressView("Compiling and testing the model…")
                    case .failed(let reason):
                        Text(reason)
                            .foregroundStyle(.red)
                        Button("Try Again") { setup.install() }
                    }
                    if setup.downloadedPackages != nil {
                        Button("Remove Kept Packages", role: .destructive) {
                            setup.removeDownloadedPackages()
                        }
                        .disabled(setup.isBusy)
                    }
                    if setup.installed != nil {
                        Button("Remove Installed Model", role: .destructive) {
                            Task { await setup.removeInstalledModel() }
                        }
                        .disabled(setup.isBusy)
                    }
                } footer: {
                    Text("Downloads the published model from Hugging Face, verifies every file against the manifest, compiles it on this iPhone and runs a self-test — the same steps as Sorla for Mac. The downloaded packages are kept so a reinstall re-measures compilation without downloading again.")
                }

                if let report = setup.report {
                    Section("Install measurements") {
                        Text(report.markdown)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button("Copy as Markdown") {
                            UIPasteboard.general.string = report.markdown
                        }
                    }
                }
            }
            .navigationTitle("Model")
        }
    }
}
