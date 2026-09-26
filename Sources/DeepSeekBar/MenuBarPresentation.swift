import Foundation

/// The menu-bar item's text content, derived purely from balance and
/// pricing state so it can be unit-tested without an `NSStatusItem`.
struct MenuBarPresentation: Equatable {
    enum Emphasis: Equatable {
        case primary
        case secondary
        /// Off-peak badge: the actionable, cheaper state.
        case pricing
        case caution
        case warning
    }

    struct Segment: Equatable {
        var text: String
        var emphasis: Emphasis
    }

    let segments: [Segment]
    let tooltip: String

    init(balance: BalanceState, pricing: PricingSnapshot?, showsPricingCountdown: Bool) {
        var segments: [Segment] = []
        var tooltipParts: [String] = []

        if let error = balance.errorMessage {
            segments.append(Segment(text: "DS!", emphasis: .warning))
            tooltipParts.append(error)
        } else if let total = balance.totalBalance {
            let amount = "\(String.currencySymbol(for: balance.currency))\(total.compactMoneyText)"
            if balance.isAvailable {
                segments.append(Segment(text: amount, emphasis: .primary))
                tooltipParts.append(total.moneyText(currency: balance.currency))
            } else {
                // Balance exists but is insufficient for API calls.
                segments.append(Segment(text: "\(amount)!", emphasis: .caution))
                tooltipParts.append(
                    L10n.tr("Balance insufficient for API calls. Top up at platform.deepseek.com.")
                )
            }
        } else {
            segments.append(Segment(text: "DS", emphasis: .primary))
        }

        if let pricing {
            // The menu bar draws over wallpaper, translucency and the
            // highlighted state of an open popover, so everything stays at
            // label contrast (`secondary` was unreadable there). Off-peak
            // keeps the brand tint; peak uses plain label colour.
            segments.append(Segment(
                text: " \(pricing.period.menuBarBadge)",
                emphasis: pricing.period.isOffPeak ? .pricing : .primary
            ))
            if showsPricingCountdown {
                segments.append(Segment(
                    text: " \(PricingFormatter.menuBarCountdown(pricing.remaining))",
                    emphasis: .primary
                ))
            }
            tooltipParts.append(Self.pricingTooltip(pricing))
        }

        self.segments = segments
        self.tooltip = (["DeepSeekBar"] + tooltipParts).joined(separator: " · ")
    }

    private static func pricingTooltip(_ pricing: PricingSnapshot) -> String {
        let countdown = PricingFormatter.countdown(pricing.remaining)
        let state = pricing.period.isOffPeak
            ? L10n.tr("Off-peak · half price")
            : L10n.tr("Peak · full price")
        let switching = pricing.period.isOffPeak
            ? L10n.trf("Full price resumes in %@", countdown)
            : L10n.trf("Off-peak starts in %@", countdown)
        return "\(state) · \(switching)"
    }
}
