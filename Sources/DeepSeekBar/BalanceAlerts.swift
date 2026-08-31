import Foundation

/// Pure alert policy for balance notifications. Stateful so each alert
/// fires at most once per alerting period and re-arms on recovery. Kept
/// free of AppKit/UserNotifications dependencies so it is unit-testable.
struct BalanceAlerts: Equatable {
    enum Action: Equatable {
        case insufficientBalance
        case lowBalance
    }

    private(set) var insufficientNotified = false
    private(set) var lowBalanceNotified = false

    /// Decides which notifications to fire for a freshly fetched balance.
    /// `balance`/`threshold` are in the account's currency.
    mutating func evaluate(
        hasBalance: Bool,
        isAvailable: Bool,
        balance: Double?,
        lowBalanceEnabled: Bool,
        lowBalanceThreshold: Double?
    ) -> Set<Action> {
        guard hasBalance else { return [] }

        var actions: Set<Action> = []

        // Official is_available == false: balance can no longer cover API calls.
        if isAvailable == false {
            if insufficientNotified == false {
                actions.insert(.insufficientBalance)
                insufficientNotified = true
            }
        } else {
            insufficientNotified = false
        }

        // User-configured early warning (below the configured threshold).
        if lowBalanceEnabled, let threshold = lowBalanceThreshold, let balance {
            if balance <= threshold {
                if lowBalanceNotified == false {
                    actions.insert(.lowBalance)
                    lowBalanceNotified = true
                }
            } else {
                lowBalanceNotified = false
            }
        } else {
            lowBalanceNotified = false
        }

        return actions
    }
}
