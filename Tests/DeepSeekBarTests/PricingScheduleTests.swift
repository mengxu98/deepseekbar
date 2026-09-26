import XCTest
@testable import DeepSeekBar

/// DeepSeek peak / off-peak rules, from
/// <https://api-docs.deepseek.com/quick_start/pricing>:
/// peak = Beijing time Mon–Fri 09:00–12:00 and 14:00–18:00, excluding
/// statutory holidays; weekends and holidays are off-peak all day.
final class PricingScheduleTests: XCTestCase {
    private let schedule = HolidaySchedule.bundled2026

    /// Builds an instant from Beijing wall-clock components.
    private func beijing(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int, _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return DeepSeekPricing.calendar.date(from: components)!
    }

    // MARK: - Weekday windows

    func testPeakWindowBoundariesAreHalfOpen() {
        // Monday 2026-03-02.
        let cases: [(Int, Int, PricePeriod)] = [
            (8, 59, .offPeak),
            (9, 0, .peak),
            (11, 59, .peak),
            (12, 0, .offPeak),
            (13, 59, .offPeak),
            (14, 0, .peak),
            (17, 59, .peak),
            (18, 0, .offPeak),
            (23, 59, .offPeak),
        ]
        for (hour, minute, expected) in cases {
            let date = beijing(2026, 3, 2, hour, minute)
            XCTAssertEqual(
                DeepSeekPricing.period(at: date, schedule: schedule), expected,
                "expected \(expected) at \(hour):\(String(format: "%02d", minute)) Beijing"
            )
        }
    }

    func testWeekendIsOffPeakAllDay() {
        let saturday = beijing(2026, 3, 7, 10, 0)
        let sunday = beijing(2026, 3, 8, 15, 0)
        XCTAssertEqual(DeepSeekPricing.period(at: saturday, schedule: schedule), .offPeak)
        XCTAssertEqual(DeepSeekPricing.period(at: sunday, schedule: schedule), .offPeak)
        XCTAssertEqual(DeepSeekPricing.dayKind(at: saturday, schedule: schedule), .weekend)
    }

    // MARK: - Statutory holidays (国办发明电〔2025〕7号)

    func testNationalDayWeekIsOffPeakAllDay() {
        // Thursday 2026-10-01 through Wednesday 10-07 are holidays.
        for day in 1...7 {
            let date = beijing(2026, 10, day, 10, 30)
            XCTAssertEqual(DeepSeekPricing.period(at: date, schedule: schedule), .offPeak)
        }
        let firstDay = beijing(2026, 10, 1, 10, 30)
        XCTAssertEqual(
            DeepSeekPricing.dayKind(at: firstDay, schedule: schedule),
            .publicHoliday(.nationalDay)
        )
        // Thursday 10-08 is a regular workday again.
        XCTAssertEqual(
            DeepSeekPricing.period(at: beijing(2026, 10, 8, 10, 30), schedule: schedule),
            .peak
        )
    }

    func testMidAutumnFridayIsOffPeak() {
        let holiday = beijing(2026, 9, 25, 10, 0) // Friday, 中秋节
        let ordinaryFriday = beijing(2026, 9, 24, 10, 0)
        XCTAssertEqual(DeepSeekPricing.period(at: holiday, schedule: schedule), .offPeak)
        XCTAssertEqual(
            DeepSeekPricing.dayKind(at: holiday, schedule: schedule),
            .publicHoliday(.midAutumn)
        )
        XCTAssertEqual(DeepSeekPricing.period(at: ordinaryFriday, schedule: schedule), .peak)
    }

    /// Make-up workdays (调休上班) land on weekends; DeepSeek still bills
    /// those days at off-peak rates all day.
    func testMakeUpWorkdaysOnWeekendsStayOffPeak() {
        for date in [beijing(2026, 9, 20, 10, 0), beijing(2026, 10, 10, 10, 0)] {
            XCTAssertEqual(DeepSeekPricing.period(at: date, schedule: schedule), .offPeak)
        }
        XCTAssertEqual(
            DeepSeekPricing.dayKind(at: beijing(2026, 9, 20, 10, 0), schedule: schedule),
            .alternateWorkday(.nationalDay)
        )
    }

    func testSpringFestivalBreakRunsUntilFebruary24() {
        // Friday 2026-02-13, last regular workday before the break.
        XCTAssertEqual(
            DeepSeekPricing.period(at: beijing(2026, 2, 13, 18, 0), schedule: schedule),
            .offPeak
        )
        // The holiday itself (Monday 02-23) is off-peak all day.
        let holiday = beijing(2026, 2, 23, 10, 0)
        XCTAssertEqual(DeepSeekPricing.period(at: holiday, schedule: schedule), .offPeak)
        XCTAssertEqual(
            DeepSeekPricing.nextSwitch(after: holiday, schedule: schedule),
            beijing(2026, 2, 24, 9, 0)
        )
        XCTAssertEqual(
            DeepSeekPricing.period(at: beijing(2026, 2, 24, 9, 0), schedule: schedule),
            .peak
        )
    }

    func testBundledScheduleMatchesOfficialNotice() {
        XCTAssertTrue(schedule.covers(year: 2026))
        XCTAssertFalse(schedule.covers(year: 2027))
        XCTAssertEqual(schedule.holiday(on: "2026-02-15")?.name, .springFestival)
        XCTAssertEqual(schedule.holiday(on: "2026-02-23")?.name, .springFestival)
        XCTAssertNil(schedule.holiday(on: "2026-02-24"))
        XCTAssertEqual(schedule.holiday(on: "2026-04-06")?.name, .qingming)
        XCTAssertEqual(schedule.holiday(on: "2026-05-05")?.name, .labourDay)
        XCTAssertEqual(schedule.holiday(on: "2026-06-19")?.name, .dragonBoat)
        XCTAssertEqual(schedule.holiday(on: "2026-09-27")?.name, .midAutumn)
        XCTAssertEqual(schedule.holiday(on: "2026-10-07")?.name, .nationalDay)
        XCTAssertNil(schedule.holiday(on: "2026-10-08"))
        XCTAssertEqual(schedule.alternateWorkday(on: "2026-10-10")?.name, .nationalDay)
        XCTAssertNil(schedule.alternateWorkday(on: "2026-10-12"))
    }

