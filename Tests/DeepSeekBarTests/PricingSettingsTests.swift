import XCTest
@testable import DeepSeekBar

/// View-model wiring for the pricing feature: defaults, persistence, and
/// the notifications the menu bar depends on.
@MainActor
final class PricingSettingsTests: XCTestCase {
    private let suiteName = "DeepSeekBarTests.pricing"

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

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

    func testDefaultsShowTheBadgeButNotTheCountdown() {
        let viewModel = AppViewModel(defaults: makeDefaults())
        XCTAssertTrue(viewModel.showPricingInMenuBar)
        XCTAssertFalse(viewModel.showPricingCountdownInMenuBar)
        XCTAssertTrue(viewModel.holidaySchedule.covers(year: 2026))
        XCTAssertEqual(viewModel.pricing.period, DeepSeekPricing.period(
            at: viewModel.pricing.date, schedule: viewModel.holidaySchedule
        ))
    }

    func testMenuBarPricingSettingsPersist() {
        let defaults = makeDefaults()
        let viewModel = AppViewModel(defaults: defaults)
        viewModel.setShowPricingInMenuBar(false)
        viewModel.setShowPricingCountdownInMenuBar(true)

        XCTAssertEqual(
            defaults.object(forKey: "DeepSeekBar.showPricingInMenuBar") as? Bool, false
        )
        XCTAssertEqual(
            defaults.object(forKey: "DeepSeekBar.showPricingCountdownInMenuBar") as? Bool, true
        )

        let restored = AppViewModel(defaults: defaults)
        XCTAssertFalse(restored.showPricingInMenuBar)
        XCTAssertTrue(restored.showPricingCountdownInMenuBar)
    }

    func testRefreshPricingUpdatesStateAndOnlyNotifiesOnChange() {
        let viewModel = AppViewModel(defaults: makeDefaults())
        var notifications = 0
        viewModel.onStatusItemChange = { notifications += 1 }

        let peak = beijing(2026, 3, 2, 10, 0)
        viewModel.refreshPricing(now: peak)
        XCTAssertEqual(viewModel.pricing.period, .peak)
        XCTAssertEqual(viewModel.pricing.nextSwitch, beijing(2026, 3, 2, 12, 0))
        XCTAssertEqual(notifications, 1)

        // Same instant: nothing changed, so the menu bar is not rebuilt.
        viewModel.refreshPricing(now: peak)
        XCTAssertEqual(notifications, 1)

        // Crossing the switch flips the period and notifies again.
        viewModel.refreshPricing(now: beijing(2026, 3, 2, 12, 0))
        XCTAssertEqual(viewModel.pricing.period, .offPeak)
        XCTAssertEqual(notifications, 2)
    }

    /// Exercises the real RunLoop timer, not just the pure snapshot math.
    func testPricingClockTicksWhileTheCountdownIsOn() async throws {
        let viewModel = AppViewModel(defaults: makeDefaults())
        viewModel.startPricingClock()
        viewModel.setShowPricingCountdownInMenuBar(true)

        let before = viewModel.pricing.date
        try await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertGreaterThan(viewModel.pricing.date, before, "pricing clock did not tick")
        XCTAssertEqual(
            viewModel.pricing.period,
            DeepSeekPricing.period(at: viewModel.pricing.date, schedule: viewModel.holidaySchedule)
        )
    }

    func testHolidayIsReflectedInTheSnapshot() {
        let viewModel = AppViewModel(defaults: makeDefaults())
        viewModel.refreshPricing(now: beijing(2026, 10, 1, 10, 0))
        XCTAssertEqual(viewModel.pricing.period, .offPeak)
        XCTAssertEqual(viewModel.pricing.dayKind, .publicHoliday(.nationalDay))
    }
}
