import AppKit
import SwiftUI

enum PopoverSizing {
    static let width: CGFloat = 320
    /// Fallback/placeholder height until the hosting view reports its
    /// fitting size on show.
    static let preferredHeight: CGFloat = 560
    static let minimumHeight: CGFloat = 360
    static let verticalMargin: CGFloat = 12

    /// Grows to the content's natural height (no dead space for short
    /// lists) but never exceeds the screen or drops below the minimum.
    static func clampedHeight(fittingHeight: CGFloat, availableHeight: CGFloat?) -> CGFloat {
        let maxHeight = availableHeight ?? max(fittingHeight, minimumHeight)
        return min(maxHeight, max(minimumHeight, fittingHeight))
    }
}

// MARK: - Design tokens

/// Four text sizes — hierarchy comes from weight and colour, not from a
/// long tail of one-off sizes.
enum DSFont {
    /// The one big number (active balance).
    static let hero = Font.system(size: 28, weight: .semibold)
    /// Window/popover titles.
    static let title = Font.system(size: 13, weight: .semibold)
    /// Card headers.
    static let section = Font.system(size: 12, weight: .semibold)

    static let body = Font.system(size: 12)
    static let bodyMedium = Font.system(size: 12, weight: .medium)
    static let bodySemibold = Font.system(size: 12, weight: .semibold)

    static let caption = Font.system(size: 11)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let captionSemibold = Font.system(size: 11, weight: .semibold)
}

/// 4-pt spacing grid.
enum DSSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
}

/// Corner radii: rows, controls, cards, utility panels.
enum DSRadius {
    static let row: CGFloat = 6
    static let control: CGFloat = 8
    static let card: CGFloat = 10
    static let panel: CGFloat = 16
}

private func dsRGB(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

/// A colour that resolves per appearance. A menu-bar app has no regular
/// window, so `NSApp.effectiveAppearance` is unreliable; resolving against
/// the view's own appearance is not.
private func dsDynamic(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

// MARK: - Palette

extension Color {
    /// Solid DeepSeek theme blue for the balance overview in both appearances.
    static let dsHeroBlue = Color(red: 77 / 255, green: 107 / 255, blue: 254 / 255)
    /// Distinct estimate accents, independent of pricing and error states.
    static let dsTeal = dsDynamic(light: dsRGB(0.03, 0.43, 0.45), dark: dsRGB(0.33, 0.82, 0.80))
    static let dsTealTint = dsDynamic(light: dsRGB(0.03, 0.53, 0.55, 0.08), dark: dsRGB(0.33, 0.82, 0.80, 0.10))
    static let dsIndigoTint = dsDynamic(light: dsRGB(0.42, 0.30, 0.78, 0.08), dark: dsRGB(0.60, 0.58, 0.98, 0.12))

    /// Brand: active account, off-peak pricing, today's spend.
    static let dsBlue = dsDynamic(light: dsRGB(0.10, 0.45, 0.88), dark: dsRGB(0.38, 0.66, 1.00))
    /// Cumulative totals — same family as the brand hue, clearly secondary.
    static let dsIndigo = dsDynamic(light: dsRGB(0.35, 0.34, 0.80), dark: dsRGB(0.60, 0.58, 0.98))
    /// Peak pricing and low-balance attention.
    static let dsAmber = dsDynamic(light: dsRGB(0.76, 0.46, 0.00), dark: dsRGB(1.00, 0.72, 0.30))
    /// Granted (free) credit.
    static let dsGreen = dsDynamic(light: dsRGB(0.09, 0.52, 0.34), dark: dsRGB(0.35, 0.82, 0.56))
    /// Errors — invalid key, failed refresh.
    static let dsRed = dsDynamic(light: dsRGB(0.76, 0.20, 0.17), dark: dsRGB(1.00, 0.46, 0.42))

    /// Surfaces. Fixed opacities instead of `secondary`, whose dark-mode
    /// value is too faint to read as a card.
    static let dsCardFill = dsDynamic(light: dsRGB(0, 0, 0, 0.035), dark: dsRGB(1, 1, 1, 0.060))
    static let dsRowFill = dsDynamic(light: dsRGB(0, 0, 0, 0.030), dark: dsRGB(1, 1, 1, 0.050))
    static let dsControlFill = dsDynamic(light: dsRGB(0, 0, 0, 0.060), dark: dsRGB(1, 1, 1, 0.090))
    static let dsBorder = dsDynamic(light: dsRGB(0, 0, 0, 0.080), dark: dsRGB(1, 1, 1, 0.100))

    /// Accent washes for cards and banners.
    static let dsBlueTint = dsDynamic(light: dsRGB(0.10, 0.45, 0.88, 0.10), dark: dsRGB(0.38, 0.66, 1.00, 0.14))
    static let dsAmberTint = dsDynamic(light: dsRGB(0.76, 0.46, 0.00, 0.10), dark: dsRGB(1.00, 0.72, 0.30, 0.14))
    static let dsGreenTint = dsDynamic(light: dsRGB(0.09, 0.52, 0.34, 0.10), dark: dsRGB(0.35, 0.82, 0.56, 0.15))
    static let dsRedTint = dsDynamic(light: dsRGB(0.76, 0.20, 0.17, 0.10), dark: dsRGB(1.00, 0.46, 0.42, 0.16))
}

/// Popover/panel surface: clean white in light mode; the system dark
/// surface in dark mode so sheets don't glare inside a dark UI.
let panelBackgroundColor = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor.windowBackgroundColor
        : NSColor.white
})

// MARK: - Shared View Helpers

@MainActor
func modalHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: DSSpacing.xs) {
        Text(title)
            .font(DSFont.title)
        Text(subtitle)
            .font(DSFont.caption)
            .foregroundColor(.secondary)
            .lineLimit(2)
    }
}

@MainActor
func modalFieldLabel(_ title: String) -> some View {
    Text(title)
        .font(DSFont.captionMedium)
        .foregroundColor(.secondary)
}

@MainActor
func modalTextButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(DSFont.bodySemibold)
            .foregroundColor(.primary)
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.control)
                    .fill(Color.dsControlFill)
            )
    }
    .buttonStyle(.plain)
    .focusable(false)
}

@MainActor
func modalPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(DSFont.bodySemibold)
            .foregroundColor(.white)
            .padding(.horizontal, DSSpacing.l)
            .padding(.vertical, DSSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.control)
                    .fill(Color.dsBlue)
            )
    }
    .buttonStyle(.plain)
    .focusable(false)
}

extension View {
    func modalPanelBackground(width: CGFloat) -> some View {
        frame(width: width)
            .padding(DSSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.panel)
                    .fill(panelBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.panel)
                            .stroke(Color.dsBorder, lineWidth: 1)
                    )
            )
            .foregroundStyle(.primary)
    }

    func modalTextField() -> some View {
        textFieldStyle(.plain)
            .font(DSFont.bodyMedium)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.control)
                    .fill(Color.dsControlFill)
            )
    }

    /// A row nested inside a card (account rows, inline editors).
    func rowBackground() -> some View {
        padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.row)
                    .fill(Color.dsRowFill)
            )
    }

    /// Standard card surface. `fill` lets the pricing card carry its
    /// period colour without duplicating the chrome.
    func cardBackground(fill: Color = .dsCardFill) -> some View {
        padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.card)
                    .fill(fill)
            )
    }
}

/// Compact desktop hit area with a stable hover treatment.
struct DSIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.bodyMedium)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: DSRadius.row)
                .fill(isHovered || configuration.isPressed ? Color.dsControlFill : .clear))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }
}
