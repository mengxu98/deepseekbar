import XCTest
@testable import DeepSeekBar

// MARK: - Official model catalog

final class OfficialModelTests: XCTestCase {
    func testOfficialModels() {
        XCTAssertTrue(DeepSeekOfficialModel.isOfficial("deepseek-v4-pro"))
        XCTAssertTrue(DeepSeekOfficialModel.isOfficial("deepseek-v4-flash"))
    }

    /// Regression guard: the "[1m]" suffix was never an official model name
    /// and the API silently maps unknown names to deepseek-v4-flash.
    func testInventedModelNamesAreRejected() {
        XCTAssertFalse(DeepSeekOfficialModel.isOfficial("deepseek-v4-pro[1m]"))
        XCTAssertFalse(DeepSeekOfficialModel.isOfficial("deepseek-chat"))
        XCTAssertFalse(DeepSeekOfficialModel.isOfficial("deepseek-reasoner"))
    }

    func testOfficialModelCatalog() {
        XCTAssertTrue(DeepSeekOfficialModel.isOfficial("deepseek-v4-pro"))
        XCTAssertTrue(DeepSeekOfficialModel.isOfficial("deepseek-v4-flash"))
        XCTAssertEqual(DeepSeekOfficialModel.all, ["deepseek-v4-pro", "deepseek-v4-flash"])
    }
}

// MARK: - Balance response decoding (official schema)

