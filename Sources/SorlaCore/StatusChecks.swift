import Foundation

// What the menu's status row and the icon's badge read from the Mac: the two permissions and the model's files.
// Read once per refresh and shared by both, so they agree and the checks aren't repeated (#76).
public struct StatusChecks: Equatable, Sendable {
    public var isMicrophoneAccessDenied: Bool
    public var isAccessibilityTrusted: Bool
    public var isModelInstalled: Bool

    public init(isMicrophoneAccessDenied: Bool, isAccessibilityTrusted: Bool, isModelInstalled: Bool) {
        self.isMicrophoneAccessDenied = isMicrophoneAccessDenied
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.isModelInstalled = isModelInstalled
    }
}

// A model download reports its progress many times a second, and a tick changes neither the permissions nor the
// files, so between ticks the last reading is reused. Every other refresh, such as app activation, the menu opening,
// a phase change or a new model status, reads again (#76).
public struct StatusCheckCache {
    private var last: StatusChecks?
    private var lastModel: ModelStatus?

    public init() {}

    // `model` is the new status when a model status change asks for the refresh, nil for any other refresh.
    public mutating func checks(model: ModelStatus?, read: () -> StatusChecks) -> StatusChecks {
        defer { if let model { lastModel = model } }
        if let model, let last, let lastModel, model.isProgressTick(after: lastModel) {
            return last
        }
        let checks = read()
        last = checks
        return checks
    }
}

extension ModelStatus {
    // Only the fraction moved: the same download, a little further along.
    public func isProgressTick(after previous: ModelStatus) -> Bool {
        guard case .downloading(let version, _, let isUpdate) = self,
              case .downloading(version, _, isUpdate) = previous else { return false }
        return true
    }
}
