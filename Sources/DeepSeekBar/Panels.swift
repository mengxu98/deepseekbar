import SwiftUI

struct APIKeyDraft {
    var name: String
    var key: String
}

/// Inline "add API key" form. Rendered inside the popover (account card or
/// onboarding card) instead of a separate floating panel, so the whole flow
/// happens in one place.
struct InlineKeyEditor: View {
    /// Returns an error message to display (the form stays open) or nil on
    /// success (the caller collapses the form).
    var onSave: (APIKeyDraft) -> String?
    var onCancel: () -> Void

    @State private var name = ""
    @State private var key = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case key
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            modalFieldLabel(L10n.tr("Name"))
            TextField(L10n.tr("Default"), text: $name)
                .modalTextField()
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .key }

            HStack {
                modalFieldLabel(L10n.tr("API Key"))
                Spacer()
                Text(L10n.tr("Stored in the macOS Keychain."))
                    .font(DSFont.caption)
                    .foregroundColor(.secondary)
            }
            SecureField("sk-...", text: $key)
                .modalTextField()
                .focused($focusedField, equals: .key)
                .onSubmit(save)
                .onExitCommand(perform: onCancel)

            if !key.isEmpty, !trimmedKey.hasPrefix("sk-") {
                Text(L10n.tr("Official DeepSeek keys start with “sk-”."))
                    .font(DSFont.caption)
                    .foregroundColor(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DSFont.caption)
                    .foregroundColor(.dsRed)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DSSpacing.s) {
                Spacer()
                modalTextButton(L10n.tr("Cancel"), action: onCancel)
                modalPrimaryButton(L10n.tr("Save"), action: save)
                    .disabled(trimmedKey.isEmpty)
            }
        }
        .onAppear { focusedField = .name }
    }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        errorMessage = onSave(APIKeyDraft(name: name, key: key))
    }
}

/// Inline rename field that replaces an account row while editing.
struct InlineRenameField: View {
    let maskedKey: String
    /// Returns an error message to display (editing continues) or nil on
    /// success.
    var onSave: (String) -> String?
    var onCancel: () -> Void

    @State private var name: String
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init(
        initialName: String,
        maskedKey: String,
        onSave: @escaping (String) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.maskedKey = maskedKey
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.s) {
                TextField(L10n.tr("Name"), text: $name)
                    .modalTextField()
                    .focused($isFocused)
                    .onSubmit(save)
                    .onExitCommand(perform: onCancel)
                    .accessibilityLabel(L10n.tr("Name"))

                Button(action: save) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DSFont.body)
                        .foregroundColor(trimmedName.isEmpty ? .secondary : .dsBlue)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(trimmedName.isEmpty)
                .help(L10n.tr("Save"))
                .accessibilityLabel(L10n.tr("Save"))

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DSFont.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(L10n.tr("Cancel"))
                .accessibilityLabel(L10n.tr("Cancel"))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DSFont.caption)
                    .foregroundColor(.dsRed)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(maskedKey)
                    .font(DSFont.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .onAppear { isFocused = true }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        errorMessage = onSave(trimmedName)
    }
}

/// Settings shown as a card inside the popover body (the footer gear swaps
/// the body for this page — no anchored popover).
struct SettingsCard: View {
    @ObservedObject var viewModel: AppViewModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            modalHeader(L10n.tr("Settings"), subtitle: L10n.tr("Menu bar preferences for DeepSeekBar."))

            VStack(alignment: .leading, spacing: DSSpacing.m) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Toggle(isOn: Binding(
                        get: { viewModel.showPricingInMenuBar },
                        set: { viewModel.setShowPricingInMenuBar($0) }
                    )) {
                        Text(L10n.tr("Show peak / off-peak in the menu bar"))
                            .font(DSFont.bodyMedium)
                    }
                    .toggleStyle(.checkbox)
                    .focusable(false)
                    .accessibilityLabel(L10n.tr("Show peak / off-peak in the menu bar"))

                    Toggle(isOn: Binding(
                        get: { viewModel.showPricingCountdownInMenuBar },
                        set: { viewModel.setShowPricingCountdownInMenuBar($0) }
                    )) {
                        Text(L10n.tr("Show countdown to the next price change"))
                            .font(DSFont.bodyMedium)
                    }
                    .toggleStyle(.checkbox)
                    .focusable(false)
                    .disabled(!viewModel.showPricingInMenuBar)
                    .accessibilityLabel(L10n.tr("Show countdown to the next price change"))

                    Text(L10n.tr("Off-peak shows ½, peak shows ×1; DeepSeek sets prices in Beijing time."))
                        .font(DSFont.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { viewModel.toggleLaunchAtLogin($0) }
                )) {
                    Text(L10n.tr("Launch at login"))
                        .font(DSFont.bodyMedium)
                }
                .toggleStyle(.checkbox)
                .focusable(false)
                .accessibilityLabel(L10n.tr("Launch at login"))

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    // Toggle and threshold share one row: the value sits on
                    // the trailing edge instead of stacking under the label.
                    HStack(spacing: DSSpacing.s) {
                        Toggle(isOn: Binding(
                            get: { viewModel.lowBalanceAlertEnabled },
                            set: { viewModel.setLowBalanceAlertEnabled($0) }
                        )) {
                            Text(L10n.tr("Low-balance alert"))
                                .font(DSFont.bodyMedium)
                        }
                        .toggleStyle(.checkbox)
                        .focusable(false)
                        .accessibilityLabel(L10n.tr("Low-balance alert"))

                        Spacer(minLength: DSSpacing.xs)

                        if viewModel.lowBalanceAlertEnabled {
                            Stepper(value: Binding(
                                get: { viewModel.lowBalanceThreshold },
                                set: { viewModel.setLowBalanceThreshold($0) }
                            ), in: 0...100_000, step: 0.5) {
                                Text("\(viewModel.lowBalanceThreshold.formatted(.number.precision(.fractionLength(0...2)))) \(String.currencySymbol(for: viewModel.balance.currency))")
                                    .font(DSFont.captionSemibold)
                                    .monospacedDigit()
                            }
                            .focusable(false)
                            .controlSize(.mini)
                            .help(L10n.tr("Alert threshold in the account's currency"))
                        }
                    }

                    if viewModel.lowBalanceAlertEnabled {
                        Text(L10n.tr("Notifies once when the active account's balance falls to the threshold (in its currency)."))
                            .font(DSFont.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let settingsMessage = viewModel.settingsMessage {
                    Text(settingsMessage)
                        .font(DSFont.caption)
                        .foregroundColor(.dsRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                modalTextButton(L10n.tr("Done"), action: onDone)
            }
        }
        .cardBackground()
    }
}
