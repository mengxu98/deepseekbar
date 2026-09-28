import XCTest
import SwiftUI
@testable import DeepSeekBar

/// Renders the popover UI offscreen to PNGs for visual verification.
/// Not part of the regular test assertions — it only produces image
/// artifacts, so it runs regardless of assertion results.
final class UISnapshotTests: XCTestCase {
    @MainActor
    private func render(_ view: some View, name: String) {
        // No fixed height: a fixed frame centers-and-clips content that
        // overflows it, which would cut off the banner at the top. The
        // real popover's body scrolls, so nothing is clipped there.
        for (suffix, appearanceName, scheme) in [
            ("light", NSAppearance.Name.aqua, ColorScheme.light),
            ("dark", NSAppearance.Name.darkAqua, ColorScheme.dark),
        ] {
            NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
                let renderer = ImageRenderer(content: view
                    .frame(width: PopoverSizing.width)
                    .background(panelBackgroundColor)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let data = rep.representation(using: .png, properties: [:]) else {
                    XCTFail("failed to render \(name)_\(suffix)")
                    return
                }
                let path = "/tmp/dsb_ui_\(name)_\(suffix).png"
                do {
                    try data.write(to: URL(fileURLWithPath: path))
                    print("WROTE \(path)")
                } catch {
                    XCTFail("failed to write \(path): \(error)")
                }
            }
        }
    }

    @MainActor
    private func seed(_ vm: AppViewModel) {
        let now = Date()
        vm.accounts = [
            APIKeyAccount(id: UUID(), name: "Main", key: "sk-abcdef1234567890xyz", createdAt: now),
            APIKeyAccount(id: UUID(), name: "Backup", key: "sk-zyxwvu0987654321abc", createdAt: now),
        ]
        vm.activeAccountID = vm.accounts[0].id
        vm.keySource = .account("Main")
        vm.balance = BalanceState(
            totalBalance: 128.42, grantedBalance: 8.42, toppedUpBalance: 120.00,
            currency: "CNY", isAvailable: true, updatedAt: now, errorMessage: nil
        )
        vm.usage = UsageStats(
            todayUsed: 12.30, yesterdayUsed: 9.80, weekUsed: 55.10, monthUsed: 108.50,
            totalUsed: 188.90, dailyAverage: 3.62, daysRemaining: 35,
            balance: 128.42, snapshots: [130, 129.5, 129.1, 128.8, 128.6, 128.42]
        )
        vm.accountBalances = [
            vm.accounts[0].id: vm.balance,
            vm.accounts[1].id: BalanceState(
                totalBalance: 9.50, grantedBalance: 0, toppedUpBalance: 9.50,
                currency: "USD", isAvailable: false, updatedAt: now, errorMessage: nil
            ),
        ]
    }

    @MainActor
    func testRenderOnboardingAndFullStates() async {
        // 1. Onboarding: no accounts, no key source.
        let onboarding = AppViewModel()
        render(PopoverBody(viewModel: onboarding, pendingDeleteAccountID: .constant(nil), showsSettings: .constant(false)), name: "onboarding")

        // 2. Full state: accounts + balances + usage + settings.
        let full = AppViewModel()
        seed(full)
        render(PopoverBody(viewModel: full, pendingDeleteAccountID: .constant(nil), showsSettings: .constant(false)), name: "full")

        // Long labels, large balances, and multiple accounts must still fit.
        let crowded = AppViewModel()
        seed(crowded)
        crowded.accounts[0].name = "Research production account / 研究生产环境"
        crowded.keySource = .account(crowded.accounts[0].name)
        crowded.balance.totalBalance = 1234567.89
        crowded.accountBalances[crowded.accounts[0].id] = crowded.balance
        for index in 3...6 {
            crowded.accounts.append(APIKeyAccount(id: UUID(), name: "Workspace \(index)", key: "sk-demo-\(index)", createdAt: Date()))
        }
        render(PopoverBody(viewModel: crowded, pendingDeleteAccountID: .constant(nil), showsSettings: .constant(false)), name: "crowded")

        let pending = AppViewModel()
        seed(pending)
        pending.balance = BalanceState()
        pending.accountBalances = [:]
        render(PopoverBody(viewModel: pending, pendingDeleteAccountID: .constant(nil), showsSettings: .constant(false)), name: "pending")

        // 3. Orange warning: active account balance insufficient (isAvailable=false).
        let warn = AppViewModel()
        seed(warn)
        warn.balance.isAvailable = false
        print("WARN state: hasBalance=\(warn.balance.hasBalance) isAvailable=\(warn.balance.isAvailable)")
        render(PopoverBody(viewModel: warn, pendingDeleteAccountID: .constant(nil), showsSettings: .constant(false)), name: "warnlow")

        // 4. Update banner.
        let upd = AppViewModel()
        seed(upd)
        upd.updateState = .available(AppUpdateInfo(
            currentVersion: "0.0.5", latestVersion: "0.0.6",
            releaseName: "DeepSeekBar v0.0.6",
            releaseURL: URL(string: "https://github.com/mengxu98/deepseekbar/releases")!
        ))
        print("UPDATE state: \(upd.updateState)")
        render(PopoverBody(viewModel: upd, pendingDeleteAccountID: .constant(nil), showsSettings: .constant(false)), name: "update")

        // 5. Invalid-key banner.
        let invalid = AppViewModel()
        seed(invalid)
        invalid.balance.isKeyInvalid = true
        invalid.balance.errorMessage = "API key is invalid."
        render(PopoverBody(viewModel: invalid, pendingDeleteAccountID: .constant(nil), showsSettings: .constant(false)), name: "keyinvalid")

        // 6. Inline settings page (footer gear swaps the body) and the
        // delete-confirmation row.
        let settings = AppViewModel()
        seed(settings)
        settings.showPricingCountdownInMenuBar = true
        render(SettingsCard(viewModel: settings, onDone: {}), name: "settings")

        let deleting = AppViewModel()
        seed(deleting)
        render(
            PopoverBody(
                viewModel: deleting,
                pendingDeleteAccountID: .constant(deleting.accounts.first?.id),
                showsSettings: .constant(false)
            ),
            name: "delete_inline"
        )

        // 7. Inline editors: rename replaces the account row, add-key opens
        // inside the account card (no floating panel any more).
        render(
            InlineRenameField(
                initialName: "he",
                maskedKey: "sk-30a…7258",
                onSave: { _ in nil },
                onCancel: {}
            )
            .padding(8)
            .background(RoundedRectangle(cornerRadius: DSRadius.row).fill(Color.dsRowFill))
            .padding(8),
            name: "rename_inline"
        )

        render(
            InlineKeyEditor(onSave: { _ in nil }, onCancel: {})
                .padding(8)
                .background(RoundedRectangle(cornerRadius: DSRadius.row).fill(Color.dsRowFill))
                .padding(8),
            name: "addkey_inline"
        )
    }
}
