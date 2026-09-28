import AppKit
import SwiftUI

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
        viewModel.onStatusItemChange = { [weak self] in
            self?.renderStatusItem()
        }
        if CommandLine.arguments.contains("--demo") {
            // README figure mode: synthetic healthy state, no Keychain/network.
            viewModel.seedDemo()
        } else {
            viewModel.start()
        }

        // Screenshot helpers (README figures): --show-popover opens the
        // popover after launch; --dark forces dark appearance;
        // --screenshot renders the popover view directly to a PNG
        // (screen capture cannot grab the menu-bar-layer panel).
        if CommandLine.arguments.contains("--dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            // NSPopover windows don't inherit NSApp.appearance on newer
            // macOS, so the panel's dynamic background resolves light.
            // Pin the content view's appearance directly as well.
            popover.contentViewController?.view.appearance = NSAppearance(named: .darkAqua)
        } else if CommandLine.arguments.contains("--screenshot") {
            // Force light appearance so the light screenshot is actually light.
            NSApp.appearance = NSAppearance(named: .aqua)
            popover.contentViewController?.view.appearance = NSAppearance(named: .aqua)
        }
        if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.togglePopover()
            }
        }
        if let screenshotPath = Self.screenshotPathArgument() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showPopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.capturePopover(to: screenshotPath)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func screenshotPathArgument() -> String? {
        guard let idx = CommandLine.arguments.firstIndex(of: "--screenshot") else {
            return nil
        }
        let next = CommandLine.arguments.index(after: idx)
        guard next < CommandLine.arguments.endIndex else { return nil }
        return CommandLine.arguments[next]
    }

    private func capturePopover(to path: String) {
        guard let window = popover.contentViewController?.view.window,
              let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                .bestResolution
              ),
              let data = NSBitmapImageRep(cgImage: image)
                .representation(using: .png, properties: [:]) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(editMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.tr("Quit DeepSeekBar"), action: #selector(quit), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: L10n.tr("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.tr("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.tr("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.tr("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.tr("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.tr("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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
        button.attributedTitle = Self.makeStatusTitle([])
        button.toolTip = "DeepSeekBar"
        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.focusRingType = .none
        button.setAccessibilityLabel("DeepSeekBar")
    }

    private func configurePopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: PopoverSizing.width, height: PopoverSizing.preferredHeight)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(
                viewModel: viewModel,
                onContentSizeChange: { [weak self] in
                    self?.resizePopoverToFitContent()
                }
            )
        )
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }
        // Size the popover to the content's natural height (a short list
        // leaves no dead space); the body ScrollView takes over scrolling
        // when content exceeds the screen.
        applyFittingPopoverSize()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Opening by mouse should not preselect the console button. Tab
        // still enters the normal keyboard focus order.
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    /// Re-sizes the open popover after the body's natural height changed
    /// (inline rename / add-key forms). Deferred by one runloop turn so the
    /// SwiftUI layout pass has already produced the new fitting size.
    private func resizePopoverToFitContent() {
        guard popover.isShown else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else {
                return
            }
            self.applyFittingPopoverSize()
        }
    }

    private func applyFittingPopoverSize() {
        // Plain `fittingSize` of the hosting view: forcing a layout pass
        // first makes it under-report (the ScrollView has not been given
        // its width yet), which clipped the bottom of the body.
        let fittingHeight = popover.contentViewController?.view.fittingSize.height
            ?? PopoverSizing.preferredHeight
        let target = NSSize(
            width: PopoverSizing.width,
            height: PopoverSizing.clampedHeight(
                fittingHeight: fittingHeight,
                availableHeight: availablePopoverHeightBelowStatusItem()
            )
        )
        // Sub-point changes would just thrash the layout.
        guard abs(popover.contentSize.height - target.height) > 0.5 else {
            return
        }
        popover.contentSize = target
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

    /// Renders the menu-bar item from view-model state so the balance and
    /// pricing callbacks cannot drift apart.
    private func renderStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        let presentation = MenuBarPresentation(
            balance: viewModel.balance,
            pricing: viewModel.showPricingInMenuBar ? viewModel.pricing : nil,
            showsPricingCountdown: viewModel.showPricingCountdownInMenuBar
        )
        button.attributedTitle = Self.makeStatusTitle(presentation.segments)
        button.toolTip = presentation.tooltip
    }

    /// Menu-bar icon from the official deepseek-harness-desktop app
    /// (apps/desktop/resources/trayTemplate@2x.png): designed as a template
    /// image so the system tints it for the current menu-bar appearance.
    /// Copied into Contents/Resources by build.sh; loaded via Bundle.main
    /// (no SwiftPM resource bundle, which is fragile in release builds).
    private static let statusLogo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "tray-icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }()

    private static func makeStatusTitle(_ segments: [MenuBarPresentation.Segment]) -> NSAttributedString {
        let title = NSMutableAttributedString()
        for segment in segments {
            title.append(NSAttributedString(
                string: segment.text,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: color(for: segment.emphasis)
                ]
            ))
        }
        return title
    }

    private static func color(for emphasis: MenuBarPresentation.Emphasis) -> NSColor {
        switch emphasis {
        case .primary: return .labelColor
        case .secondary: return .secondaryLabelColor
        case .pricing: return .systemBlue
        case .caution: return .systemOrange
        case .warning: return .systemYellow
        }
    }
}
