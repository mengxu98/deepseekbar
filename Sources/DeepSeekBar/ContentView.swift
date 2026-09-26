import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    /// Asked for when inline editing changes the body's natural height, so
    /// the popover can grow instead of making the user scroll.
    var onContentSizeChange: () -> Void = {}
    @State private var pendingDeleteAccountID: UUID?
    /// The gear swaps the body for an inline settings page.
    @State private var showsSettings = false
    /// Custom refresh interval, edited in place in the footer.
    @State private var isEditingInterval = false
    @State private var intervalDraft = ""
    @FocusState private var intervalFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                PopoverBody(
                    viewModel: viewModel,
                    pendingDeleteAccountID: $pendingDeleteAccountID,
                    showsSettings: $showsSettings,
                    onContentSizeChange: onContentSizeChange
                )
            }
            Divider()
            footer
        }
        .frame(width: PopoverSizing.width)
        .foregroundStyle(.primary)
        .background(panelBackgroundColor)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("deepseekbar")
                .font(DSFont.title)

            Text(viewModel.keySource.label)
                .font(DSFont.captionMedium)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.row)
                        .fill(statusColor.opacity(0.14))
                )
                .foregroundColor(statusColor)

            Spacer()

            Button {
                viewModel.openConsole()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.tr("Open DeepSeek Console"))
            .accessibilityLabel(L10n.tr("Open DeepSeek Console"))
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DSSpacing.s) {
            if isEditingInterval {
                intervalEditor
            } else {
                footerStatus
            }

            Spacer(minLength: DSSpacing.xs)

            Button {
                showsSettings.toggle()
                onContentSizeChange()
            } label: {
                Image(systemName: "gearshape")
                    .font(DSFont.bodyMedium)
                    .foregroundColor(showsSettings ? .dsBlue : .primary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.tr("Settings"))
            .accessibilityLabel(L10n.tr("Settings"))

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.tr("Quit DeepSeekBar"))
            .accessibilityLabel(L10n.tr("Quit DeepSeekBar"))
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
    }

    private var footerStatus: some View {
        HStack(spacing: 6) {
            Text(updatedText)
                .font(DSFont.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            Text("·")
                .font(DSFont.caption)
                .foregroundColor(.secondary.opacity(0.7))

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: viewModel.isRefreshing ? "hourglass" : "arrow.clockwise")
                    .font(DSFont.bodyMedium)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(viewModel.isRefreshing)
            .help(L10n.tr("Refresh now"))
            .accessibilityLabel(L10n.tr("Refresh now"))

            Menu {
                Button(L10n.trf("%d min", 1)) {
                    viewModel.setRefreshInterval(1)
                }
                Button(L10n.trf("%d min", 5)) {
                    viewModel.setRefreshInterval(5)
                }
                Button(L10n.trf("%d min", 10)) {
                    viewModel.setRefreshInterval(10)
                }
                Divider()
                Button(L10n.tr("Custom...")) {
                    startEditingInterval()
                }
            } label: {
                Text(L10n.trf("%d min", viewModel.refreshIntervalMinutes))
                    .font(DSFont.captionMedium)
            }
            .menuStyle(.borderlessButton)
            .focusable(false)
            .fixedSize()
            .accessibilityLabel(L10n.tr("Refresh interval"))

            Button {
                handleUpdateAction()
            } label: {
                Image(systemName: updateIconName)
                    .font(DSFont.bodyMedium)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(updateButtonDisabled)
            .foregroundColor(updateButtonColor)
            .help(updateHelpText)
            .accessibilityLabel(updateHelpText)
        }
    }

    /// In-place editor for a custom refresh interval — replaces the status
    /// group in the footer instead of opening a panel.
    private var intervalEditor: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "timer")
                .font(DSFont.caption)
                .foregroundColor(.secondary)

            TextField("5", text: $intervalDraft)
                .textFieldStyle(.plain)
                .font(DSFont.captionMedium)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 34)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.row)
                        .fill(Color.dsControlFill)
                )
                .focused($intervalFieldFocused)
                .onSubmit(commitInterval)
                .onExitCommand(perform: cancelIntervalEdit)
                .accessibilityLabel(L10n.tr("Refresh interval"))

            Text(L10n.tr("min"))
                .font(DSFont.caption)
                .foregroundColor(.secondary)

            Button(action: commitInterval) {
                Image(systemName: "checkmark.circle.fill")
                    .font(DSFont.body)
                    .foregroundColor(parsedInterval == nil ? .secondary : .dsBlue)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(parsedInterval == nil)
            .help(L10n.tr("Save"))
            .accessibilityLabel(L10n.tr("Save"))

            Button(action: cancelIntervalEdit) {
                Image(systemName: "xmark.circle.fill")
                    .font(DSFont.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.tr("Cancel"))
            .accessibilityLabel(L10n.tr("Cancel"))
        }
    }

    private var parsedInterval: Int? {
        guard let value = Int(intervalDraft.trimmingCharacters(in: .whitespaces)),
              (1...1_440).contains(value) else {
            return nil
        }
        return value
    }

    private func startEditingInterval() {
        intervalDraft = "\(viewModel.refreshIntervalMinutes)"
        isEditingInterval = true
        DispatchQueue.main.async { intervalFieldFocused = true }
    }

    private func commitInterval() {
        guard let minutes = parsedInterval else { return }
        viewModel.setRefreshInterval(minutes)
        isEditingInterval = false
    }

    private func cancelIntervalEdit() {
        isEditingInterval = false
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
            return .dsBlue
        case .failed:
            return .dsAmber
        default:
            return .secondary
        }
    }

    private var updateHelpText: String {
        switch viewModel.updateState {
        case .checking:
            return L10n.tr("Checking for updates")
        case let .available(update):
            return L10n.trf("Download DeepSeekBar %@", update.latestVersion)
        case let .upToDate(version):
            return L10n.trf("DeepSeekBar is up to date (%@)", version)
        case .failed:
            return L10n.tr("Update check failed; click to retry")
        case .idle:
            return L10n.tr("Check for updates")
        }
    }

    private var statusColor: Color {
        if viewModel.balance.errorMessage != nil {
            return .dsRed
        }
        if viewModel.balance.hasBalance, !viewModel.balance.isAvailable {
            return .dsAmber
        }
        return viewModel.balance.hasBalance ? .dsBlue : .secondary
    }

    private var updatedText: String {
        guard let updatedAt = viewModel.balance.updatedAt else {
            return L10n.tr("Not updated")
        }
        let time = updatedAt.formatted(date: .omitted, time: .standard)
        return viewModel.balance.errorMessage == nil
            ? L10n.trf("Updated %@", time)
            : L10n.trf("Failed %@", time)
    }
}