    // MARK: - Blocks

    func testFridayEveningBlockRunsToMondayMorning() {
        let fridayEvening = beijing(2026, 3, 6, 18, 0)
        XCTAssertEqual(DeepSeekPricing.period(at: fridayEvening, schedule: schedule), .offPeak)
        XCTAssertEqual(
            DeepSeekPricing.nextSwitch(after: fridayEvening, schedule: schedule),
            beijing(2026, 3, 9, 9, 0)
        )
    }

    func testPeakBlockStartAndProgress() {
        let date = beijing(2026, 3, 2, 10, 0)
        let snapshot = DeepSeekPricing.snapshot(at: date, schedule: schedule)
        XCTAssertEqual(snapshot.period, .peak)
        XCTAssertEqual(snapshot.blockStart, beijing(2026, 3, 2, 9, 0))
        XCTAssertEqual(snapshot.nextSwitch, beijing(2026, 3, 2, 12, 0))
        XCTAssertEqual(snapshot.progress, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testLunchBreakBlock() {
        let date = beijing(2026, 3, 2, 13, 0)
        let snapshot = DeepSeekPricing.snapshot(at: date, schedule: schedule)
        XCTAssertEqual(snapshot.period, .offPeak)
        XCTAssertEqual(snapshot.blockStart, beijing(2026, 3, 2, 12, 0))
        XCTAssertEqual(snapshot.nextSwitch, beijing(2026, 3, 2, 14, 0))
        XCTAssertEqual(snapshot.progress, 0.5, accuracy: 0.0001)
    }

    func testHolidayBlockStartsAtThePreviousEvening() {
        // Wednesday 2026-10-07 is still a holiday; its off-peak block began
        // Wednesday 2026-09-30 at 18:00 (the previous regular workday).
        let date = beijing(2026, 10, 5, 12, 0)
        let snapshot = DeepSeekPricing.snapshot(at: date, schedule: schedule)
        XCTAssertEqual(snapshot.period, .offPeak)
        XCTAssertEqual(snapshot.blockStart, beijing(2026, 9, 30, 18, 0))
        XCTAssertEqual(snapshot.nextSwitch, beijing(2026, 10, 8, 9, 0))
    }

    func testSnapshotExactlyOnASwitch() {
        let snapshot = DeepSeekPricing.snapshot(at: beijing(2026, 3, 2, 12, 0), schedule: schedule)
        XCTAssertEqual(snapshot.period, .offPeak)
        XCTAssertEqual(snapshot.blockStart, beijing(2026, 3, 2, 12, 0))
        XCTAssertEqual(snapshot.nextSwitch, beijing(2026, 3, 2, 14, 0))
        XCTAssertEqual(snapshot.progress, 0, accuracy: 0.0001)
    }

    // MARK: - Time zone and coverage

    func testDecisionsIgnoreTheMachinesTimeZone() {
        // 2026-03-02 01:00 UTC == 09:00 Beijing (Monday, peak starts).
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let startOfPeak = utc.date(from: DateComponents(
            year: 2026, month: 3, day: 2, hour: 1, minute: 0
        ))!
        XCTAssertEqual(DeepSeekPricing.period(at: startOfPeak, schedule: schedule), .peak)

        // 2026-03-01 20:00 UTC is already 2026-03-02 in Beijing.
        let lateUtc = utc.date(from: DateComponents(
            year: 2026, month: 3, day: 1, hour: 20, minute: 0
        ))!
        XCTAssertEqual(DeepSeekPricing.dayKey(for: lateUtc), "2026-03-02")
        XCTAssertEqual(DeepSeekPricing.period(at: lateUtc, schedule: schedule), .offPeak)
    }

    func testUncoveredYearUsesWeekdayRulesOnly() {
        let monday = beijing(2027, 1, 4, 10, 0)
        let saturday = beijing(2027, 1, 2, 10, 0)
        XCTAssertFalse(schedule.covers(year: 2027))
        XCTAssertEqual(DeepSeekPricing.period(at: monday, schedule: schedule), .peak)
        XCTAssertEqual(DeepSeekPricing.period(at: saturday, schedule: schedule), .offPeak)
    }

    // MARK: - Presentation helpers

    func testMenuBarBadges() {
        XCTAssertEqual(PricePeriod.peak.menuBarBadge, "×1")
        XCTAssertEqual(PricePeriod.offPeak.menuBarBadge, "½")
        XCTAssertEqual(PricePeriod.peak.priceMultiplier, 1.0)
        XCTAssertEqual(PricePeriod.offPeak.priceMultiplier, 0.5)
    }

    func testCountdownFormatting() {
        XCTAssertEqual(PricingFormatter.countdown(0), "0:00:00")
        XCTAssertEqual(PricingFormatter.countdown(3_661), "1:01:01")
        XCTAssertEqual(PricingFormatter.countdown(2 * 86_400 + 3 * 3_600 + 4 * 60), "2d 3:04")
        XCTAssertEqual(PricingFormatter.menuBarCountdown(3_661), "01:01:01")
        XCTAssertEqual(PricingFormatter.menuBarCountdown(100 * 3_600), "100:00:00")
    }
}
