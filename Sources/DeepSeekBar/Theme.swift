import AppKit
import SwiftUI

enum PopoverSizing {
    static let width: CGFloat = 300
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

extension Color {
    static let deepSeekBlue = Color(red: 0.10, green: 0.45, blue: 0.88)
}

/// Popover/panel surface: clean white in light mode; the system dark
/// surface in dark mode so sheets don't glare inside a dark UI.
/// A dynamic NSColor resolves against the view's appearance, which follows
/// the system for a menu-bar app. (A computed color keyed off
/// NSApp.effectiveAppearance is unreliable here: a menu-bar app has no
/// regular window, so NSApp.effectiveAppearance can stay light in dark mode.)
let panelBackgroundColor = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor.windowBackgroundColor
        : NSColor.white
})

// MARK: - Shared View Helpers

@MainActor
func modalHeader(_ title: String, subtitle: String) -> some View {
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
func modalFieldLabel(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
}

@MainActor
func modalTextButton(_ title: String, action: @escaping () -> Void) -> some View {
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
func modalPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
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

extension View {
    func modalPanelBackground(width: CGFloat) -> some View {
        frame(width: width)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(panelBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
            )
            .foregroundStyle(.primary)
    }

    func modalTextField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
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
}
