import Foundation

/// Chinese mainland public-holiday arrangement used by DeepSeek's
/// peak / off-peak pricing.
///
/// Only the State Council holiday calendar matters here: DeepSeek bills
/// weekends and statutory holidays at off-peak rates all day, so a
/// make-up workday that falls on a weekend is *still* off-peak. Those
/// entries are kept for the "why" label in the UI, not for the price math.
///
/// Days are Beijing-time calendar days; `endDayExclusive` follows the
/// official notice style (a holiday listed as `10-01 → 10-08` covers
/// Oct 1 through Oct 7).
struct HolidaySchedule: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case holiday
            /// 调休上班 — a weekend day the State Council turns into a workday.
            case alternateWorkday
        }

        let kind: Kind
        /// `yyyy-MM-dd`, inclusive.
        let startDay: String
        /// `yyyy-MM-dd`, exclusive.
        let endDayExclusive: String
        let name: HolidayName

        func contains(_ dayKey: String) -> Bool {
            startDay <= dayKey && dayKey < endDayExclusive
        }
    }

    let entries: [Entry]

    /// Years with at least one statutory-holiday entry bundled.
    var coveredYears: Set<Int> {
        Set(entries.compactMap { Int($0.startDay.prefix(4)) })
    }

    func covers(year: Int) -> Bool {
        coveredYears.contains(year)
    }

    func holiday(on dayKey: String) -> Entry? {
        entries.first { $0.kind == .holiday && $0.contains(dayKey) }
    }

    func alternateWorkday(on dayKey: String) -> Entry? {
        entries.first { $0.kind == .alternateWorkday && $0.contains(dayKey) }
    }

    /// Shipped fallback for 2026 (国务院办公厅 国办发明电〔2025〕7号,
    /// <https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm>).
    /// The app keeps working — weekday/weekend rules only — for years the
    /// table does not cover yet, and says so in the pricing card.
    static let bundled2026 = HolidaySchedule(entries: [
        Entry(kind: .holiday, startDay: "2026-01-01", endDayExclusive: "2026-01-04", name: .newYear),
        Entry(kind: .alternateWorkday, startDay: "2026-01-04", endDayExclusive: "2026-01-05", name: .newYear),

        Entry(kind: .alternateWorkday, startDay: "2026-02-14", endDayExclusive: "2026-02-15", name: .springFestival),
        Entry(kind: .holiday, startDay: "2026-02-15", endDayExclusive: "2026-02-24", name: .springFestival),
        Entry(kind: .alternateWorkday, startDay: "2026-02-28", endDayExclusive: "2026-03-01", name: .springFestival),

        Entry(kind: .holiday, startDay: "2026-04-04", endDayExclusive: "2026-04-07", name: .qingming),

        Entry(kind: .holiday, startDay: "2026-05-01", endDayExclusive: "2026-05-06", name: .labourDay),
        Entry(kind: .alternateWorkday, startDay: "2026-05-09", endDayExclusive: "2026-05-10", name: .labourDay),

        Entry(kind: .holiday, startDay: "2026-06-19", endDayExclusive: "2026-06-22", name: .dragonBoat),

        Entry(kind: .alternateWorkday, startDay: "2026-09-20", endDayExclusive: "2026-09-21", name: .nationalDay),
        Entry(kind: .holiday, startDay: "2026-09-25", endDayExclusive: "2026-09-28", name: .midAutumn),

        Entry(kind: .holiday, startDay: "2026-10-01", endDayExclusive: "2026-10-08", name: .nationalDay),
        Entry(kind: .alternateWorkday, startDay: "2026-10-10", endDayExclusive: "2026-10-11", name: .nationalDay),
    ])
}

/// Statutory holidays of the Chinese mainland, in the order the State
/// Council lists them. Names are localized at the UI layer.
enum HolidayName: String, CaseIterable, Equatable, Sendable {
    case newYear
    case springFestival
    case qingming
    case labourDay
    case dragonBoat
    case midAutumn
    case nationalDay

    var localizedName: String {
        switch self {
        case .newYear: return L10n.tr("New Year's Day")
        case .springFestival: return L10n.tr("Spring Festival")
        case .qingming: return L10n.tr("Qingming Festival")
        case .labourDay: return L10n.tr("Labour Day")
        case .dragonBoat: return L10n.tr("Dragon Boat Festival")
        case .midAutumn: return L10n.tr("Mid-Autumn Festival")
        case .nationalDay: return L10n.tr("National Day")
        }
    }
}
