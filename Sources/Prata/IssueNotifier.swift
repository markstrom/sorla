import PrataCore
import os
import UserNotifications

// Posts at most one user notification per PrataIssue case per launch; authorization is requested
// lazily on the first issue that actually needs a notification.
@MainActor
final class IssueNotifier {
    private let center: UNUserNotificationCenter
    private var didRequestAuthorization = false
    private var notifiedIssues: Set<PrataIssue> = []
    private static let logger = Logger(subsystem: "com.prata.app", category: "IssueNotifier")

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func notify(_ issue: PrataIssue) {
        guard let body = issue.notificationBody else { return }
        guard notifiedIssues.insert(issue).inserted else { return }
        Task {
            await requestAuthorizationIfNeeded()
            let content = UNMutableNotificationContent()
            content.title = "Prata"
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                Self.logger.error("failed to post notification: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        do {
            _ = try await center.requestAuthorization(options: [.alert])
        } catch {
            Self.logger.error("notification authorization request failed: \(String(describing: error), privacy: .public)")
        }
    }
}
