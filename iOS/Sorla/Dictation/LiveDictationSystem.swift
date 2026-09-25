import ActivityKit
import AVFoundation
import UIKit

@MainActor
final class LiveDictationSystem: DictationSystem {
    private static let sessionMarkerKey = "dictation.sessionStartedAt"

    private let defaults: UserDefaults
    private let log: DictationLog
    private var activity: Activity<DictationActivityAttributes>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(defaults: UserDefaults = .standard, log: DictationLog) {
        self.defaults = defaults
        self.log = log
    }

    var isMicrophoneAuthorized: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    var isModelInstalled: Bool {
        PianissimoModel.isInstalled
    }

    var isAppActive: Bool {
        UIApplication.shared.applicationState == .active
    }

    var sessionMarker: Date? {
        get { defaults.object(forKey: Self.sessionMarkerKey) as? Date }
        set { defaults.set(newValue, forKey: Self.sessionMarkerKey) }
    }

    var backgroundTimeRemaining: TimeInterval? {
        let remaining = UIApplication.shared.backgroundTimeRemaining
        return remaining == .greatestFiniteMagnitude ? nil : remaining
    }

    func startActivity() -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let state = DictationActivityAttributes.ContentState(phase: .listening, startedAt: Date())
        do {
            activity = try Activity.request(
                attributes: DictationActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            return true
        } catch {
            return false
        }
    }

    func updateActivity(_ phase: DictationActivityPhase) {
        guard let activity else { return }
        let state = DictationActivityAttributes.ContentState(phase: phase, startedAt: activity.content.state.startedAt)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // A new process never owns a recording, so any Live Activity still showing belongs to a lost one.
    static func endStaleActivities() {
        for activity in Activity<DictationActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func beginBackgroundTask(onExpiration: @escaping @MainActor () -> Void) {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Sorla transcription") { [weak self] in
            MainActor.assumeIsolated {
                onExpiration()
                self?.endBackgroundTask()
            }
        }
    }

    func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    func record(_ metric: DictationMetric) {
        log.append(metric)
    }
}
