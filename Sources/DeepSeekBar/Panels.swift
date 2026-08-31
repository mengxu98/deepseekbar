import SwiftUI

struct APIKeyDraft {
    var name: String
    var key: String
}

struct AddAPIKeyPanelView: View {
    /// Saves the draft; returns an error message to display (panel stays
    /// open) or nil on success (panel closes).
    var onSave: (APIKeyDraft) -> String?
    var onCancel: () -> Void

    @State private var name = ""
    @State private var key = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modalHeader(L10n.tr("Add API Key"), subtitle: L10n.tr("Stored in the macOS Keychain."))

            VStack(alignment: .leading, spacing: 9) {
                modalFieldLabel(L10n.tr("Name"))
                TextField(L10n.tr("Default"), text: $name)
                    .modalTextField()

                modalFieldLabel(L10n.tr("API Key"))
                SecureField("sk-...", text: $key)
                    .modalTextField()

                if !key.isEmpty, !key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-") {
                    Text(L10n.tr("Official DeepSeek keys start with “sk-”."))
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            HStack {
                Spacer()
                modalTextButton(L10n.tr("Cancel"), action: onCancel)
                modalPrimaryButton(L10n.tr("Save")) {
                    errorMessage = onSave(APIKeyDraft(name: name, key: key))
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .modalPanelBackground(width: 332)
    }
}

struct RenameAccountPanelView: View {
    let account: APIKeyAccount
    /// Saves the new name; returns an error message to display or nil on
    /// success (panel closes).
    var onSave: (String) -> String?
    var onCancel: () -> Void

    @State private var name: String
    @State private var errorMessage: String?

    init(account: APIKeyAccount, onSave: @escaping (String) -> String?, onCancel: @escaping () -> Void) {
        self.account = account
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: account.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modalHeader(L10n.tr("Rename Key"), subtitle: account.maskedKey)

            VStack(alignment: .leading, spacing: 9) {
                modalFieldLabel(L10n.tr("Name"))
                TextField(account.displayName, text: $name)
                    .modalTextField()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            HStack {
                Spacer()
                modalTextButton(L10n.tr("Cancel"), action: onCancel)
                modalPrimaryButton(L10n.tr("Save")) {
                    errorMessage = onSave(name)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .modalPanelBackground(width: 288)
    }
}

/// Settings content shown in an anchored popover on the footer gear button
/// (system popover provides the surface, so no modal panel chrome here).
struct SettingsPanelView: View {
    @ObservedObject var viewModel: AppViewModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modalHeader(L10n.tr("Settings"), subtitle: L10n.tr("Menu bar preferences for DeepSeekBar."))

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.toggleLaunchAtLogin($0) }
                )) {
                    Text(L10n.tr("Launch at login"))
                        .font(.system(size: 11, weight: .medium))
                }
                .toggleStyle(.checkbox)
                .focusable(false)
                .accessibilityLabel(L10n.tr("Launch at login"))

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { viewModel.lowBalanceAlertEnabled },
                        set: { viewModel.setLowBalanceAlertEnabled($0) }
                    )) {
                        Text(L10n.tr("Low-balance alert"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .toggleStyle(.checkbox)
                    .focusable(false)
                    .accessibilityLabel(L10n.tr("Low-balance alert"))

                    if viewModel.lowBalanceAlertEnabled {
                        HStack(spacing: 8) {
                            Stepper(value: Binding(
                                get: { viewModel.lowBalanceThreshold },
                                set: { viewModel.setLowBalanceThreshold($0) }
                            ), in: 0...100_000, step: 0.5) {
                                Text("\(viewModel.lowBalanceThreshold.formatted(.number.precision(.fractionLength(0...2)))) \(String.currencySymbol(for: viewModel.balance.currency))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .monospacedDigit()
                            }
                            .focusable(false)
                            .controlSize(.mini)
                            .help(L10n.tr("Alert threshold in the account's currency"))
                            Text(L10n.tr("Notifies once when the active account's balance falls to the threshold (in its currency)."))
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                modalTextButton(L10n.tr("Done"), action: onDone)
            }
        }
        .frame(width: 288)
        .padding(14)
    }
}

struct RefreshIntervalPanelView: View {
    var currentInterval: Int
    var onCancel: () -> Void
    var onSave: (Int) -> Void

    @State private var intervalText: String

    private static let allowedRange = 1...1_440

    init(currentInterval: Int, onCancel: @escaping () -> Void, onSave: @escaping (Int) -> Void) {
        self.currentInterval = currentInterval
        self.onCancel = onCancel
        self.onSave = onSave
        _intervalText = State(initialValue: "\(currentInterval)")
    }

    private var parsedInterval: Int? {
        guard let value = Int(intervalText.trimmingCharacters(in: .whitespaces)),
              Self.allowedRange.contains(value) else {
            return nil
        }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modalHeader(L10n.tr("Refresh"), subtitle: L10n.tr("Choose a preset or enter minutes."))

            HStack(spacing: 6) {
                intervalButton(1)
                intervalButton(5)
                intervalButton(10)
            }

            HStack(spacing: 8) {
                TextField("\(currentInterval)", text: $intervalText)
                    .modalTextField()
                    .frame(width: 74)
                Text(L10n.tr("min"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if parsedInterval == nil {
                Text(L10n.trf("Enter a value between %d and %d.", Self.allowedRange.lowerBound, Self.allowedRange.upperBound))
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                modalTextButton(L10n.tr("Cancel"), action: onCancel)
                modalPrimaryButton(L10n.tr("Save")) {
                    if let interval = parsedInterval {
                        onSave(interval)
                    }
                }
                .disabled(parsedInterval == nil)
            }
        }
        .modalPanelBackground(width: 268)
    }

    private func intervalButton(_ minutes: Int) -> some View {
        Button {
            intervalText = "\(minutes)"
        } label: {
            Text(L10n.trf("%d min", minutes))
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