final class BalanceDecodingTests: XCTestCase {
    private let officialJSON = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "CNY",
          "total_balance": "110.00",
          "granted_balance": "10.00",
          "topped_up_balance": "100.00"
        }
      ]
    }
    """

    func testDecodesOfficialResponse() throws {
        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: Data(officialJSON.utf8))
        XCTAssertTrue(decoded.isAvailable)
        let info = try XCTUnwrap(decoded.balanceInfos.first)
        XCTAssertEqual(info.currency, "CNY")
        XCTAssertEqual(info.totalBalance, "110.00")
        XCTAssertEqual(info.grantedBalance, "10.00")
        XCTAssertEqual(info.toppedUpBalance, "100.00")
    }

    func testBalanceStateMapping() throws {
        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: Data(officialJSON.utf8))
        let state = BalanceState(
            totalBalance: Double(decoded.balanceInfos[0].totalBalance),
            grantedBalance: Double(decoded.balanceInfos[0].grantedBalance),
            toppedUpBalance: Double(decoded.balanceInfos[0].toppedUpBalance),
            currency: decoded.balanceInfos[0].currency,
            isAvailable: decoded.isAvailable,
            updatedAt: Date(),
            errorMessage: nil
        )
        XCTAssertEqual(state.totalBalance, 110.0)
        XCTAssertEqual(state.grantedBalance, 10.0)
        XCTAssertTrue(state.hasBalance)
    }
}

// MARK: - Balance API (mocked URLSession)

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class DeepSeekAPITests: XCTestCase {
    private func makeAPI(status: Int, body: String) -> DeepSeekAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        return DeepSeekAPI(session: URLSession(configuration: config))
    }

    func testFetchBalanceSuccess() async throws {
        let api = makeAPI(status: 200, body: """
        {"is_available": true, "balance_infos": [{"currency": "CNY", "total_balance": "42.50", "granted_balance": "0.00", "topped_up_balance": "42.50"}]}
        """)
        let state = try await api.fetchBalance(apiKey: "sk-test")
        XCTAssertEqual(state.totalBalance, 42.5)
        XCTAssertEqual(state.currency, "CNY")
        XCTAssertTrue(state.isAvailable)
        XCTAssertNil(state.errorMessage)
    }

    func testFetchBalanceUnauthorized() async {
        let api = makeAPI(status: 401, body: "{}")
        do {
            _ = try await api.fetchBalance(apiKey: "sk-bad")
            XCTFail("expected invalidKey error")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalidKey)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFetchBalanceUnavailable() async throws {
        let api = makeAPI(status: 200, body: """
        {"is_available": false, "balance_infos": [{"currency": "CNY", "total_balance": "1.00", "granted_balance": "1.00", "topped_up_balance": "0.00"}]}
        """)
        let state = try await api.fetchBalance(apiKey: "sk-test")
        XCTAssertFalse(state.isAvailable)
        XCTAssertEqual(state.totalBalance, 1.0)
    }
}

// MARK: - Version comparison (update checker)

final class VersionComparisonTests: XCTestCase {
    func testNormalizedVersion() {
        XCTAssertEqual(AppUpdateChecker.normalizedVersion("v1.2.3"), "1.2.3")
        XCTAssertEqual(AppUpdateChecker.normalizedVersion("V2.0.0"), "2.0.0")
        XCTAssertEqual(AppUpdateChecker.normalizedVersion("1.2.3"), "1.2.3")
    }

    func testCompareVersions() {
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.0.0", "1.0.1"), .orderedAscending)
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.2.0", "1.2"), .orderedSame, "zero-padded components compare equal")
        XCTAssertEqual(AppUpdateChecker.compareVersions("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.2.3", "1.2.3"), .orderedSame)
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.10.0", "1.9.0"), .orderedDescending)
    }
}

// MARK: - Usage statistics (sandboxed to temp dir)

final class UsageTrackerTests: XCTestCase {
    private func makeTracker() throws -> (UsageTracker, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (UsageTracker(baseDirectory: dir), dir)
    }

    func testStatsDropsFromBaseline() throws {
        let (tracker, dir) = try makeTracker()
        defer { try? FileManager.default.removeItem(at: dir) }

        tracker.record(balance: 100, namespace: "t")
        tracker.record(balance: 95, namespace: "t")
        let stats = tracker.stats(currentBalance: 90, namespace: "t")
        XCTAssertEqual(stats.todayUsed, 10, accuracy: 0.001)
        XCTAssertEqual(stats.monthUsed, 10, accuracy: 0.001)
        XCTAssertEqual(stats.weekUsed, 10, accuracy: 0.001)
        XCTAssertEqual(stats.totalUsed, 10, accuracy: 0.001)
        XCTAssertEqual(stats.balance, 90)
        XCTAssertTrue(stats.hasSnapshots)
        XCTAssertEqual(stats.snapshots, [100, 95])
    }

    func testTopUpResetsBaseline() throws {
        let (tracker, dir) = try makeTracker()
        defer { try? FileManager.default.removeItem(at: dir) }

        tracker.record(balance: 100, namespace: "t")
        _ = tracker.stats(currentBalance: 90, namespace: "t")
        // Top-up: balance rises above the last snapshot → snapshots reset.
        tracker.record(balance: 150, namespace: "t")
        let stats = tracker.stats(currentBalance: 140, namespace: "t")
        XCTAssertEqual(stats.todayUsed, 10, accuracy: 0.001)
    }

    func testDailyAverageAndDaysRemaining() throws {
        let (tracker, dir) = try makeTracker()
        defer { try? FileManager.default.removeItem(at: dir) }

        tracker.record(balance: 100, namespace: "t")
        // 10 spent so far; elapsed day-of-month >= 1 → daily average <= 10.
        let stats = tracker.stats(currentBalance: 90, namespace: "t")
        XCTAssertGreaterThan(stats.dailyAverage, 0)
        XCTAssertGreaterThanOrEqual(stats.dailyAverage, 10 / 31)
        XCTAssertLessThanOrEqual(stats.dailyAverage, 10)
        if let days = stats.daysRemaining {
            XCTAssertGreaterThan(days, 0)
        } else {
            XCTFail("expected days remaining with positive daily average")
        }
    }

    func testResetClearsSnapshots() throws {
        let (tracker, dir) = try makeTracker()
        defer { try? FileManager.default.removeItem(at: dir) }

        tracker.record(balance: 100, namespace: "t")
        tracker.reset(namespace: "t")
        let stats = tracker.stats(currentBalance: 90, namespace: "t")
        XCTAssertEqual(stats.todayUsed, 0, accuracy: 0.001)
        XCTAssertFalse(stats.hasSnapshots)
    }
}

// MARK: - Money formatting

final class MoneyFormattingTests: XCTestCase {
    func testFormatsWithCurrencyCode() {
        let cny = 110.0.moneyText(currency: "CNY")
        XCTAssertTrue(cny.contains("110.00"))

        let usd = 110.0.moneyText(currency: "USD")
        XCTAssertTrue(usd.contains("110.00"))
        XCTAssertNotEqual(cny, usd, "different currencies must render differently")
    }

    func testCompactMoneyText() {
        XCTAssertEqual(120.0.compactMoneyText, "120")
        XCTAssertEqual(12.34.compactMoneyText, "12.34")
        XCTAssertEqual(0.5.compactMoneyText, "0.50")
    }
}

@MainActor
final class AppViewModelSettingsTests: XCTestCase {
    func testZeroLowBalanceThresholdSurvivesRestart() {
        let suite = "DeepSeekBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.0, forKey: "DeepSeekBar.lowBalanceThreshold")

        XCTAssertEqual(AppViewModel(defaults: defaults).lowBalanceThreshold, 0)
    }
}


