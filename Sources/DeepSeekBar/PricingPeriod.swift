import Foundation

/// DeepSeek's time-of-day pricing.
///
/// Official rule (<https://api-docs.deepseek.com/quick_start/pricing>):
/// off-peak tokens cost half the peak rate. Peak hours are **Beijing time**
/// Monday–Friday 09:00–12:00 and 14:00–18:00, excluding Chinese statutory
/// holidays; every other moment — including weekends and holidays all day —
/// is off-peak. Ranges are half-open: 12:00 sharp is already off-peak,
/// 18:00 sharp is already off-peak, 09:00 sharp is already peak.
///
/// The decision is always made in `Asia/Shanghai`, regardless of the Mac's
/// time zone.
enum PricePeriod: String, CaseIterable, Identifiable, Sendable {
    case peak
    case offPeak

    var id: String { rawValue }

    /// Price relative to the peak rate: `1.0` / `0.5`.
    var priceMultiplier: Double {
        self == .peak ? 1.0 : 0.5
    }

    var isOffPeak: Bool { self == .offPeak }

    /// Compact menu-bar badge ("×1" / "½") — the same symbol the pricing
    /// card explains, so the menu bar never needs more than one glyph.
    var menuBarBadge: String {
        self == .peak ? "×1" : "½"
    }
}

/// Why a given Beijing calendar day is (or is not) all-day off-peak.
enum PricingDayKind: Equatable, Sendable {
    case publicHoliday(HolidayName)
    /// Weekend make-up workday (调休上班): still off-peak all day.
    case alternateWorkday(HolidayName)
    case weekend
    case regularWeekday

    var isAllDayOffPeak: Bool {
        self != .regularWeekday
    }
}

/// The pricing state at one instant, plus the block it sits in.
struct PricingSnapshot: Equatable, Sendable {
    let date: Date
    let period: PricePeriod
    let dayKind: PricingDayKind
    /// Start of the current constant-price block (a transition instant).
    let blockStart: Date
    /// When the price next changes.
    let nextSwitch: Date

    var remaining: TimeInterval {
        max(0, nextSwitch.timeIntervalSince(date))
    }

    /// 0…1 through the current block.
    var progress: Double {
        let length = nextSwitch.timeIntervalSince(blockStart)
        guard length > 0 else { return 0 }
        return min(max(date.timeIntervalSince(blockStart) / length, 0), 1)
    }
}

enum DeepSeekPricing {
    /// Pricing is defined in Beijing time (UTC+8, no daylight saving).
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")
        ?? TimeZone(secondsFromGMT: 8 * 3_600)!

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Peak windows in Beijing time, as half-open [start, end) hour pairs.
    static let peakWindows: [(start: Int, end: Int)] = [(9, 12), (14, 18)]

    /// The four instants per day at which the price can change.
    private static let transitionHours = [9, 12, 14, 18]

    /// How far the transition search looks. The longest bundled off-peak
    /// stretch is the Spring Festival break plus its weekend (≈11 days);
    /// 20 days leaves room for a longer future arrangement.
    private static let searchDays = 20

    // MARK: - Period

    static func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func dayKind(at date: Date, schedule: HolidaySchedule) -> PricingDayKind {
        let key = dayKey(for: date)
        if let holiday = schedule.holiday(on: key) {
            return .publicHoliday(holiday.name)
        }
        if let makeUp = schedule.alternateWorkday(on: key), isWeekend(date) {
            return .alternateWorkday(makeUp.name)
        }
        return isWeekend(date) ? .weekend : .regularWeekday
    }

    /// Weekday as seen in Beijing time (1 = Sunday … 7 = Saturday).
    static func weekday(at date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    static func isWeekend(_ date: Date) -> Bool {
        let weekday = weekday(at: date)
        return weekday == 1 || weekday == 7
    }

    static func period(at date: Date, schedule: HolidaySchedule) -> PricePeriod {
        switch dayKind(at: date, schedule: schedule) {
        case .publicHoliday, .alternateWorkday, .weekend:
            return .offPeak
        case .regularWeekday:
            let hour = calendar.component(.hour, from: date)
            let isPeak = peakWindows.contains { hour >= $0.start && hour < $0.end }
            return isPeak ? .peak : .offPeak
        }
    }

    // MARK: - Snapshot

    static func snapshot(at date: Date, schedule: HolidaySchedule) -> PricingSnapshot {
        PricingSnapshot(
            date: date,
            period: period(at: date, schedule: schedule),
            dayKind: dayKind(at: date, schedule: schedule),
            blockStart: previousSwitch(before: date, schedule: schedule),
            nextSwitch: nextSwitch(after: date, schedule: schedule)
        )
    }

    /// First instant after `date` at which the price differs.
    static func nextSwitch(after date: Date, schedule: HolidaySchedule) -> Date {
        let current = period(at: date, schedule: schedule)
        for candidate in transitionCandidates(around: date) where candidate > date {
            if period(at: candidate, schedule: schedule) != current {
                return candidate
            }
        }
        return date.addingTimeInterval(12 * 3_600)
    }

    /// Instant at which the current block started.
    static func previousSwitch(before date: Date, schedule: HolidaySchedule) -> Date {
        let current = period(at: date, schedule: schedule)
        for candidate in transitionCandidates(around: date).reversed() where candidate <= date {
            let justBefore = candidate.addingTimeInterval(-1)
            if period(at: candidate, schedule: schedule) == current,
               period(at: justBefore, schedule: schedule) != current {
                return candidate
            }
        }
        return date.addingTimeInterval(-12 * 3_600)
    }

    /// Candidate transition instants: 09:00 / 12:00 / 14:00 / 18:00 Beijing
    /// time on each day of a window around `date`.
    private static func transitionCandidates(around date: Date) -> [Date] {
        guard let start = calendar.date(
            byAdding: .day, value: -searchDays, to: calendar.startOfDay(for: date)
        ) else {
            return []
        }
        var candidates: [Date] = []
        candidates.reserveCapacity((searchDays * 2 + 1) * transitionHours.count)
        for offset in 0...(searchDays * 2) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else {
                continue
            }
            for hour in transitionHours {
                if let instant = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) {
                    candidates.append(instant)
                }
            }
        }
        return candidates.sorted()
    }
}

// MARK: - Formatting

enum PricingFormatter {
    /// `09:00` in Beijing time.
    static func clock(_ date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    /// `Mon 09:00`, or `09:00` when the instant is on the current Beijing day.
    static func switchLabel(_ date: Date, relativeTo now: Date) -> String {
        if DeepSeekPricing.calendar.isDate(date, inSameDayAs: now) {
            return clock(date)
        }
        return formatter("EEE HH:mm").string(from: date)
    }

    /// Same instant in the Mac's own time zone, shown only when it differs
    /// from Beijing time so travellers are not surprised.
    static func localClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.uiLocale
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Live countdown: `H:MM:SS`, or `2d 3:04` for long holiday stretches.
    static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 {
            return String(format: "%dd %d:%02d", days, hours, minutes)
        }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    /// Menu-bar countdown: always `HH:MM:SS` (hours are not truncated, so a
    /// long holiday break stays unambiguous).
    static func menuBarCountdown(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        return String(format: "%02d:%02d:%02d",
                      total / 3_600, (total % 3_600) / 60, total % 60)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = L10n.uiLocale
        formatter.timeZone = DeepSeekPricing.timeZone
        formatter.calendar = DeepSeekPricing.calendar
        formatter.dateFormat = format
        return formatter
    }
}
