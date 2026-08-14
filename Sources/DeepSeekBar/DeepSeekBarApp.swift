import AppKit
import SwiftUI
import Foundation

private enum PopoverSizing {
    static let width: CGFloat = 300
    static let preferredHeight: CGFloat = 500
    static let minimumHeight: CGFloat = 360
    static let verticalMargin: CGFloat = 12

    static func clampedHeight(availableHeight: CGFloat?) -> CGFloat {
        let maxHeight = availableHeight ?? preferredHeight
        return min(preferredHeight, max(minimumHeight, maxHeight))
    }
}

private extension Color {
    static let deepSeekBlue = Color(red: 0.10, green: 0.45, blue: 0.88)
}

/// Popover/panel surface: clean white in light mode; the system dark
/// surface in dark mode so sheets don't glare inside a dark UI.
private let panelBackgroundColor = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor.windowBackgroundColor
        : NSColor.white
})

@MainActor
final class DeepSeekBarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = AppViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        configureStatusItem()
        configurePopover()
        viewModel.statusUpdater = { [weak self] balance in
            self?.updateStatusItem(balance: balance)
        }
        viewModel.start()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(editMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DeepSeekBar", action: #selector(quit), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else {
            return
        }
        if let logo = Self.statusLogo {
            button.image = logo
            button.imagePosition = .imageLeading
        }
        button.attributedTitle = Self.makeStatusTitle("")
        button.toolTip = "DeepSeekBar"
        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.focusRingType = .none
    }

    private func configurePopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: PopoverSizing.width, height: PopoverSizing.preferredHeight)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(viewModel: viewModel)
        )
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }
        popover.contentSize = NSSize(
            width: PopoverSizing.width,
            height: PopoverSizing.clampedHeight(availableHeight: availablePopoverHeightBelowStatusItem())
        )
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func availablePopoverHeightBelowStatusItem() -> CGFloat? {
        guard let screen = NSScreen.main else {
            return nil
        }
        let menuBarHeight = NSStatusBar.system.thickness
        let visibleFrame = screen.visibleFrame
        return visibleFrame.height - menuBarHeight - PopoverSizing.verticalMargin
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateStatusItem(balance: BalanceState) {
        guard let button = statusItem.button else {
            return
        }

        if let error = balance.errorMessage {
            button.attributedTitle = Self.makeStatusTitle("DS!", color: .systemYellow)
            button.toolTip = error
        } else if let total = balance.totalBalance {
            if balance.isAvailable {
                button.attributedTitle = Self.makeStatusTitle(total.compactMoneyText)
                button.toolTip = "DeepSeekBar · \(total.moneyText(currency: balance.currency))"
            } else {
                // Balance exists but is insufficient for API calls.
                button.attributedTitle = Self.makeStatusTitle("\(total.compactMoneyText)!", color: .systemOrange)
                button.toolTip = "Balance insufficient for API calls. Top up at platform.deepseek.com."
            }
        } else {
            button.attributedTitle = Self.makeStatusTitle("DS")
            button.toolTip = "DeepSeekBar"
        }
    }

    /// Menu-bar icon from the official deepseek-harness-desktop app
    /// (apps/desktop/resources/trayTemplate@2x.png): designed as a template
    /// image so the system tints it for the current menu-bar appearance.
    private static let statusLogo: NSImage? = {
        guard let url = Bundle.module.url(forResource: "tray-icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }()

    private static func makeStatusTitle(_ text: String, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color
            ]
        )
    }
}

