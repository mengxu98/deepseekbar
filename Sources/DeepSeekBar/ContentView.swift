import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var pendingDeleteAccountID: UUID?
    @State private var settingsPopoverPresented = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                PopoverBody(viewModel: viewModel, pendingDeleteAccountID: $pendingDeleteAccountID)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text(updatedText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .monospacedDigit()

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
                    viewModel.promptForRefreshInterval()
                }
            } label: {
                Text(L10n.trf("%d min", viewModel.refreshIntervalMinutes))
                    .font(.system(size: 10, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .focusable(false)
            .fixedSize()
            .accessibilityLabel(L10n.tr("Refresh interval"))

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
            .accessibilityLabel(updateHelpText)

            Spacer()

            Button {
                settingsPopoverPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.tr("Settings"))
            .accessibilityLabel(L10n.tr("Settings"))
            .popover(isPresented: $settingsPopoverPresented, arrowEdge: .bottom) {
                SettingsPanelView(
                    viewModel: viewModel,
                    onDone: { settingsPopoverPresented = false }
                )
            }

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
            return .yellow
        }
        if viewModel.balance.hasBalance, !viewModel.balance.isAvailable {
            return .orange
        }
        return viewModel.balance.hasBalance ? .deepSeekBlue : .white.opacity(0.35)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case let .available(update) = viewModel.updateState {
                updateBanner(update)
            }
            if case let .failed(message) = viewModel.updateState {
                errorBanner(L10n.trf("Update check failed: %@", message))
            }
            if let settingsMessage = viewModel.settingsMessage {
                errorBanner(settingsMessage)
            }
            if viewModel.needsOnboarding {
                onboardingCard
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Onboarding

    private var onboardingCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 26))
                .foregroundColor(.deepSeekBlue.opacity(0.85))
            Text(L10n.tr("Track your DeepSeek balance"))
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.tr("Add an API key to monitor balance and usage from the menu bar."))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            modalPrimaryButton(L10n.tr("Add API Key")) {
                viewModel.promptForAPIKey()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .cardBackground()
    }

    // MARK: Accounts

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("API Keys"))
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
                .help(L10n.tr("Add API Key"))
                .accessibilityLabel(L10n.tr("Add API Key"))
            }

            if viewModel.accounts.isEmpty {
                Text(viewModel.keySource == .environment
                    ? L10n.tr("Using DEEPSEEK_API_KEY from the environment.")
                    : L10n.tr("No API key added."))
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
                viewModel.promptForRename(account)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 9.5))
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
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundColor(.secondary)
            .accessibilityLabel(L10n.trf("Delete key %@", account.displayName))
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.trf("Account %@, balance %@", account.displayName, accountBalanceText(account)))
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
            Text(L10n.tr("Delete this key?"))
                .font(.system(size: 12, weight: .semibold))

            Text(account.maskedKey)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Button(L10n.tr("Cancel")) {
                    pendingDeleteAccountID = nil
                }
                .buttonStyle(.plain)
                .focusable(false)

                Spacer(minLength: 0)

                Button(L10n.tr("Delete")) {
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

    // MARK: Usage

    private var usageCard: some View {
        let stats = viewModel.usage
        let currency = viewModel.balance.currency

        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Statistics"))
                .font(.system(size: 12, weight: .semibold))

            statRow(L10n.tr("Today"), used: stats.todayUsed, ratio: spentRatio(spent: stats.todayUsed, balance: stats.balance), color: .deepSeekBlue)
            statRow(L10n.tr("Total"), used: stats.totalUsed, ratio: spentRatio(spent: stats.totalUsed, balance: stats.balance), color: .accentColor)

            Divider()
                .padding(.vertical, 2)

            if stats.dailyAverage > 0 {
                HStack {
                    Text(L10n.tr("Daily avg"))
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

            Text(L10n.tr("Local balance snapshots; counts balance drops only."))
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
            return L10n.trf("Daily avg %@", avg)
        }
        let rounded = max(0, Int(days.rounded()))
        if rounded <= 1 {
            return L10n.trf("Daily avg %@ · ≈1 day left", avg)
        }
        return L10n.trf("Daily avg %@ · ≈%d days left", avg, rounded)
    }

    private func balanceSplitText(currency: String) -> String? {
        guard let granted = viewModel.balance.grantedBalance,
              let toppedUp = viewModel.balance.toppedUpBalance else {
            return nil
        }
        return L10n.trf("Granted %@ · Topped up %@", granted.moneyText(currency: currency), toppedUp.moneyText(currency: currency))
    }

    @ViewBuilder
    private func balanceSparkline(_ values: [Double]) -> some View {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = maxV - minV
        // Flat history (balance barely moved): a straight line adds no
        // information, so show a neutral placeholder instead.
        if span < 0.01 {
            Text(L10n.tr("Balance stable"))
                .font(.system(size: 9.5))
                .foregroundColor(.secondary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
        } else {
            GeometryReader { proxy in
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
        }
    }

    // MARK: Settings (moved to the footer gear → settings panel)

    // MARK: Banners

    private var keyInvalidBanner: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "key.slash")
                .foregroundColor(.red)
            Text(L10n.tr("API key is invalid. Replace it to resume monitoring."))
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(L10n.tr("Replace")) {
                viewModel.promptForAPIKey()
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.08))
        )
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
                Text(L10n.trf("Update %@ available", update.latestVersion))
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.trf("Current %@ · %@", update.currentVersion, update.releaseName))
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(L10n.tr("Open")) {
                viewModel.openUpdateDownload()
            }
            .buttonStyle(.plain)
            .focusable(false)
            .font(.system(size: 10, weight: .semibold))
            .accessibilityLabel(L10n.tr("Open"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.deepSeekBlue.opacity(0.10))
        )
    }
}
