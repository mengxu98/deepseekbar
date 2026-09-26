import SwiftUI

/// DeepSeek peak / off-peak card.
///
/// Pricing needs no API key, so this card is shown even before an account
/// is configured. It is also the app's one colour-coded surface: cool blue
/// while tokens are half price, warm amber during peak hours.
struct PricingCard: View {
    var schedule: HolidaySchedule
    /// Screenshot support (`--demo`): render this instant instead of the
    /// live clock so README figures are reproducible.
    var frozenAt: Date?

    var body: some View {
        if let frozenAt {
            card(for: DeepSeekPricing.snapshot(at: frozenAt, schedule: schedule))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                card(for: DeepSeekPricing.snapshot(at: context.date, schedule: schedule))
            }
        }
    }

    private func card(for snapshot: PricingSnapshot) -> some View {
        let accent = Self.accent(for: snapshot.period)

        return VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: snapshot.period.isOffPeak ? "moon.zzz.fill" : "sun.max.fill")
                    .font(DSFont.bodySemibold)
                    .foregroundColor(accent)
                Text(snapshot.period.isOffPeak
                     ? L10n.tr("Off-peak · half price")
                     : L10n.tr("Peak · full price"))
                    .font(DSFont.bodySemibold)
                Spacer()
                Text(snapshot.period.isOffPeak ? "×0.5" : "×1")
                    .font(DSFont.bodySemibold)
                    .monospacedDigit()
                    .foregroundColor(accent)
            }

            Text(countdownText(snapshot))
                .font(DSFont.bodyMedium)
                .monospacedDigit()

            PricingProgressBar(progress: snapshot.progress, tint: accent)

            Text(detailText(snapshot))
                .font(DSFont.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let coverageNote {
                Text(coverageNote)
                    .font(DSFont.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardBackground(fill: Self.fill(for: snapshot.period))
    }

    /// Off-peak (the cheaper, actionable state) is brand blue; peak hours
    /// are warm amber so the two states are distinguishable at a glance and
    /// in greyscale (the label and badge carry the meaning too).
    static func accent(for period: PricePeriod) -> Color {
        period.isOffPeak ? .dsBlue : .dsAmber
    }

    static func fill(for period: PricePeriod) -> Color {
        period.isOffPeak ? .dsBlueTint : .dsAmberTint
    }

    private func countdownText(_ snapshot: PricingSnapshot) -> String {
        let countdown = PricingFormatter.countdown(snapshot.remaining)
        return snapshot.period.isOffPeak
            ? L10n.trf("Full price resumes in %@", countdown)
            : L10n.trf("Off-peak starts in %@", countdown)
    }

    private func detailText(_ snapshot: PricingSnapshot) -> String {
        let switchLabel = PricingFormatter.switchLabel(snapshot.nextSwitch, relativeTo: snapshot.date)
        var text = "\(dayKindText(snapshot.dayKind)) · \(L10n.trf("Next switch %@ Beijing time", switchLabel))"
        if !Self.isBeijingLocalTime(at: snapshot.nextSwitch) {
            text += " · \(L10n.trf("%@ your time", PricingFormatter.localClock(snapshot.nextSwitch)))"
        }
        return text
    }

    private func dayKindText(_ kind: PricingDayKind) -> String {
        switch kind {
        case .publicHoliday(let name):
            return L10n.trf("%@ holiday · off-peak all day", name.localizedName)
        case .alternateWorkday(let name):
            return L10n.trf("%@ make-up workday (weekend) · off-peak all day", name.localizedName)
        case .weekend:
            return L10n.tr("Weekend · off-peak all day")
        case .regularWeekday:
            return L10n.tr("Weekday · peak 09:00–12:00, 14:00–18:00")
        }
    }

    /// Shown only when the bundled statutory-holiday table does not cover
    /// the current Beijing year (e.g. 2027 until the State Council
    /// publishes it), so the card never overstates its accuracy.
    private var coverageNote: String? {
        let year = DeepSeekPricing.calendar.component(.year, from: Date())
        guard !schedule.covers(year: year), let covered = schedule.coveredYears.max() else {
            return nil
        }
        return L10n.trf("Holiday dates bundled for %d; later years use weekday/weekend rules only.", covered)
    }

    private static func isBeijingLocalTime(at date: Date) -> Bool {
        TimeZone.current.secondsFromGMT(for: date) == DeepSeekPricing.timeZone.secondsFromGMT(for: date)
    }
}

/// Thin block-progress bar. Drawn from plain shapes instead of
/// `ProgressView`: offscreen `ImageRenderer` snapshots (README figures,
/// UI tests) cannot rasterise the AppKit-backed control.
struct PricingProgressBar: View {
    var progress: Double
    var tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 5)
        .accessibilityLabel(L10n.tr("Progress through the current pricing block"))
    }
}

