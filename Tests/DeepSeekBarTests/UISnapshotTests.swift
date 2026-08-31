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
        let renderer = ImageRenderer(content: view
            .frame(width: 300)
            .background(panelBackgroundColor))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            XCTFail("failed to render \(name)")
            return
        }
        let path = "/tmp/dsb_ui_\(name).png"
        try? data.write(to: URL(fileURLWithPath: path))
        print("WROTE \(path)")
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
        render(PopoverBody(viewModel: onboarding, pendingDeleteAccountID: .constant(nil)), name: "onboarding")

        // 2. Full state: accounts + balances + usage + settings.
        let full = AppViewModel()
        seed(full)
        render(PopoverBody(viewModel: full, pendingDeleteAccountID: .constant(nil)), name: "full")

        // 3. Orange warning: active account balance insufficient (isAvailable=false).
        let warn = AppViewModel()
        seed(warn)
        warn.balance.isAvailable = false
        print("WARN state: hasBalance=\(warn.balance.hasBalance) isAvailable=\(warn.balance.isAvailable)")
        render(PopoverBody(viewModel: warn, pendingDeleteAccountID: .constant(nil)), name: "warnlow")

        // 4. Update banner.
        let upd = AppViewModel()
        seed(upd)
        upd.updateState = .available(AppUpdateInfo(
            currentVersion: "0.0.5", latestVersion: "0.0.6",
            releaseName: "DeepSeekBar v0.0.6",
            releaseURL: URL(string: "https://github.com/mengxu98/deepseekbar/releases")!
        ))
        print("UPDATE state: \(upd.updateState)")
        render(PopoverBody(viewModel: upd, pendingDeleteAccountID: .constant(nil)), name: "update")

        // 5. Invalid-key banner.
        let invalid = AppViewModel()
        seed(invalid)
        invalid.balance.isKeyInvalid = true
        invalid.balance.errorMessage = "API key is invalid."
        render(PopoverBody(viewModel: invalid, pendingDeleteAccountID: .constant(nil)), name: "keyinvalid")
    }
}
