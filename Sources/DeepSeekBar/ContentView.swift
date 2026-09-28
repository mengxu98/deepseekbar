import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    /// Asked for when inline editing changes the body's natural height, so
    /// the popover can grow instead of making the user scroll.
    var onContentSizeChange: () -> Void = {}
    @State private var pendingDeleteAccountID: UUID?
    /// The gear swaps the body for an inline settings page.
    @State private var showsSettings = false
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
        HStack(spacing: DSSpacing.s) {
            Text("deepseekbar")
                .font(DSFont.title)
            Spacer()
            Button { viewModel.openConsole() } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(DSIconButtonStyle())
            .help(L10n.tr("Open DeepSeek Console"))
            .accessibilityLabel(L10n.tr("Open DeepSeek Console"))

            Button {
                showsSettings.toggle()
                onContentSizeChange()
            } label: {
                Image(systemName: showsSettings ? "chevron.left" : "gearshape")
            }
            .buttonStyle(DSIconButtonStyle())
            .help(L10n.tr(showsSettings ? "Back" : "Settings"))
            .accessibilityLabel(L10n.tr(showsSettings ? "Back" : "Settings"))
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.xs)
    }

    private var footer: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: viewModel.balance.errorMessage == nil ? "clock" : "exclamationmark.circle")
                .foregroundColor(viewModel.balance.errorMessage == nil ? .secondary : .dsRed)
            Text(updatedText)
                .monospacedDigit()
                .foregroundColor(.secondary)
            Spacer()
            Button { viewModel.refresh() } label: {
                Image(systemName: viewModel.isRefreshing ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(DSIconButtonStyle())
            .disabled(viewModel.isRefreshing)
            .help(L10n.tr("Refresh now"))
            .accessibilityLabel(L10n.tr("Refresh now"))
        }
        .font(DSFont.caption)
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.xs)
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
    /// Set by the header gear: the body becomes the settings page.
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
        .padding(DSSpacing.m)
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
            if !viewModel.needsOnboarding {
                balanceOverview
            }
            PricingCard(schedule: viewModel.holidaySchedule, frozenAt: viewModel.demoInstant, onContentSizeChange: onContentSizeChange)
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
                usageCard
                Divider()
                accountsCard
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
        .padding(.horizontal, DSSpacing.xs)
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
        return HStack(spacing: DSSpacing.xs) {
            Button { viewModel.activateAccount(account) } label: {
                HStack(spacing: DSSpacing.s) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isActive ? .dsBlue : .secondary)
                        .font(DSFont.body)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(account.displayName)
                            .font(DSFont.bodyMedium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(account.maskedKey)
                            .font(DSFont.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DSSpacing.xs)
                    Text(accountBalanceText(account))
                        .font(DSFont.bodySemibold)
                        .foregroundColor(accountBalanceColor(account, isActive: isActive))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.trf("Account %@, balance %@", account.displayName, accountBalanceText(account)))
            .accessibilityAddTraits(isActive ? .isSelected : [])

            Menu {
                Button(L10n.tr("Rename Key")) {
                    pendingDeleteAccountID = nil
                    editingAccountID = account.id
                }
                Button(L10n.tr("Delete"), role: .destructive) {
                    pendingDeleteAccountID = account.id
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.tr("Account actions"))
            .accessibilityLabel(L10n.trf("Actions for %@", account.displayName))
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xxs)
        .background(RoundedRectangle(cornerRadius: DSRadius.control)
            .fill(isActive ? Color.dsBlueTint : .clear))
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

    // MARK: Balance overview

    private var balanceOverview: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            HStack {
                Text(viewModel.keySource.label)
                    .font(DSFont.bodySemibold)
                    .lineLimit(1)
                Spacer(minLength: DSSpacing.s)
                Image(systemName: "wallet.bifold")
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(viewModel.balance.totalBalance?.moneyText(currency: viewModel.balance.currency) ?? "—")
                    .font(DSFont.hero)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(L10n.tr(viewModel.balance.errorMessage == nil ? "Current balance" : "Last known balance"))
                    .font(DSFont.captionMedium)
                    .foregroundStyle(.white)
            }
            if let toppedUp = viewModel.balance.toppedUpBalance,
               let granted = viewModel.balance.grantedBalance {
                HStack(spacing: DSSpacing.l) {
                    heroDetail("Topped up", value: toppedUp)
                    heroDetail("Granted", value: granted)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsHeroBlue)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card + 2))
    }

    private func heroDetail(_ label: String, value: Double) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text(L10n.tr(label))
                .foregroundStyle(.white)
            Text(value.moneyText(currency: viewModel.balance.currency))
                .monospacedDigit()
        }
        .font(DSFont.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Usage

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack(alignment: .top, spacing: DSSpacing.s) {
                statValue("Today’s estimate", amount: viewModel.usage.todayUsed, accent: .dsTeal, fill: .dsTealTint)
                statValue("Total estimate", amount: viewModel.usage.totalUsed, accent: .dsIndigo, fill: .dsIndigoTint)
            }
            Text(L10n.tr("Local balance snapshots; counts balance drops only."))
                .font(DSFont.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xs)
    }

    private func statValue(_ label: String, amount: Double, accent: Color, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(L10n.tr(label))
                .font(DSFont.captionMedium)
                .foregroundColor(accent)
            Text(amount.moneyText(currency: viewModel.balance.currency))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DSRadius.control).fill(fill))
    }

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
