import XCTest
@testable import DeepSeekBar

final class UsageTrackerHistoryTests: XCTestCase {
    private func makeTracker() throws -> (UsageTracker, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (UsageTracker(baseDirectory: dir), dir)
    }

    private func hoursAgo(_ hours: Double, plus minutes: Double = 0) -> Date {
        Date().addingTimeInterval(-hours * 3600 + minutes * 60)
    }

    // MARK: - Top-up threshold

    func testTinyIncreaseKeepsHistory() throws {
        let (tracker, dir) = try makeTracker()
        defer { try? FileManager.default.removeItem(at: dir) }

        tracker.record(balance: 100, namespace: "t")
        // A few-cent grant must not wipe the baseline.
        tracker.record(balance: 100.5, namespace: "t")

        let stats = tracker.stats(currentBalance: 90, namespace: "t")
        XCTAssertEqual(stats.totalUsed, 10, accuracy: 0.001, "history survived the tiny increase")
        XCTAssertFalse(UsageTracker.isSignificantTopUp(new: 100.5, previous: 100))
    }

    func testSignificantIncreaseResetsHistory() throws {
        let (tracker, dir) = try makeTracker()
        defer { try? FileManager.default.removeItem(at: dir) }

        tracker.record(balance: 100, namespace: "t")
        tracker.record(balance: 110, namespace: "t")
        XCTAssertTrue(UsageTracker.isSignificantTopUp(new: 110, previous: 100))

        let stats = tracker.stats(currentBalance: 105, namespace: "t")
        XCTAssertEqual(stats.totalUsed, 5, accuracy: 0.001, "top-up reset the baseline")
    }

    func testThresholdIsRelativeForLargeBalances() {
        // 1% of 10_000 = 100: a +50 drip is not a top-up, +150 is.
        XCTAssertFalse(UsageTracker.isSignificantTopUp(new: 10_050, previous: 10_000))
        XCTAssertTrue(UsageTracker.isSignificantTopUp(new: 10_150, previous: 10_000))
    }

    // MARK: - Downsampling

    func testDownsampleCoalescesOldSnapshotsToHourlyBuckets() {
        let tracker = UsageTracker()
        let calendar = Calendar.current

        // Three observations per hour, five hours, all outside the raw
        // window. Anchored to the hour start so the test cannot straddle
        // an hour boundary depending on the current wall-clock minute.
        let base = calendar.dateInterval(of: .hour, for: Date().addingTimeInterval(-36 * 3600))!.start
        var snapshots: [UsageTracker.Snapshot] = []
        for hour in 0..<5 {
            for minute in [5.0, 20.0, 40.0] {
                snapshots.append(UsageTracker.Snapshot(
                    date: base.addingTimeInterval(Double(hour) * 3600 + minute * 60),
                    balance: 100 - Double(hour)
                ))
            }
        }

        let downsampled = tracker.downsampled(snapshots)
        XCTAssertEqual(downsampled.count, 5, "one bucket per hour")
        // First-of-hour semantics: each bucket keeps the earliest snapshot.
        XCTAssertEqual(downsampled.map(\.balance), [100, 99, 98, 97, 96])
    }

    func testDownsampleKeepsRawWindowUnchanged() {
        let tracker = UsageTracker()
        let snapshots = (0..<50).map { index in
            UsageTracker.Snapshot(date: hoursAgo(1, plus: Double(index)), balance: Double(100 - index))
        }

        XCTAssertEqual(tracker.downsampled(snapshots).count, 50)
    }

    func testDownsampleMergesOldAndRecentData() {
        let tracker = UsageTracker()

        var snapshots: [UsageTracker.Snapshot] = []
        for hour in 1...10 {
            snapshots.append(UsageTracker.Snapshot(date: hoursAgo(Double(hour) + 30), balance: 90))
        }
        snapshots.append(UsageTracker.Snapshot(date: hoursAgo(2), balance: 80))

        let downsampled = tracker.downsampled(snapshots)
        XCTAssertEqual(downsampled.count, 11, "10 hourly buckets + 1 recent raw snapshot")
        XCTAssertEqual(downsampled.last?.balance, 80)
    }

    func testDownsampleCapsTotalCount() {
        let tracker = UsageTracker()
        let snapshots = (0..<4_500).map { index in
            UsageTracker.Snapshot(date: hoursAgo(Double(4_600 - index)), balance: 100)
        }

        let downsampled = tracker.downsampled(snapshots)
        XCTAssertEqual(downsampled.count, UsageTracker.maxSnapshots)
        XCTAssertEqual(downsampled.last?.date, snapshots.last?.date, "newest snapshot survives the cap")
    }

    func testRecordedHistorySurvivesRepeatedRefreshesOverDays() throws {
        let (tracker, dir) = try makeTracker()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 3 days of 30-minute refreshes = 144 records, all beyond the raw
        // window except the last day. Under the old count-cap this would
        // have been the entire stored history.
        let start = Date().addingTimeInterval(-3 * 86_400)
        for step in 0..<144 {
            tracker.record(
                balance: 100 - Double(step) * 0.25,
                namespace: "t",
                date: start.addingTimeInterval(Double(step) * 1_800)
            )
        }

        let stats = tracker.stats(currentBalance: 60, namespace: "t")
        XCTAssertEqual(stats.totalUsed, 40, accuracy: 0.001, "month baseline must survive downsampling")
    }
}
