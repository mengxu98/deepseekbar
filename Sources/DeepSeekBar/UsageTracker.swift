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
    private struct Snapshot: Codable {
        let date: Date
        let balance: Double
    }

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

    func record(balance: Double, namespace: String) {
        var snapshots = loadSnapshots(namespace: namespace)
        if let last = snapshots.last, balance > last.balance {
            snapshots.removeAll()
        }
        snapshots.append(Snapshot(date: Date(), balance: balance))
        saveSnapshots(snapshots.suffix(1_000), namespace: namespace)
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

    private func baseline(in snapshots: [Snapshot], since start: Date) -> Double? {
        snapshots.first(where: { $0.date >= start })?.balance
    }

    private func loadSnapshots(namespace: String) -> [Snapshot] {
        guard let data = try? Data(contentsOf: snapshotsURL(namespace: namespace)) else {
            return []
        }
        return (try? JSONDecoder().decode([Snapshot].self, from: data)) ?? []
    }

    private func saveSnapshots<S: Sequence>(_ snapshots: S, namespace: String) where S.Element == Snapshot {
        let url = snapshotsURL(namespace: namespace)
        let dir = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(Array(snapshots))
        if let data {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func safeNamespace(_ namespace: String) -> String {
        namespace
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
    }
}
