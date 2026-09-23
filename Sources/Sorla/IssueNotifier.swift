import SorlaCore
import os
import UserNotifications

// At most one notification per issue per launch; permission is only asked for when first needed.
@MainActor
final class IssueNotifier {
    private let center: UNUserNotificationCenter
    private var didRequestAuthorization = false
    private var notifiedIssues: Set<SorlaIssue> = []
    private static let logger = Logger(subsystem: "com.sorla.app", category: "IssueNotifier")

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func notify(_ issue: SorlaIssue) {
        guard let body = issue.notificationBody else { return }
        guard notifiedIssues.insert(issue).inserted else { return }
        post(body)
    }

    func post(_ body: String) {
        Task {
            await requestAuthorizationIfNeeded()
            let content = UNMutableNotificationContent()
            content.title = "Sorla"
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
