import Combine
import Foundation

@MainActor
public final class AppSettings: ObservableObject {
    private enum Keys {
        static let triggerKey = "triggerKey"
        static let recordingMode = "recordingMode"
        static let keepClipboardContent = "keepClipboardContent"
        static let playSounds = "playSounds"
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

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        triggerKey = defaults.string(forKey: Keys.triggerKey).flatMap(TriggerKey.init(rawValue:)) ?? .default
        recordingMode = defaults.string(forKey: Keys.recordingMode).flatMap(RecordingMode.init(rawValue:)) ?? .default

        keepClipboardContent = defaults.object(forKey: Keys.keepClipboardContent) as? Bool ?? true
        playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
    }
}
