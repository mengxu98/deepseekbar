import AppKit
import SwiftUI

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
        button.attributedTitle = Self.makeStatusTitle("DS")
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
        guard let event = NSApp.currentEvent else {
            showPopover()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }
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
        guard let button = statusItem.button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main else {
            return nil
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)
        return max(
            PopoverSizing.minimumHeight,
            buttonFrameOnScreen.minY - screen.visibleFrame.minY - PopoverSizing.verticalMargin
        )
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Add API Key", action: #selector(addKeyFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DeepSeekBar", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshFromMenu() {
        viewModel.refresh()
    }

    @objc private func addKeyFromMenu() {
        viewModel.promptForAPIKey()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateStatusItem(balance: BalanceState) {
        guard let button = statusItem.button else {
            return
        }
        if let total = balance.totalBalance {
            let balanceText = "¥\(String(format: "%.2f", total))"
            button.image = nil
            button.attributedTitle = Self.makeStatusTitle(balanceText)
            button.toolTip = "DeepSeekBar: \(balanceText)"
        } else {
            button.image = nil
            button.attributedTitle = Self.makeStatusTitle("DS")
            button.toolTip = "DeepSeekBar"
        }
    }

    private static func makeStatusTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var balance = BalanceState()
    @Published var usage = UsageEstimate()
    @Published var keySource: APIKeySource = .none
    @Published var accounts: [APIKeyAccount] = []
    @Published var activeAccountID: UUID?
    @Published var accountBalances: [UUID: BalanceState] = [:]
    @Published var refreshIntervalMinutes: Int = 5
    @Published var isRefreshing = false

    var statusUpdater: ((BalanceState) -> Void)?

    private let keyStore = APIKeyStore()
    private let api = DeepSeekAPI()
    private let usageTracker = UsageTracker()
    private var apiKey: String?
    private var timer: Timer?
    private var utilityPanel: NSPanel?

    func start() {
        reloadAccounts()
        scheduleTimer()
        refresh()
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
            usage = UsageEstimate()
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
                usage = usageTracker.estimate(currentBalance: next.totalBalance, namespace: usageNamespace)
                balance = next
                statusUpdater?(next)
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
            var nextBalances = accountBalances

            for account in accounts {
                do {
                    let next = try await api.fetchBalance(apiKey: account.key)
                    nextBalances[account.id] = next
                    if let total = next.totalBalance {
                        usageTracker.record(balance: total, namespace: account.id.uuidString)
                    }
                } catch {
                    var failed = nextBalances[account.id] ?? BalanceState()
                    failed.errorMessage = error.localizedDescription
                    failed.updatedAt = Date()
                    nextBalances[account.id] = failed
                }
            }

            accountBalances = nextBalances
            let activeBalance = activeID.flatMap { nextBalances[$0] } ?? BalanceState(errorMessage: "Add a DeepSeek API key first.")
            balance = activeBalance
            usage = usageTracker.estimate(currentBalance: activeBalance.totalBalance, namespace: usageNamespace)
            statusUpdater?(activeBalance)
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
        showUtilityPanel(size: NSSize(width: 376, height: 348)) {
            AddAPIKeyPanelView(
                onCancel: { [weak self] in
                    self?.closeUtilityPanel()
                },
                onSave: { [weak self] draft in
                    self?.saveAPIKey(
                        draft.key,
                        name: draft.name,
                        baseURL: draft.baseURL,
                        model: draft.model
                    )
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

    func saveAPIKey(
        _ key: String,
        name: String = "",
        baseURL: String = DeepSeekProfilePreset.claudeCodePro1M.baseURL,
        model: String = DeepSeekProfilePreset.claudeCodePro1M.model
    ) {
        do {
            let account = try keyStore.addAccount(name: name, key: key)
            try keyStore.updateAccount(id: account.id, name: account.displayName, baseURL: baseURL, model: model)
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
                usage = usageTracker.estimate(currentBalance: cached.totalBalance, namespace: usageNamespace)
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

    func updateActiveAccount(name: String, baseURL: String, model: String) {
        guard let activeAccount else {
            return
        }

        do {
            try keyStore.updateAccount(id: activeAccount.id, name: name, baseURL: baseURL, model: model)
            reloadAccounts()
        } catch {
            balance = BalanceState(errorMessage: error.localizedDescription)
        }
    }

    func applyPreset(_ preset: DeepSeekProfilePreset) {
        guard let activeAccount else {
            return
        }

        do {
            try keyStore.applyPreset(preset, to: activeAccount.id)
            reloadAccounts()
        } catch {
            balance = BalanceState(errorMessage: error.localizedDescription)
        }
    }

    func copyActiveProfileEnv() {
        guard let activeAccount else {
            return
        }

        let env = """
        export DEEPSEEK_API_KEY="\(activeAccount.key)"
        export DEEPSEEK_BASE_URL="\(activeAccount.baseURL)"
        export DEEPSEEK_MODEL="\(activeAccount.model)"
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(env, forType: .string)
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
        usage = usageTracker.estimate(currentBalance: balance.totalBalance, namespace: usageNamespace)
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
        usage = usageTracker.estimate(currentBalance: balance.totalBalance, namespace: usageNamespace)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshIntervalMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
}

struct APIKeyDraft {
    var name: String
    var key: String
    var baseURL: String
    var model: String
}

struct AddAPIKeyPanelView: View {
    var onCancel: () -> Void
    var onSave: (APIKeyDraft) -> Void

    @State private var name = ""
    @State private var key = ""
    @State private var selectedPreset = DeepSeekProfilePreset.claudeCodePro1M
    @State private var baseURL = DeepSeekProfilePreset.claudeCodePro1M.baseURL

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

                modalFieldLabel("Model")
                HStack(spacing: 6) {
                    ForEach(DeepSeekProfilePreset.allCases) { preset in
                        modelButton(preset)
                    }
                }

                modalFieldLabel("Base URL")
                TextField("https://api.deepseek.com/anthropic", text: $baseURL)
                    .modalTextField()
            }

            HStack {
                Text("URL defaults to DeepSeek's compatible endpoint.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Spacer()
                modalTextButton("Cancel", action: onCancel)
                modalPrimaryButton("Save") {
                    onSave(
                        APIKeyDraft(
                            name: name,
                            key: key,
                            baseURL: baseURL,
                            model: selectedPreset.model
                        )
                    )
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .modalPanelBackground(width: 332)
    }

    private func modelButton(_ preset: DeepSeekProfilePreset) -> some View {
        Button {
            selectedPreset = preset
            baseURL = preset.baseURL
        } label: {
            Text(preset.shortTitle)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selectedPreset == preset ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
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

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Estimated Usage")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Reset") {
                    viewModel.confirmResetUsage()
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(.system(size: 10, weight: .medium))
            }
            usageRow("Today", used: viewModel.usage.todayUsed, budget: viewModel.usage.todayBudget, color: .green)
            usageRow("This Month", used: viewModel.usage.monthUsed, budget: viewModel.usage.monthBudget, color: .accentColor)
            Text("Local balance snapshots; counts balance drops only.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .cardBackground()
    }

    private func usageRow(_ title: String, used: Double, budget: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(used.moneyText) / \(budget?.moneyText ?? "--")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                let ratio = budget.map { $0 > 0 ? min(max(used / $0, 0), 1) : 0 } ?? 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.14))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.78))
                        .frame(width: max(5, proxy.size.width * ratio))
                }
            }
            .frame(height: 5)
        }
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

            Spacer()
            toolbarButton("power", action: { NSApp.terminate(nil) })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func accountRow(_ account: APIKeyAccount) -> some View {
        let isActive = account.id == viewModel.activeAccountID
        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 3) {
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

                Text(account.modelDetailText)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                if isActive {
                    Text("Active")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.green)
                } else {
                    Button("Use") {
                        viewModel.activateAccount(account)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.system(size: 10, weight: .medium))
                }

                Button {
                    viewModel.removeAccount(account)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundColor(.secondary)
            }
            .frame(width: 45, alignment: .trailing)
        }
        .frame(height: 72)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.green.opacity(0.10) : Color.secondary.opacity(0.06))
        )
    }

    private func accountBalanceText(_ account: APIKeyAccount) -> String {
        guard let state = viewModel.accountBalances[account.id] else {
            return "--"
        }
        if let total = state.totalBalance {
            return total.moneyText
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

    private func setIntervalFromFooter(_ minutes: Int) {
        viewModel.setRefreshInterval(minutes)
    }

    private var statusColor: Color {
        if viewModel.balance.errorMessage != nil {
            return .yellow
        }
        return viewModel.balance.hasBalance ? .green : .white.opacity(0.35)
    }

    private var updatedText: String {
        guard let updatedAt = viewModel.balance.updatedAt else {
            return "Not updated"
        }
        return "Updated " + updatedAt.formatted(date: .omitted, time: .standard)
    }
}

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
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
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