// MARK: - Body

/// The scrollable card stack. Extracted from ContentView so snapshot tests
/// can render it directly (ImageRenderer does not draw ScrollView content).
struct PopoverBody: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var pendingDeleteAccountID: UUID?
    /// Set by the footer gear: the body becomes the settings page.
    @Binding var showsSettings: Bool
    var onContentSizeChange: () -> Void = {}
    /// Account currently being renamed in place (nil = none).
    @State private var editingAccountID: UUID?
    /// Inline "add API key" form visibility.
    @State private var isAddingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if showsSettings {
                SettingsCard(viewModel: viewModel, onDone: { showsSettings = false })
            } else {
                accountContent
            }
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.s)
        // Inline editors change the body's natural height; ask the popover
        // to re-fit whenever they open or close.
        .onChange(of: isAddingKey) { _ in onContentSizeChange() }
        .onChange(of: editingAccountID) { _ in onContentSizeChange() }
        .onChange(of: showsSettings) { _ in onContentSizeChange() }
        .onChange(of: pendingDeleteAccountID) { _ in onContentSizeChange() }
    }

    @ViewBuilder
    private var accountContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if case let .available(update) = viewModel.updateState {
                updateBanner(update)
            }
            if case let .failed(message) = viewModel.updateState {
                errorBanner(L10n.trf("Update check failed: %@", message))
            }
            if let settingsMessage = viewModel.settingsMessage {
                errorBanner(settingsMessage)
            }
            // Peak / off-peak pricing needs no API key, so the card leads
            // the body and is shown in every account state.
            PricingCard(schedule: viewModel.holidaySchedule, frozenAt: viewModel.demoInstant)
            if viewModel.needsOnboarding {
                if isAddingKey {
                    addKeyCard
                } else {
                    onboardingCard
                }
            } else {
                if viewModel.balance.hasBalance, !viewModel.balance.isAvailable {
                    warningBanner(L10n.tr("Balance insufficient — API calls may fail. Top up at platform.deepseek.com."))
                }
                accountsCard
                usageCard
                if viewModel.balance.isKeyInvalid {
                    keyInvalidBanner
                } else if let error = viewModel.balance.errorMessage {
                    errorBanner(error)
                }
            }
        }
    }

    // MARK: Onboarding

    private var onboardingCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 26))
                .foregroundColor(.dsBlue)
            Text(L10n.tr("Track your DeepSeek balance"))
                .font(DSFont.title)
            Text(L10n.tr("Add an API key to monitor balance and usage from the menu bar."))
                .font(DSFont.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            modalPrimaryButton(L10n.tr("Add API Key")) {
                isAddingKey = true
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .cardBackground()
    }

    // MARK: Accounts

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack {
                Text(L10n.tr("API Keys"))
                    .font(DSFont.section)
                Spacer()
                Button {
                    isAddingKey.toggle()
                } label: {
                    Image(systemName: isAddingKey ? "minus.circle" : "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(L10n.tr("Add API Key"))
                .accessibilityLabel(L10n.tr("Add API Key"))
            }

            if viewModel.accounts.isEmpty {
                Text(viewModel.keySource == .environment
                    ? L10n.tr("Using DEEPSEEK_API_KEY from the environment.")
                    : L10n.tr("No API key added."))
                    .font(DSFont.body)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: DSSpacing.s) {
                    ForEach(viewModel.accounts) { account in
                        accountRow(account)
                    }
                }
            }

            if isAddingKey {
                InlineKeyEditor(
                    onSave: { draft in
                        do {
                            try viewModel.saveAPIKey(draft.key, name: draft.name)
                            isAddingKey = false
                            return nil
                        } catch {
                            return error.localizedDescription
                        }
                    },
                    onCancel: { isAddingKey = false }
                )
                .rowBackground()
            }
        }
        .cardBackground()
    }

    /// Onboarding variant of the inline form: same editor, card chrome.
    private var addKeyCard: some View {
        InlineKeyEditor(
            onSave: { draft in
                do {
                    try viewModel.saveAPIKey(draft.key, name: draft.name)
                    isAddingKey = false
                    return nil
                } catch {
                    return error.localizedDescription
                }
            },
            onCancel: { isAddingKey = false }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private func accountRow(_ account: APIKeyAccount) -> some View {
        if pendingDeleteAccountID == account.id {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "trash")
                    .font(DSFont.caption)
                    .foregroundColor(.dsRed)
                Text(L10n.trf("Delete key %@?", account.displayName))
                    .font(DSFont.bodyMedium)
                    .lineLimit(1)
                Spacer(minLength: DSSpacing.xs)
                Button(L10n.tr("Cancel")) {
                    pendingDeleteAccountID = nil
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(DSFont.captionMedium)

                Button(L10n.tr("Delete")) {
                    pendingDeleteAccountID = nil
                    viewModel.removeAccount(account)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(DSFont.captionSemibold)
                .foregroundColor(.dsRed)
            }
            .padding(.horizontal, DSSpacing.s)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.row)
                    .fill(Color.dsRedTint)
            )
        } else if editingAccountID == account.id {
            InlineRenameField(
                initialName: account.displayName,
                maskedKey: account.maskedKey,
                onSave: { newName in
                    do {
                        try viewModel.renameAccount(account, to: newName)
                        editingAccountID = nil
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                },
                onCancel: { editingAccountID = nil }
            )
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.row)
                    .fill(Color.dsRowFill)
            )
        } else {
            accountRowContent(account)
        }
    }

    private func accountRowContent(_ account: APIKeyAccount) -> some View {
        let isActive = account.id == viewModel.activeAccountID
        return HStack(alignment: .center, spacing: DSSpacing.s) {
            Circle()
                .fill(isActive ? Color.dsBlue : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(DSFont.bodyMedium)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(accountBalanceText(account))
                        .font(DSFont.bodySemibold)
                        .foregroundColor(accountBalanceColor(account, isActive: isActive))
                        .monospacedDigit()
                        .lineLimit(1)
                }

                Text(account.maskedKey)
                    .font(DSFont.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                pendingDeleteAccountID = nil
                editingAccountID = account.id
            } label: {
                Image(systemName: "pencil")
                    .font(DSFont.caption)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundColor(.secondary)
            .help(L10n.tr("Rename Key"))
            .accessibilityLabel(L10n.trf("Rename key %@", account.displayName))

            Button {
                pendingDeleteAccountID = account.id
            } label: {
                Image(systemName: "trash")
                    .font(DSFont.caption)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundColor(.secondary)
            .accessibilityLabel(L10n.trf("Delete key %@", account.displayName))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.activateAccount(account)
        }
        .frame(height: 44)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.row)
                .fill(isActive ? Color.dsBlueTint : Color.dsRowFill)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.trf("Account %@, balance %@", account.displayName, accountBalanceText(account)))
    }

    /// Amber for a balance that can no longer pay for calls, red for a
    /// failed key; the active account keeps the primary label colour so it
    /// reads as the hero row.
    private func accountBalanceColor(_ account: APIKeyAccount, isActive: Bool) -> Color {
        guard let state = viewModel.accountBalances[account.id] else {
            return .secondary
        }
        if state.errorMessage != nil {
            return .dsRed
        }
        if state.hasBalance, !state.isAvailable {
            return .dsAmber
        }
        return isActive ? .primary : .secondary
    }

    private func accountBalanceText(_ account: APIKeyAccount) -> String {
        guard let state = viewModel.accountBalances[account.id] else {
            return "--"
        }
        if let total = state.totalBalance {
            return total.moneyText(currency: state.currency)
        }
        if state.errorMessage != nil {
            return L10n.tr("Error")
        }
        return "--"
    }

    // MARK: Usage

    private var usageCard: some View {
        let stats = viewModel.usage
        let currency = viewModel.balance.currency

        return VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(L10n.tr("Statistics"))
                .font(DSFont.section)

            statRow(L10n.tr("Today"), used: stats.todayUsed, ratio: spentRatio(spent: stats.todayUsed, balance: stats.balance), color: .dsBlue)
            statRow(L10n.tr("Total"), used: stats.totalUsed, ratio: spentRatio(spent: stats.totalUsed, balance: stats.balance), color: .dsIndigo)

            balanceSplitView(currency: currency)

            Text(L10n.tr("Local balance snapshots; counts balance drops only."))
                .font(DSFont.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .cardBackground()
    }

    private func statRow(_ title: String, used: Double, ratio: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(title)
                    .font(DSFont.bodyMedium)
                Spacer()
                Text(used.moneyText(currency: viewModel.balance.currency))
                    .font(DSFont.body)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            if let ratio {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.16))
                        Capsule()
                            .fill(color)
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

    /// Granted vs topped-up credit. Each gets its own colour dot so the
    /// split reads without a legend.
    @ViewBuilder
    private func balanceSplitView(currency: String) -> some View {
        if let granted = viewModel.balance.grantedBalance,
           let toppedUp = viewModel.balance.toppedUpBalance {
            HStack(spacing: DSSpacing.m) {
                balanceSplitItem(
                    color: .dsGreen,
                    label: L10n.tr("Granted"),
                    value: granted.moneyText(currency: currency)
                )
                balanceSplitItem(
                    color: .dsBlue,
                    label: L10n.tr("Topped up"),
                    value: toppedUp.moneyText(currency: currency)
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func balanceSplitItem(color: Color, label: String, value: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(DSFont.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(DSFont.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    // MARK: Settings (moved to the footer gear → settings panel)

    // MARK: Banners

    private var keyInvalidBanner: some View {
        HStack(alignment: .center, spacing: DSSpacing.s) {
            Image(systemName: "key.slash")
                .foregroundColor(.dsRed)
            Text(L10n.tr("API key is invalid. Replace it to resume monitoring."))
                .font(DSFont.caption)
                .lineLimit(2)
            Spacer(minLength: DSSpacing.xs)
            Button(L10n.tr("Replace")) {
                isAddingKey = true
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(DSFont.captionSemibold)
            .foregroundColor(.dsRed)
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.card)
                .fill(Color.dsRedTint)
        )
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.dsRed)
            Text(error)
                .font(DSFont.caption)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.card)
                .fill(Color.dsRedTint)
        )
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.dsAmber)
            Text(message)
                .font(DSFont.caption)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.card)
                .fill(Color.dsAmberTint)
        )
    }

    private func updateBanner(_ update: AppUpdateInfo) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.s) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.dsBlue)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(L10n.trf("Update %@ available", update.latestVersion))
                    .font(DSFont.captionSemibold)
                Text(L10n.trf("Current %@ · %@", update.currentVersion, update.releaseName))
                    .font(DSFont.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DSSpacing.xs)

            Button(L10n.tr("Open")) {
                viewModel.openUpdateDownload()
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(DSFont.captionSemibold)
            .foregroundColor(.dsBlue)
            .accessibilityLabel(L10n.tr("Open"))
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.card)
                .fill(Color.dsBlueTint)
        )
    }
}
