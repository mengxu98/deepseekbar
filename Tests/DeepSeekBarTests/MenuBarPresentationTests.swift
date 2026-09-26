import XCTest
@testable import DeepSeekBar

/// The menu-bar item is the app's primary surface and cannot be asserted
/// from a screenshot, so its composition is a pure, tested function.
final class MenuBarPresentationTests: XCTestCase {
    private let schedule = HolidaySchedule.bundled2026

    private let healthyBalance = BalanceState(
        totalBalance: 128.42,
        grantedBalance: 8.42,
        toppedUpBalance: 120.00,
        currency: "CNY",
        isAvailable: true
    )

    private func beijing(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return DeepSeekPricing.calendar.date(from: components)!
    }

    /// Saturday 2026-03-07 10:00 — off-peak until Monday 09:00 (47 hours).
    private var offPeakSnapshot: PricingSnapshot {
        DeepSeekPricing.snapshot(at: beijing(2026, 3, 7, 10, 0), schedule: schedule)
    }

    /// Monday 2026-03-02 10:00 — peak until 12:00 (2 hours).
    private var peakSnapshot: PricingSnapshot {
        DeepSeekPricing.snapshot(at: beijing(2026, 3, 2, 10, 0), schedule: schedule)
    }

    func testBalanceWithOffPeakBadge() {
        let presentation = MenuBarPresentation(
            balance: healthyBalance,
            pricing: offPeakSnapshot,
            showsPricingCountdown: false
        )
        XCTAssertEqual(presentation.segments.map(\.text), ["¥128", " ½"])
        XCTAssertEqual(presentation.segments.map(\.emphasis), [.primary, .pricing])
    }

    func testPeakBadgeIsSecondaryAndCountdownIsOptional() {
        let withoutCountdown = MenuBarPresentation(
            balance: healthyBalance,
            pricing: peakSnapshot,
            showsPricingCountdown: false
        )
        XCTAssertEqual(withoutCountdown.segments.map(\.text), ["¥128", " ×1"])
        XCTAssertEqual(withoutCountdown.segments.map(\.emphasis), [.primary, .primary])

        let withCountdown = MenuBarPresentation(
            balance: healthyBalance,
            pricing: peakSnapshot,
            showsPricingCountdown: true
        )
        XCTAssertEqual(withCountdown.segments.map(\.text), ["¥128", " ×1", " 02:00:00"])
        // Menu-bar text never drops below label contrast.
        XCTAssertEqual(withCountdown.segments.map(\.emphasis), [.primary, .primary, .primary])
    }

    func testOffPeakCountdownUsesUnpaddedHours() {
        let presentation = MenuBarPresentation(
            balance: healthyBalance,
            pricing: offPeakSnapshot,
            showsPricingCountdown: true
        )
        XCTAssertEqual(presentation.segments.map(\.text), ["¥128", " ½", " 47:00:00"])
        XCTAssertEqual(presentation.segments.map(\.emphasis), [.primary, .pricing, .primary])
    }

    func testPricingCanBeHidden() {
        let presentation = MenuBarPresentation(
            balance: healthyBalance,
            pricing: nil,
            showsPricingCountdown: true
        )
        XCTAssertEqual(presentation.segments.map(\.text), ["¥128"])
        // Currency formatting follows the machine locale — the menu-bar text
        // uses the fixed "¥" symbol, but the tooltip goes through
        // NumberFormatter, which spells it "CN¥" on an en-US runner. Assert
        // the shape, not one spelling.
        XCTAssertTrue(presentation.tooltip.hasPrefix("DeepSeekBar · "))
        XCTAssertTrue(presentation.tooltip.contains("128.42"))
        XCTAssertFalse(presentation.tooltip.contains("½"))
    }

    func testInsufficientBalanceKeepsItsMarkerAndTheBadge() {
        var balance = healthyBalance
        balance.isAvailable = false
        let presentation = MenuBarPresentation(
            balance: balance,
            pricing: offPeakSnapshot,
            showsPricingCountdown: false
        )
        XCTAssertEqual(presentation.segments.map(\.text), ["¥128!", " ½"])
        XCTAssertEqual(presentation.segments.first?.emphasis, .caution)
        XCTAssertTrue(presentation.tooltip.contains("Balance insufficient"))
    }

    func testErrorStateTooltipCarriesTheMessage() {
        let balance = BalanceState(errorMessage: "API key is invalid.")
        let presentation = MenuBarPresentation(
            balance: balance,
            pricing: offPeakSnapshot,
            showsPricingCountdown: false
        )
        XCTAssertEqual(presentation.segments.map(\.text), ["DS!", " ½"])
        XCTAssertEqual(presentation.segments.first?.emphasis, .warning)
        XCTAssertTrue(presentation.tooltip.contains("API key is invalid."))
    }

    func testTooltipDescribesTheNextPriceChange() {
        let offPeak = MenuBarPresentation(
            balance: healthyBalance,
            pricing: offPeakSnapshot,
            showsPricingCountdown: false
        )
        XCTAssertTrue(offPeak.tooltip.contains("Off-peak · half price"))
        XCTAssertTrue(offPeak.tooltip.contains("Full price resumes in 1d 23:00"))

        let peak = MenuBarPresentation(
            balance: healthyBalance,
            pricing: peakSnapshot,
            showsPricingCountdown: false
        )
        XCTAssertTrue(peak.tooltip.contains("Peak · full price"))
        XCTAssertTrue(peak.tooltip.contains("Off-peak starts in 2:00:00"))
    }
}
