import Foundation
import UserNotifications

/// Local notifications for balance health. Fired at most once per
/// insufficient period (re-armed once the balance becomes sufficient again).
enum BalanceNotifier {
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyInsufficient() {
        let content = UNMutableNotificationContent()
        content.title = "DeepSeek balance insufficient"
        content.body = "Balance can no longer cover API calls. Top up at platform.deepseek.com."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "deepseekbar.balance.insufficient",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
