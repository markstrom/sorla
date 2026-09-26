import Foundation

// The hand-off from the Sorla app to the Sorla keyboard, compiled into both (and reached by the tests through the app).
// It depends on Foundation only, never on SorlaCore, so the keyboard stays small: no model, no audio.
//
// The app writes one pending delivery (id, text, createdAt) to a file in the App Group container and posts a Darwin
// notification; the keyboard claims the file, inserts the text once and deletes it. The dictation phase goes to the
// App Group's UserDefaults so the keyboard can show a status line. Text is never written to UserDefaults or logged.
enum TranscriptHandoff {
    static let appGroup = "group.com.sorla.ios"
    static let transcriptReadyNotification = "se.sorla.ios.transcript-ready"
    static let phaseChangedNotification = "se.sorla.ios.phase-changed"
    // The same five minutes as the Mac app's Recent Transcript: an unused transcript is deleted after that.
    static let lifetime: TimeInterval = 5 * 60
    // A phase older than this belongs to a process that is gone; recording (2 min) plus the longest transcription fit.
    static let phaseLifetime: TimeInterval = 10 * 60
}

// What the keyboard's status line shows. Carries no text.
enum KeyboardPhase: String, Codable, Equatable, Sendable {
    case idle
    case listening
    // Capture ended by itself (time limit, call); the next press transcribes what was heard.
    case captured
    case transcribing
}

struct TranscriptDelivery: Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date

    // A clock set back makes the age negative; such a record is not trusted either.
    func isExpired(at now: Date) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return age < 0 || age >= TranscriptHandoff.lifetime
    }
}

final class TranscriptHandoffStore {
    private static let pendingFileName = "pending-transcript.json"
    private static let phaseKey = "handoff.phase"
    private static let phaseDateKey = "handoff.phaseUpdatedAt"
    private static let deliveredKey = "handoff.deliveredIDs"
    private static let deliveredCapacity = 32

    private let directory: URL
    private let defaults: UserDefaults
    private let now: () -> Date
    private let notify: (String) -> Void
    private let fileManager = FileManager.default

    init(directory: URL, defaults: UserDefaults, now: @escaping () -> Date = Date.init, notify: @escaping (String) -> Void = DarwinNotification.post) {
        self.directory = directory
        self.defaults = defaults
        self.now = now
        self.notify = notify
    }

    // Nil when the App Group container can't be reached: in the keyboard, that is when Full Access is off.
    static func shared() -> TranscriptHandoffStore? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TranscriptHandoff.appGroup),
              let defaults = UserDefaults(suiteName: TranscriptHandoff.appGroup) else { return nil }
        return TranscriptHandoffStore(directory: container.appendingPathComponent("Handoff", isDirectory: true), defaults: defaults)
    }

    private var pendingURL: URL { directory.appendingPathComponent(Self.pendingFileName) }

    // MARK: App side

    // Replaces any earlier pending transcript. The file is written atomically with "complete unless open" protection:
    // it can be created while the iPhone locks during a transcription, but can't be read again until it is unlocked.
    @discardableResult
    func offer(_ text: String) throws -> TranscriptDelivery {
        let delivery = TranscriptDelivery(id: UUID(), text: text, createdAt: now())
        try prepareDirectory()
        let data = try JSONEncoder().encode(delivery)
        try data.write(to: pendingURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        notify(TranscriptHandoff.transcriptReadyNotification)
        return delivery
    }

    func publish(_ phase: KeyboardPhase) {
        defaults.set(phase.rawValue, forKey: Self.phaseKey)
        defaults.set(now(), forKey: Self.phaseDateKey)
        notify(TranscriptHandoff.phaseChangedNotification)
    }

    // Deletes a pending transcript that nobody took in time. Either side calls it whenever it runs.
    func removeExpired() {
        guard fileManager.fileExists(atPath: pendingURL.path) else { return }
        guard let data = try? Data(contentsOf: pendingURL) else { return } // unreadable while locked: try again later
        if let delivery = try? JSONDecoder().decode(TranscriptDelivery.self, from: data), !delivery.isExpired(at: now()) {
            return
        }
        try? fileManager.removeItem(at: pendingURL)
    }

    // MARK: Keyboard side

    var phase: KeyboardPhase {
        guard let raw = defaults.string(forKey: Self.phaseKey), let phase = KeyboardPhase(rawValue: raw),
              let updatedAt = defaults.object(forKey: Self.phaseDateKey) as? Date else { return .idle }
        let age = now().timeIntervalSince(updatedAt)
        return age >= 0 && age < TranscriptHandoff.phaseLifetime ? phase : .idle
    }

    // Takes the pending transcript at most once: the file is first renamed to a name only this call knows (a rename
    // succeeds for one caller only), then read and deleted. Expired or already delivered records are deleted unused.
    func claimPendingDelivery() -> TranscriptDelivery? {
        guard fileManager.fileExists(atPath: pendingURL.path) else { return nil }
        let claimed = directory.appendingPathComponent("claimed-\(UUID().uuidString).json")
        do {
            try fileManager.moveItem(at: pendingURL, to: claimed)
        } catch {
            return nil
        }
        defer { try? fileManager.removeItem(at: claimed) }
        guard let data = try? Data(contentsOf: claimed),
              let delivery = try? JSONDecoder().decode(TranscriptDelivery.self, from: data),
              !delivery.isExpired(at: now()),
              !deliveredIDs.contains(delivery.id.uuidString) else { return nil }
        deliveredIDs = Array((deliveredIDs + [delivery.id.uuidString]).suffix(Self.deliveredCapacity))
        return delivery
    }

    private var deliveredIDs: [String] {
        get { defaults.stringArray(forKey: Self.deliveredKey) ?? [] }
        set { defaults.set(newValue, forKey: Self.deliveredKey) }
    }

    private func prepareDirectory() throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = self.directory
        try? directory.setResourceValues(values)
    }
}

// Darwin notifications carry a name only, never data, so nothing about the text crosses the process boundary this way.
enum DarwinNotification {
    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true
        )
    }
}

// Calls `handler` on the main thread whenever one of `names` is posted, until the observer is released.
final class DarwinNotificationObserver {
    private let handler: () -> Void

    init(names: [String], handler: @escaping () -> Void) {
        self.handler = handler
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        for name in names {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), pointer,
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    let target = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
                    if Thread.isMainThread {
                        target.handler()
                    } else {
                        DispatchQueue.main.async { [weak target] in target?.handler() }
                    }
                },
                name as CFString, nil, .deliverImmediately
            )
        }
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}
