import SwiftUI

/// Step-by-step card for the plan currently drawn on the map.
struct PlanDetailCard: View {
    let plan: TripPlan
    let onEdit: () -> Void

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Palette.hairline)
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(plan.totalMinutes)")
                    .font(.displayXL)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                Text("min")
                    .font(.title)
                    .foregroundStyle(Palette.subtext)
                Spacer()
                Text("arrive \(plan.arrival.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Palette.subtext)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Palette.text)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Palette.surface))
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(plan.legs) { leg in
                        LegRow(leg: leg)
                    }
                }
                .frame(maxHeight: 250)
            }

            HStack(spacing: 10) {
                BigButton(title: "edit trip", icon: "slider.horizontal.3", style: AnyShapeStyle(Palette.surfaceHigh), foreground: Palette.text) {
                    onEdit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(Palette.ink.opacity(0.97))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct LegRow: View {
    let leg: Leg

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let line = leg.line {
                LineBadge(line: line, size: 30)
            } else {
                Image(systemName: "figure.walk")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Palette.subtext)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.surfaceHigh))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.rounded(14, .heavy))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.subtext)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if leg.kind == .ride {
                ETAChip(minutes: leg.waitMinutes, isLive: leg.waitIsLive, compact: true)
            } else {
                Pill(text: "\(leg.minutes) min")
            }
        }
        .padding(10)
        .cardSurface(18)
    }

    private var headline: String {
        switch leg.kind {
        case .walk: "walk to \(leg.toName)"
        case .ride: "ride \(leg.line?.shortName ?? "the bus") to \(leg.toName)"
        }
    }

    private var detail: String {
        switch leg.kind {
        case .walk: "\(leg.minutes) min on foot"
        case .ride: "board at \(leg.fromName) · \(leg.stops.count - 1) stops · \(leg.minutes) min ride"
        }
    }
}
