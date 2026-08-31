import Foundation
import UserNotifications

/// Local notifications for balance health. Both alerts are decided by
/// BalanceAlerts and fire at most once per alerting period (re-armed once
/// the balance recovers).
enum BalanceNotifier {
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyInsufficient() {
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("DeepSeek balance insufficient")
        content.body = L10n.tr("Balance can no longer cover API calls. Top up at platform.deepseek.com.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "deepseekbar.balance.insufficient",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyLowBalance(balance: Double, currency: String, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Low DeepSeek balance")
        content.body = L10n.trf(
            "Balance %@ is at or below your alert threshold (%@).",
            balance.moneyText(currency: currency),
            threshold.moneyText(currency: currency)
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "deepseekbar.balance.low",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
