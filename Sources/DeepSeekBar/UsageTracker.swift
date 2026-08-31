import Foundation

/// Aggregated usage statistics derived from local balance snapshots.
///
/// DeepSeek's API only exposes the current balance, so usage is estimated
/// from balance drops between refreshes (top-ups reset the baseline).
struct UsageStats: Equatable {
    var todayUsed: Double = 0
    var yesterdayUsed: Double = 0
    var weekUsed: Double = 0
    var monthUsed: Double = 0
    /// Total consumption since the earliest snapshot (i.e. since the last
    /// top-up, which resets the snapshot baseline).
    var totalUsed: Double = 0
    var dailyAverage: Double = 0
    var daysRemaining: Double?
    var balance: Double?
    /// Recent balance history (oldest → newest) for a sparkline.
    var snapshots: [Double] = []

    var hasSnapshots: Bool { snapshots.count > 1 }
}

final class UsageTracker {
    /// One balance observation. Internal (not private) so tests can build
    /// backdated histories.
    struct Snapshot: Codable, Equatable {
        let date: Date
        let balance: Double
    }

    /// Snapshots newer than this window stay raw; older ones are coalesced
    /// into first-of-hour buckets. Without coalescing, the fixed snapshot
    /// cap would expire the month/total baselines for anyone refreshing
    /// more often than every ~7 minutes.
    static let rawWindow: TimeInterval = 24 * 60 * 60
    /// Hard cap on stored snapshots (~5 months of hourly buckets).
    static let maxSnapshots = 4_000

    private let fileManager: FileManager
    private let calendar: Calendar
    private let baseDirectory: URL

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DeepSeekBar", isDirectory: true)
        }
    }

    private func snapshotsURL(namespace: String) -> URL {
        baseDirectory.appendingPathComponent("balance_snapshots_\(safeNamespace(namespace)).json")
    }

    func record(balance: Double, namespace: String, date: Date = Date()) {
        var snapshots = loadSnapshots(namespace: namespace)
        if let last = snapshots.last, Self.isSignificantTopUp(new: balance, previous: last.balance) {
            snapshots.removeAll()
        }
        snapshots.append(Snapshot(date: date, balance: balance))
        saveSnapshots(downsampled(snapshots, now: date), namespace: namespace)
    }

    /// A rise in balance means a top-up (or a granted drip). Only a
    /// significant rise resets the baseline so a few-cent grant cannot wipe
    /// months of history. Trade-off: a top-up smaller than the threshold
    /// shows up as negative usage, which max(0, …) clamps to zero.
    static func isSignificantTopUp(new: Double, previous: Double) -> Bool {
        let increase = new - previous
        guard increase > 0 else { return false }
        return increase >= max(1, previous * 0.01)
    }

    /// Computes usage statistics for the current balance.
    func stats(currentBalance: Double?, namespace: String) -> UsageStats {
        guard let currentBalance else {
            return UsageStats()
        }

        let snapshots = loadSnapshots(namespace: namespace)
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let weekStart = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? todayStart

        let todayBase = baseline(in: snapshots, since: todayStart) ?? currentBalance
        let yesterdayBase = baseline(in: snapshots, since: yesterdayStart) ?? currentBalance
        let weekBase = baseline(in: snapshots, since: weekStart) ?? currentBalance
        let monthBase = baseline(in: snapshots, since: monthStart) ?? currentBalance
        let earliestBase = snapshots.first?.balance ?? currentBalance

        let todayUsed = max(0, todayBase - currentBalance)
        let monthUsed = max(0, monthBase - currentBalance)
        let elapsedDays = max(1, calendar.component(.day, from: now))
        let dailyAverage = monthUsed / Double(elapsedDays)
        let daysRemaining = dailyAverage > 0 ? currentBalance / dailyAverage : nil

        return UsageStats(
            todayUsed: todayUsed,
            yesterdayUsed: max(0, yesterdayBase - todayBase),
            weekUsed: max(0, weekBase - currentBalance),
            monthUsed: monthUsed,
            totalUsed: max(0, earliestBase - currentBalance),
            dailyAverage: dailyAverage,
            daysRemaining: daysRemaining,
            balance: currentBalance,
            snapshots: Array(snapshots.suffix(24).map(\.balance))
        )
    }

    func reset(namespace: String) {
        try? fileManager.removeItem(at: snapshotsURL(namespace: namespace))
    }

    /// Keeps raw snapshots for the recent window and first-of-hour buckets
    /// for older data. First-of-hour preserves the "balance at period start"
    /// semantics that stats() baselines rely on, and is idempotent across
    /// repeated records.
    func downsampled(_ snapshots: [Snapshot], now: Date = Date()) -> [Snapshot] {
        let cutoff = now.addingTimeInterval(-Self.rawWindow)
        let split = snapshots.firstIndex(where: { $0.date >= cutoff }) ?? snapshots.endIndex
        var older = Array(snapshots[..<split])
        if older.count > 1 {
            older = hourlyFirstBuckets(older)
        }
        let recent = Array(snapshots[split...])
        return Array((older + recent).suffix(Self.maxSnapshots))
    }

    private func hourlyFirstBuckets(_ snapshots: [Snapshot]) -> [Snapshot] {
        var result: [Snapshot] = []
        var currentHour: Date?
        for snapshot in snapshots {
            let hour = calendar.dateInterval(of: .hour, for: snapshot.date)?.start ?? snapshot.date
            if hour != currentHour {
                result.append(snapshot)
                currentHour = hour
            }
        }
        return result
    }

    private func baseline(in snapshots: [Snapshot], since start: Date) -> Double? {
        snapshots.first(where: { $0.date >= start })?.balance
    }

    private func loadSnapshots(namespace: String) -> [Snapshot] {
        guard let data = try? Data(contentsOf: snapshotsURL(namespace: namespace)) else {
            return []
        }
        return (try? JSONDecoder().decode([Snapshot].self, from: data)) ?? []
    }

    private func saveSnapshots(_ snapshots: [Snapshot], namespace: String) {
        let url = snapshotsURL(namespace: namespace)
        let dir = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshots) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func safeNamespace(_ namespace: String) -> String {
        namespace
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
    }
}
