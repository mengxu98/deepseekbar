import Foundation

final class UsageTracker {
    private struct Snapshot: Codable {
        let date: Date
        let balance: Double
    }

    private let fileManager = FileManager.default
    private let calendar = Calendar.current

    private func snapshotsURL(namespace: String) -> URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepSeekBar", isDirectory: true)
        return dir.appendingPathComponent("balance_snapshots_\(safeNamespace(namespace)).json")
    }

    func record(balance: Double, namespace: String) {
        var snapshots = loadSnapshots(namespace: namespace)
        if let last = snapshots.last, balance > last.balance {
            snapshots.removeAll()
        }
        snapshots.append(Snapshot(date: Date(), balance: balance))
        saveSnapshots(snapshots.suffix(1_000), namespace: namespace)
    }

    func estimate(currentBalance: Double?, namespace: String) -> UsageEstimate {
        guard let currentBalance else {
            return UsageEstimate()
        }

        let snapshots = loadSnapshots(namespace: namespace)
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? todayStart

        let todayBaseline = baseline(in: snapshots, since: todayStart) ?? currentBalance
        let monthBaseline = baseline(in: snapshots, since: monthStart) ?? currentBalance

        return UsageEstimate(
            todayUsed: max(0, todayBaseline - currentBalance),
            monthUsed: max(0, monthBaseline - currentBalance),
            todayBudget: todayBaseline,
            monthBudget: monthBaseline
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
