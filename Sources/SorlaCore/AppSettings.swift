import Combine
import Foundation

@MainActor
public final class AppSettings: ObservableObject {
    private enum Keys {
        static let triggerKey = "triggerKey"
        static let recordingMode = "recordingMode"
        static let keepClipboardContent = "keepClipboardContent"
        static let playSounds = "playSounds"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let autoInstallUpdates = "autoInstallUpdates"
        static let legacyAutoCheckModelUpdates = "autoCheckModelUpdates"
        static let legacyAutoDownloadModelUpdates = "autoDownloadModelUpdates"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    @Published public var triggerKey: TriggerKey {
        didSet { defaults.set(triggerKey.rawValue, forKey: Keys.triggerKey) }
    }

    @Published public var recordingMode: RecordingMode {
        didSet { defaults.set(recordingMode.rawValue, forKey: Keys.recordingMode) }
    }

    @Published public var keepClipboardContent: Bool {
        didSet { defaults.set(keepClipboardContent, forKey: Keys.keepClipboardContent) }
    }

    @Published public var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }

    // Covers both the app and the model.
    @Published public var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }

    // Applies to the model only until the app can install its own updates (#29).
    @Published public var autoInstallUpdates: Bool {
        didSet { defaults.set(autoInstallUpdates, forKey: Keys.autoInstallUpdates) }
    }

    @Published public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        triggerKey = defaults.string(forKey: Keys.triggerKey).flatMap(TriggerKey.init(rawValue:)) ?? .default
        recordingMode = defaults.string(forKey: Keys.recordingMode).flatMap(RecordingMode.init(rawValue:)) ?? .default

        keepClipboardContent = defaults.object(forKey: Keys.keepClipboardContent) as? Bool ?? true
        playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        Self.migrate(from: Keys.legacyAutoCheckModelUpdates, to: Keys.autoCheckUpdates, in: defaults)
        Self.migrate(from: Keys.legacyAutoDownloadModelUpdates, to: Keys.autoInstallUpdates, in: defaults)
        autoCheckUpdates = defaults.object(forKey: Keys.autoCheckUpdates) as? Bool ?? false
        autoInstallUpdates = defaults.object(forKey: Keys.autoInstallUpdates) as? Bool ?? false
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    // The model-only toggles of 1.0 became the toggles for all updates, so a choice made there carries over.
    private static func migrate(from legacyKey: String, to key: String, in defaults: UserDefaults) {
        guard let legacyValue = defaults.object(forKey: legacyKey) as? Bool else { return }
        if defaults.object(forKey: key) == nil {
            defaults.set(legacyValue, forKey: key)
        }
        defaults.removeObject(forKey: legacyKey)
    }
}