// MARK: - ViewModel

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

    var statusUpdater: ((BalanceState) -> Void)?

    private let keyStore = APIKeyStore()
    private let api = DeepSeekAPI()
    private let usageTracker = UsageTracker()
    private let updateChecker = AppUpdateChecker()
    private var apiKey: String?
    private var timer: Timer?
    private var updateTimer: Timer?
    private var utilityPanel: NSPanel?
    /// True while the balance is insufficient; used to fire the low-balance
    /// notification at most once per insufficient period.
    private var insufficientNotified = false

    func start() {
        BalanceNotifier.requestAuthorizationIfNeeded()
        reloadAccounts()
        scheduleTimer()
        scheduleUpdateTimer()
        refresh()
        Task { await checkForUpdates(automatic: true) }
    }

    var activeAccount: APIKeyAccount? {
        if let activeAccountID {
            return accounts.first(where: { $0.id == activeAccountID })
        }
        return accounts.first
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        if accounts.isEmpty == false {
            refreshSavedAccounts()
            return
        }

        guard let apiKey, !apiKey.isEmpty else {
            balance = BalanceState(errorMessage: "Add a DeepSeek API key first.")
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
                var failed = balance
                failed.errorMessage = error.localizedDescription
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
            // the official concurrency limit is generous).
            let results = await withTaskGroup(of: (UUID, BalanceState).self, returning: [UUID: BalanceState].self) { group in
                for account in accounts {
                    group.addTask { [api] in
                        do {
                            let next = try await api.fetchBalance(apiKey: account.key)
                            if let total = next.totalBalance {
                                self.usageTracker.record(balance: total, namespace: account.id.uuidString)
                            }
                            return (account.id, next)
                        } catch {
                            var failed = BalanceState()
                            failed.errorMessage = error.localizedDescription
                            failed.updatedAt = Date()
                            return (account.id, failed)
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
            }

            accountBalances = nextBalances
            let activeBalance = activeID.flatMap { nextBalances[$0] } ?? BalanceState(errorMessage: "Add a DeepSeek API key first.")
            applyBalance(activeBalance)
        }
    }

    /// Applies a freshly fetched balance to the UI and evaluates alerts.
    private func applyBalance(_ next: BalanceState) {
        balance = next
        usage = usageTracker.stats(currentBalance: next.totalBalance, namespace: usageNamespace)
        statusUpdater?(next)
        evaluateBalanceAlert(next)
    }

    /// Fires the insufficient-balance notification at most once per
    /// insufficient period (re-armed when the balance recovers).
    private func evaluateBalanceAlert(_ next: BalanceState) {
        guard next.hasBalance else { return }
        if next.isAvailable == false {
            if insufficientNotified == false {
                BalanceNotifier.notifyInsufficient()
                insufficientNotified = true
            }
        } else {
            insufficientNotified = false
        }
    }

    func setRefreshInterval(_ minutes: Int) {
        refreshIntervalMinutes = min(max(minutes, 1), 1_440)
        scheduleTimer()
    }

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
        showUtilityPanel(size: NSSize(width: 376, height: 240)) {
            AddAPIKeyPanelView(
                onCancel: { [weak self] in
                    self?.closeUtilityPanel()
                },
                onSave: { [weak self] draft in
                    self?.saveAPIKey(draft.key, name: draft.name)
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

    func saveAPIKey(_ key: String, name: String = "") {
        do {
            _ = try keyStore.addAccount(name: name, key: key)
            reloadAccounts()
            refresh()
        } catch {
            balance = BalanceState(errorMessage: error.localizedDescription)
        }
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
        alert.messageText = "Reset usage estimate?"
        alert.informativeText = "This clears local balance snapshots used for daily and monthly estimates."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        usageTracker.reset(namespace: usageNamespace)
        usage = usageTracker.stats(currentBalance: balance.totalBalance, namespace: usageNamespace)
    }

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

// MARK: - Draft & Panels

struct APIKeyDraft {
    var name: String
    var key: String
}

struct AddAPIKeyPanelView: View {
    var onCancel: () -> Void
    var onSave: (APIKeyDraft) -> Void

    @State private var name = ""
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modalHeader("Add API Key", subtitle: "Stored locally with 0600 permissions.")

            VStack(alignment: .leading, spacing: 9) {
                modalFieldLabel("Name")
                TextField("Default", text: $name)
                    .modalTextField()

                modalFieldLabel("API Key")
                SecureField("sk-...", text: $key)
                    .modalTextField()
            }

            HStack {
                Spacer()
                modalTextButton("Cancel", action: onCancel)
                modalPrimaryButton("Save") {
                    onSave(APIKeyDraft(name: name, key: key))
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .modalPanelBackground(width: 332)
    }
}

struct RefreshIntervalPanelView: View {
    var currentInterval: Int
    var onCancel: () -> Void
    var onSave: (Int) -> Void

    @State private var intervalText: String

    init(currentInterval: Int, onCancel: @escaping () -> Void, onSave: @escaping (Int) -> Void) {
        self.currentInterval = currentInterval
        self.onCancel = onCancel
        self.onSave = onSave
        _intervalText = State(initialValue: "\(currentInterval)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modalHeader("Refresh", subtitle: "Choose a preset or enter minutes.")

            HStack(spacing: 6) {
                intervalButton(1)
                intervalButton(5)
                intervalButton(10)
            }

            HStack(spacing: 8) {
                TextField("\(currentInterval)", text: $intervalText)
                    .modalTextField()
                    .frame(width: 74)
                Text("min")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                Spacer()
                modalTextButton("Cancel", action: onCancel)
                modalPrimaryButton("Save") {
                    onSave(Int(intervalText) ?? currentInterval)
                }
            }
        }
        .modalPanelBackground(width: 268)
    }

    private func intervalButton(_ minutes: Int) -> some View {
        Button {
            intervalText = "\(minutes)"
        } label: {
            Text("\(minutes) min")
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(intervalText == "\(minutes)" ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var pendingDeleteAccountID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                bodyContent
            }
            .frame(height: 413)
            Divider()
            footer
        }
        .frame(width: 300, height: PopoverSizing.preferredHeight)
        .foregroundStyle(.primary)
        .background(panelBackgroundColor)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("deepseekbar")
                .font(.system(size: 13, weight: .semibold))

            Text(viewModel.keySource.label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.12))
                .foregroundColor(statusColor)
                .cornerRadius(4)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case let .available(update) = viewModel.updateState {
                updateBanner(update)
            }
            if case let .failed(message) = viewModel.updateState {
                errorBanner("Update check failed: \(message)")
            }
            if viewModel.balance.hasBalance, !viewModel.balance.isAvailable {
                warningBanner("Balance insufficient — API calls may fail. Top up at platform.deepseek.com.")
            }
            accountsCard
            usageCard
            if let error = viewModel.balance.errorMessage {
                errorBanner(error)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Keys")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    viewModel.promptForAPIKey()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            if viewModel.accounts.isEmpty {
                Text("No API key added.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.accounts) { account in
                        accountRow(account)
                    }
                }
            }
        }
        .cardBackground()
    }

    private var usageCard: some View {
        let stats = viewModel.usage
        let currency = viewModel.balance.currency

        return VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.system(size: 12, weight: .semibold))

            statRow("Today", used: stats.todayUsed, ratio: spentRatio(spent: stats.todayUsed, balance: stats.balance), color: .deepSeekBlue)
            statRow("Total", used: stats.totalUsed, ratio: spentRatio(spent: stats.totalUsed, balance: stats.balance), color: .accentColor)

            Divider()
                .padding(.vertical, 2)

            if stats.dailyAverage > 0 {
                HStack {
                    Text("Daily avg")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(daysRemainingText(stats: stats, currency: currency))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            if stats.hasSnapshots {
                balanceSparkline(stats.snapshots)
            }

            if let split = balanceSplitText(currency: currency) {
                Text(split)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Text("Local balance snapshots; counts balance drops only.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .cardBackground()
    }

    private func statRow(_ title: String, used: Double, ratio: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(used.moneyText(currency: viewModel.balance.currency))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            if let ratio {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.14))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.78))
                            .frame(width: max(5, proxy.size.width * min(max(ratio, 0), 1)))
                    }
                }
                .frame(height: 5)
            }
        }
    }

    /// Share of the current balance spent within the period.
    private func spentRatio(spent: Double, balance: Double?) -> Double? {
        guard let balance, balance + spent > 0 else { return nil }
        return spent / (balance + spent)
    }

    private func daysRemainingText(stats: UsageStats, currency: String) -> String {
        let avg = stats.dailyAverage.moneyText(currency: currency)
        guard let days = stats.daysRemaining else {
            return "Daily avg \(avg)"
        }
        let rounded = max(0, Int(days.rounded()))
        return "\(avg) · ≈\(rounded) day\(rounded == 1 ? "" : "s") left"
    }

    private func balanceSplitText(currency: String) -> String? {
        guard let granted = viewModel.balance.grantedBalance,
              let toppedUp = viewModel.balance.toppedUpBalance else {
            return nil
        }
        return "Granted \(granted.moneyText(currency: currency)) · Topped up \(toppedUp.moneyText(currency: currency))"
    }

    private func balanceSparkline(_ values: [Double]) -> some View {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = maxV - minV
        // Flat history (balance barely moved): a straight line adds no
        // information, so show a neutral placeholder instead.
        if span < 0.01 {
            return AnyView(
                Text("Balance stable")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
            )
        }

        return AnyView(GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) / CGFloat(max(values.count - 1, 1)) * width
                    let y = height - CGFloat((value - minV) / span) * height
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                Color.deepSeekBlue.opacity(0.7),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 26)
        )
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(updatedText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text("·")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: viewModel.isRefreshing ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(viewModel.isRefreshing)

            Menu {
                Button("1 min") {
                    setIntervalFromFooter(1)
                }
                Button("5 min") {
                    setIntervalFromFooter(5)
                }
                Button("10 min") {
                    setIntervalFromFooter(10)
                }
                Divider()
                Button("Custom...") {
                    viewModel.promptForRefreshInterval()
                }
            } label: {
                Text("\(viewModel.refreshIntervalMinutes) min")
                    .font(.system(size: 10, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .focusable(false)
            .fixedSize()

            Button {
                handleUpdateAction()
            } label: {
                Image(systemName: updateIconName)
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(updateButtonDisabled)
            .foregroundColor(updateButtonColor)
            .help(updateHelpText)

            Spacer()
            toolbarButton("power", action: { NSApp.terminate(nil) })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func accountRow(_ account: APIKeyAccount) -> some View {
        let isActive = account.id == viewModel.activeAccountID
        return HStack(alignment: .center, spacing: 7) {
            Circle()
                .fill(isActive ? Color.deepSeekBlue : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(accountBalanceText(account))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                Text(account.maskedKey)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                pendingDeleteAccountID = account.id
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundColor(.secondary)
            .popover(isPresented: deleteConfirmationBinding(for: account)) {
                deleteConfirmationPopover(for: account)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.activateAccount(account)
        }
        .frame(height: 46)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.deepSeekBlue.opacity(0.10) : Color.secondary.opacity(0.06))
        )
    }

    private func accountBalanceText(_ account: APIKeyAccount) -> String {
        guard let state = viewModel.accountBalances[account.id] else {
            return "--"
        }
        if let total = state.totalBalance {
            return total.moneyText(currency: state.currency)
        }
        if state.errorMessage != nil {
            return "Error"
        }
        return "--"
    }

    private func toolbarButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(name)
    }

    private func deleteConfirmationBinding(for account: APIKeyAccount) -> Binding<Bool> {
        Binding(
            get: { pendingDeleteAccountID == account.id },
            set: { isPresented in
                if isPresented == false, pendingDeleteAccountID == account.id {
                    pendingDeleteAccountID = nil
                }
            }
        )
    }

    private func deleteConfirmationPopover(for account: APIKeyAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delete this key?")
                .font(.system(size: 12, weight: .semibold))

            Text(account.maskedKey)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Button("Cancel") {
                    pendingDeleteAccountID = nil
                }
                .buttonStyle(.plain)
                .focusable(false)

                Spacer(minLength: 0)

                Button("Delete") {
                    pendingDeleteAccountID = nil
                    viewModel.removeAccount(account)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundColor(.red)
                .font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(12)
        .frame(width: 178)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(error)
                .font(.caption)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.10))
        )
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.10))
        )
    }

    private func updateBanner(_ update: AppUpdateInfo) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.deepSeekBlue)

            VStack(alignment: .leading, spacing: 1) {
                Text("Update \(update.latestVersion) available")
                    .font(.system(size: 11, weight: .semibold))
                Text("Current \(update.currentVersion) · \(update.releaseName)")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button("Open") {
                viewModel.openUpdateDownload()
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.deepSeekBlue.opacity(0.10))
        )
    }

    private func setIntervalFromFooter(_ minutes: Int) {
        viewModel.setRefreshInterval(minutes)
    }

    private func handleUpdateAction() {
        switch viewModel.updateState {
        case .available:
            viewModel.openUpdateDownload()
        default:
            Task { await viewModel.checkForUpdates(automatic: false) }
        }
    }

    private var updateIconName: String {
        switch viewModel.updateState {
        case .checking:
            return "hourglass"
        case .available:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.circle"
        default:
            return "arrow.down.circle"
        }
    }

    private var updateButtonDisabled: Bool {
        if case .checking = viewModel.updateState {
            return true
        }
        return false
    }

    private var updateButtonColor: Color {
        switch viewModel.updateState {
        case .available:
            return .deepSeekBlue
        case .failed:
            return .yellow
        default:
            return .secondary
        }
    }

    private var updateHelpText: String {
        switch viewModel.updateState {
        case .checking:
            return "Checking for updates"
        case let .available(update):
            return "Open DeepSeekBar \(update.latestVersion)"
        case let .upToDate(version):
            return "DeepSeekBar is up to date (\(version))"
        case .failed:
            return "Update check failed; click to retry"
        case .idle:
            return "Check for updates"
        }
    }

    private var statusColor: Color {
        if viewModel.balance.errorMessage != nil {
            return .yellow
        }
        if viewModel.balance.hasBalance, !viewModel.balance.isAvailable {
            return .orange
        }
        return viewModel.balance.hasBalance ? .deepSeekBlue : .white.opacity(0.35)
    }

    private var updatedText: String {
        guard let updatedAt = viewModel.balance.updatedAt else {
            return "Not updated"
        }
        return "Updated " + updatedAt.formatted(date: .omitted, time: .standard)
    }
}

// MARK: - Shared View Helpers

@MainActor
private func modalHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
        Text(subtitle)
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
            .lineLimit(2)
    }
}

@MainActor
private func modalFieldLabel(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
}

@MainActor
private func modalTextButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.10))
            )
    }
    .buttonStyle(.plain)
    .focusable(false)
}

@MainActor
private func modalPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.88))
            )
    }
    .buttonStyle(.plain)
    .focusable(false)
}

private extension View {
    func modalPanelBackground(width: CGFloat) -> some View {
        frame(width: width)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(panelBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
            )
            .foregroundStyle(.primary)
    }

    func modalTextField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .modalFieldBackground()
    }

    func modalFieldBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    func cardBackground() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
            )
    }

    func cardTitle() -> some View {
        font(.system(size: 12, weight: .semibold))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
