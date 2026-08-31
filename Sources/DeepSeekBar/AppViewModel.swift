import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var balance = BalanceState()
    @Published var usage = UsageStats()
    @Published var keySource: APIKeySource = .none
    @Published var accounts: [APIKeyAccount] = []
    @Published var activeAccountID: UUID?
    @Published var accountBalances: [UUID: BalanceState] = [:]
    @Published var refreshIntervalMinutes: Int = 5
    @Published var isRefreshing = false
    @Published var updateState: AppUpdateState = .idle
    @Published var lowBalanceAlertEnabled: Bool = true
    @Published var lowBalanceThreshold: Double = 10
    @Published var launchAtLoginEnabled: Bool = false
    /// Transient feedback for settings actions (e.g. launch-at-login errors).
    @Published var settingsMessage: String?

    var statusUpdater: ((BalanceState) -> Void)?

    private let keyStore = APIKeyStore()
    private let api = DeepSeekAPI()
    private let usageTracker = UsageTracker()
    private let updateChecker = AppUpdateChecker()
    private let defaults: UserDefaults
    private var alerts = BalanceAlerts()
    private var apiKey: String?
    private var timer: Timer?
    private var updateTimer: Timer?
    private var utilityPanel: NSPanel?
    private var settingsMessageTask: Task<Void, Never>?

    private enum DefaultsKeys {
        static let refreshIntervalMinutes = "DeepSeekBar.refreshIntervalMinutes"
        static let lowBalanceAlertEnabled = "DeepSeekBar.lowBalanceAlertEnabled"
        static let lowBalanceThreshold = "DeepSeekBar.lowBalanceThreshold"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedInterval = defaults.integer(forKey: DefaultsKeys.refreshIntervalMinutes)
        if storedInterval > 0 {
            refreshIntervalMinutes = min(max(storedInterval, 1), 1_440)
        }
        if defaults.object(forKey: DefaultsKeys.lowBalanceAlertEnabled) != nil {
            lowBalanceAlertEnabled = defaults.bool(forKey: DefaultsKeys.lowBalanceAlertEnabled)
        }
        if defaults.object(forKey: DefaultsKeys.lowBalanceThreshold) != nil {
            lowBalanceThreshold = min(max(defaults.double(forKey: DefaultsKeys.lowBalanceThreshold), 0), 1_000_000)
        }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func start() {
        if lowBalanceAlertEnabled {
            BalanceNotifier.requestAuthorizationIfNeeded()
        }
        reloadAccounts()
        scheduleTimer()
        scheduleUpdateTimer()
        refresh()
        Task { await checkForUpdates(automatic: true) }
    }

    /// Screenshot-support mode (--demo): fills the UI with synthetic but
    /// healthy state so README figures show a clean panel without touching
    /// the Keychain (whose per-signature authorization dialogs would block
    /// the process) or the network.
    func seedDemo() {
        let now = Date(timeIntervalSince1970: 1_704_076_200)
        let main = APIKeyAccount(id: UUID(), name: "Main", key: "sk-demo000000000001", createdAt: now)
        let backup = APIKeyAccount(id: UUID(), name: "Backup", key: "sk-demo000000000002", createdAt: now)
        accounts = [main, backup]
        activeAccountID = main.id
        keySource = .account("Main")

        let mainBalance = BalanceState(
            totalBalance: 128.42, grantedBalance: 8.42, toppedUpBalance: 120.00,
            currency: "CNY", isAvailable: true, updatedAt: now, errorMessage: nil
        )
        let backupBalance = BalanceState(
            totalBalance: 42.19, grantedBalance: 2.19, toppedUpBalance: 40.00,
            currency: "USD", isAvailable: true, updatedAt: now, errorMessage: nil
        )
        balance = mainBalance
        accountBalances = [main.id: mainBalance, backup.id: backupBalance]
        usage = UsageStats(
            todayUsed: 12.30, yesterdayUsed: 9.80, weekUsed: 55.10, monthUsed: 108.50,
            totalUsed: 188.90, dailyAverage: 3.62, daysRemaining: 35,
            balance: 128.42, snapshots: [130, 129.5, 129.1, 128.8, 128.6, 128.42]
        )
        statusUpdater?(mainBalance)
    }

    var activeAccount: APIKeyAccount? {
        if let activeAccountID {
            return accounts.first(where: { $0.id == activeAccountID })
        }
        return accounts.first
    }

    /// First-run state: nothing configured yet, so the popover should lead
    /// with an "Add API Key" call to action instead of empty cards.
    var needsOnboarding: Bool {
        accounts.isEmpty && keySource == .none
    }

    // MARK: - Refresh

    func refresh() {
        guard !isRefreshing else {
            return
        }

        if accounts.isEmpty == false {
            refreshSavedAccounts()
            return
        }

        guard let apiKey, !apiKey.isEmpty else {
            balance = BalanceState(errorMessage: L10n.tr("Add a DeepSeek API key first."))
            usage = UsageStats()
            statusUpdater?(balance)
            return
        }

        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                let next = try await api.fetchBalance(apiKey: apiKey)
                if let total = next.totalBalance {
                    usageTracker.record(balance: total, namespace: usageNamespace)
                }
                applyBalance(next)
            } catch {
                // Keep the last known balance visible; just flag the failure.
                var failed = balance
                failed.errorMessage = error.localizedDescription
                failed.isKeyInvalid = (error as? APIError) == .invalidKey
                failed.updatedAt = Date()
                balance = failed
                statusUpdater?(failed)
            }
        }
    }

    private func refreshSavedAccounts() {
        isRefreshing = true
        let accounts = accounts
        let activeID = activeAccountID ?? accounts.first?.id

        Task {
            defer { isRefreshing = false }

            // Fetch all accounts concurrently (balance endpoint is cheap and
            // the official concurrency limit is generous). Child tasks only
            // fetch; snapshot recording happens below on the main actor.
            let results = await withTaskGroup(of: (UUID, BalanceState).self, returning: [UUID: BalanceState].self) { group in
                for account in accounts {
                    group.addTask { [api] in
                        do {
                            return (account.id, try await api.fetchBalance(apiKey: account.key))
                        } catch {
                            return (account.id, Self.failedState(error))
                        }
                    }
                }
                var collected: [UUID: BalanceState] = [:]
                for await (id, state) in group {
                    collected[id] = state
                }
                return collected
            }

            var nextBalances = accountBalances
            for (id, state) in results {
                nextBalances[id] = state
                if let total = state.totalBalance {
                    usageTracker.record(balance: total, namespace: id.uuidString)
                }
            }

            accountBalances = nextBalances
            let activeBalance = activeID.flatMap { nextBalances[$0] }
                ?? BalanceState(errorMessage: L10n.tr("Add a DeepSeek API key first."))
            applyBalance(activeBalance)
        }
    }

    nonisolated private static func failedState(_ error: Error) -> BalanceState {
        var failed = BalanceState()
        failed.errorMessage = error.localizedDescription
        failed.isKeyInvalid = (error as? APIError) == .invalidKey
        failed.updatedAt = Date()
        return failed
    }

    /// Applies a freshly fetched balance to the UI and evaluates alerts.
    private func applyBalance(_ next: BalanceState) {
        balance = next
        usage = usageTracker.stats(currentBalance: next.totalBalance, namespace: usageNamespace)
        statusUpdater?(next)

        let actions = alerts.evaluate(
            hasBalance: next.hasBalance,
            isAvailable: next.isAvailable,
            balance: next.totalBalance,
            lowBalanceEnabled: lowBalanceAlertEnabled,
            lowBalanceThreshold: lowBalanceThreshold
        )
        if actions.contains(.insufficientBalance) {
            BalanceNotifier.notifyInsufficient()
        }
        if actions.contains(.lowBalance), let total = next.totalBalance {
            BalanceNotifier.notifyLowBalance(
                balance: total,
                currency: next.currency,
                threshold: lowBalanceThreshold
            )
        }
    }

    // MARK: - Settings

    func setRefreshInterval(_ minutes: Int) {
        refreshIntervalMinutes = min(max(minutes, 1), 1_440)
        defaults.set(refreshIntervalMinutes, forKey: DefaultsKeys.refreshIntervalMinutes)
        scheduleTimer()
    }

    func setLowBalanceThreshold(_ value: Double) {
        lowBalanceThreshold = min(max(value.rounded(toPlaces: 2), 0), 1_000_000)
        defaults.set(lowBalanceThreshold, forKey: DefaultsKeys.lowBalanceThreshold)
    }

    func setLowBalanceAlertEnabled(_ enabled: Bool) {
        lowBalanceAlertEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKeys.lowBalanceAlertEnabled)
        if enabled {
            BalanceNotifier.requestAuthorizationIfNeeded()
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = enabled
            settingsMessage = nil
        } catch {
            // Reflect the actual service state so the toggle never lies.
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            showSettingsMessage(
                L10n.trf("Could not update launch-at-login: %@", error.localizedDescription)
            )
        }
    }

    private func showSettingsMessage(_ message: String) {
        settingsMessageTask?.cancel()
        settingsMessage = message
        settingsMessageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.settingsMessage = nil
        }
    }

    func openConsole() {
        if let url = URL(string: "https://platform.deepseek.com/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Key management

    func saveAPIKey(_ key: String, name: String = "") throws {
        _ = try keyStore.addAccount(name: name, key: key)
        reloadAccounts()
        refresh()
    }

    func renameAccount(_ account: APIKeyAccount, to newName: String) throws {
        try keyStore.updateAccount(id: account.id, name: newName)
        reloadAccounts()
    }

    func activateAccount(_ account: APIKeyAccount) {
        do {
            try keyStore.setActiveAccount(id: account.id)
            reloadAccounts()
            if let cached = accountBalances[account.id] {
                balance = cached
                usage = usageTracker.stats(currentBalance: cached.totalBalance, namespace: usageNamespace)
                statusUpdater?(cached)
            }
            refresh()
        } catch {
            balance = BalanceState(errorMessage: error.localizedDescription)
        }
    }

    func removeAccount(_ account: APIKeyAccount) {
        do {
            try keyStore.removeAccount(id: account.id)
            accountBalances.removeValue(forKey: account.id)
            reloadAccounts()
            refresh()
        } catch {
            balance = BalanceState(errorMessage: error.localizedDescription)
        }
    }

    func clearSavedKey() {
        do {
            try keyStore.clearSavedKey()
            reloadAccounts()
            refresh()
        } catch {
            balance = BalanceState(errorMessage: error.localizedDescription)
        }
    }

    func confirmResetUsage() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Reset usage estimate?")
        alert.informativeText = L10n.tr("This clears local balance snapshots used for daily and monthly estimates.")
        alert.addButton(withTitle: L10n.tr("Reset"))
        alert.addButton(withTitle: L10n.tr("Cancel"))
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        usageTracker.reset(namespace: usageNamespace)
        usage = usageTracker.stats(currentBalance: balance.totalBalance, namespace: usageNamespace)
    }

    // MARK: - Updates

    func checkForUpdates(automatic: Bool) async {
        if case .checking = updateState {
            return
        }

        updateState = .checking
        do {
            if let update = try await updateChecker.check() {
                updateState = .available(update)
            } else {
                updateState = automatic ? .idle : .upToDate(checkedVersion: updateChecker.currentVersion)
            }
        } catch {
            updateState = automatic ? .idle : .failed(error.localizedDescription)
        }
    }

    func openUpdateDownload() {
        guard case let .available(update) = updateState else {
            Task { await checkForUpdates(automatic: false) }
            return
        }
        NSWorkspace.shared.open(update.releaseURL)
    }

    // MARK: - Utility panels

    func promptForRefreshInterval() {
        showUtilityPanel(size: NSSize(width: 300, height: 178)) {
            RefreshIntervalPanelView(
                currentInterval: self.refreshIntervalMinutes,
                onCancel: { [weak self] in
                    self?.closeUtilityPanel()
                },
                onSave: { [weak self] minutes in
                    self?.setRefreshInterval(minutes)
                    self?.closeUtilityPanel()
                }
            )
        }
    }

    func promptForAPIKey() {
        showUtilityPanel(size: NSSize(width: 376, height: 258)) {
            AddAPIKeyPanelView(
                onSave: { [weak self] draft in
                    guard let self else { return nil }
                    do {
                        try self.saveAPIKey(draft.key, name: draft.name)
                        self.closeUtilityPanel()
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                },
                onCancel: { [weak self] in
                    self?.closeUtilityPanel()
                }
            )
        }
    }

    func promptForRename(_ account: APIKeyAccount) {
        showUtilityPanel(size: NSSize(width: 332, height: 168)) {
            RenameAccountPanelView(
                account: account,
                onSave: { [weak self] newName in
                    guard let self else { return nil }
                    do {
                        try self.renameAccount(account, to: newName)
                        self.closeUtilityPanel()
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                },
                onCancel: { [weak self] in
                    self?.closeUtilityPanel()
                }
            )
        }
    }

    private func makeUtilityPanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func showUtilityPanel<PanelContent: View>(
        size: NSSize,
        @ViewBuilder content: @escaping () -> PanelContent
    ) {
        utilityPanel?.close()
        let panel = makeUtilityPanel(size: size)
        panel.contentView = NSHostingView(rootView: content())
        utilityPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func closeUtilityPanel() {
        utilityPanel?.close()
        utilityPanel = nil
    }

    // MARK: - Private

    private var usageNamespace: String {
        activeAccount?.id.uuidString ?? "default"
    }

    private func reloadAccounts() {
        let state = keyStore.loadState()
        accounts = state.accounts
        activeAccountID = state.activeAccountID
        let loaded = keyStore.load()
        apiKey = loaded.key
        keySource = loaded.source
        usage = usageTracker.stats(currentBalance: balance.totalBalance, namespace: usageNamespace)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: TimeInterval(refreshIntervalMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        // .common so the timer keeps firing while menus/trackpads are tracked.
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func scheduleUpdateTimer() {
        updateTimer?.invalidate()
        let newTimer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates(automatic: true)
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        updateTimer = newTimer
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
