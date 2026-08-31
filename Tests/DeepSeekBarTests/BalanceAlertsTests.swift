import XCTest
@testable import DeepSeekBar

final class BalanceAlertsTests: XCTestCase {
    private func evaluate(
        _ alerts: inout BalanceAlerts,
        isAvailable: Bool = true,
        balance: Double?,
        enabled: Bool = true,
        threshold: Double? = 10
    ) -> Set<BalanceAlerts.Action> {
        alerts.evaluate(
            hasBalance: balance != nil,
            isAvailable: isAvailable,
            balance: balance,
            lowBalanceEnabled: enabled,
            lowBalanceThreshold: threshold
        )
    }

    func testInsufficientFiresOnceAndRearmsOnRecovery() {
        var alerts = BalanceAlerts()

        XCTAssertTrue(evaluate(&alerts, isAvailable: false, balance: 5).contains(.insufficientBalance))
        XCTAssertTrue(alerts.insufficientNotified)

        // Still insufficient: no repeat notification.
        XCTAssertTrue(evaluate(&alerts, isAvailable: false, balance: 5).isEmpty)

        // Recovery re-arms the alert.
        XCTAssertTrue(evaluate(&alerts, isAvailable: true, balance: 50).isEmpty)
        XCTAssertFalse(alerts.insufficientNotified)

        XCTAssertTrue(evaluate(&alerts, isAvailable: false, balance: 5).contains(.insufficientBalance))
    }

    func testLowBalanceFiresOnceBelowThresholdAndRearms() {
        var alerts = BalanceAlerts()

        XCTAssertTrue(evaluate(&alerts, balance: 9, threshold: 10).contains(.lowBalance))
        XCTAssertTrue(evaluate(&alerts, balance: 9, threshold: 10).isEmpty, "no repeat while still low")

        // Recovery re-arms.
        XCTAssertTrue(evaluate(&alerts, balance: 11, threshold: 10).isEmpty)
        XCTAssertFalse(alerts.lowBalanceNotified)

        // Threshold is inclusive (balance == threshold fires).
        XCTAssertTrue(evaluate(&alerts, balance: 10, threshold: 10).contains(.lowBalance))
    }

    func testDisabledThresholdNeverFires() {
        var alerts = BalanceAlerts()
        XCTAssertTrue(evaluate(&alerts, balance: 1, enabled: false, threshold: 10).isEmpty)
        XCTAssertFalse(alerts.lowBalanceNotified)
    }

    func testNoBalanceProducesNoActions() {
        var alerts = BalanceAlerts()
        XCTAssertTrue(evaluate(&alerts, balance: nil).isEmpty)
    }

    func testInsufficientAndLowBalanceCanFireTogether() {
        var alerts = BalanceAlerts()
        let actions = evaluate(&alerts, isAvailable: false, balance: 2, threshold: 10)
        XCTAssertEqual(actions, [.insufficientBalance, .lowBalance])
    }
}
