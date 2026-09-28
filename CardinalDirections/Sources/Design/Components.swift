import SwiftUI

/// Chunky coloured line badge, e.g. `X`, `SE`, `OCA`.
struct LineBadge: View {
    let line: Line
    var size: CGFloat = 34

    var body: some View {
        Text(line.badge)
            .font(.rounded(size * 0.42, .black))
            .foregroundStyle(.black.opacity(0.85))
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, size * 0.18)
            .background(
                Capsule().fill(Color(hex: line.color).punchy)
            )
            .shadow(color: Color(hex: line.color).punchy.opacity(0.5), radius: 8, y: 2)
    }
}

/// "3 min" arrival pill. Turns hot when the bus is basically here.
struct ETAChip: View {
    let minutes: Int
    var isLive: Bool = true
    var compact: Bool = false

    private var urgent: Bool { minutes <= 3 }

    var body: some View {
        HStack(spacing: 4) {
            if isLive {
                Circle()
                    .fill(urgent ? Palette.illuminating : Palette.palo)
                    .frame(width: 6, height: 6)
                    .pulse()
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .heavy))
            }
            Text(minutes <= 0 ? "now" : "\(minutes) min")
                .font(.rounded(compact ? 12 : 14, .heavy))
                .monospacedDigit()
        }
        .foregroundStyle(urgent ? .black : Palette.text)
        .padding(.horizontal, compact ? 8 : 11)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            Capsule().fill(urgent ? AnyShapeStyle(Palette.sunrise) : AnyShapeStyle(Color.white.opacity(0.10)))
        )
        .bounce(minutes)
    }
}

struct Pill: View {
    let text: String
    var icon: String?
    var tint: Color = Palette.subtext

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .heavy)) }
            Text(text).font(.caption)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

struct BigButton: View {
    let title: String
    var icon: String?
    var style: AnyShapeStyle = AnyShapeStyle(Palette.heat)
    var foreground: Color = .white
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .black)) }
                Text(title).font(.rounded(16, .black))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(style))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.micro)
                .tracking(1.4)
                .foregroundStyle(Palette.subtext)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.micro)
                    .foregroundStyle(Palette.subtext.opacity(0.75))
            }
        }
    }
}

/// Slow breathing animation for the live dots.
struct Pulse: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    func pulse() -> some View { modifier(Pulse()) }
}

/// Microcopy with a pulse. Keeps the app sounding like a person.
enum Copy {
    static func etaVibe(minutes: Int) -> String {
        switch minutes {
        case ..<1: "it's literally here 🏃"
        case 1...2: "run. now. 🏃‍♀️"
        case 3...6: "you've got a sec ☕️"
        case 7...14: "chill, it's coming 😌"
        default: "long wait, sorry bestie 💀"
        }
    }

    static func planVibe(minutes: Int, transfers: Int) -> String {
        if transfers == 0 && minutes <= 12 { return "easiest win 🏆" }
        if transfers == 0 { return "one bus, zero stress" }
        if transfers == 1 { return "one switch, still cute" }
        return "scenic route ✨"
    }

    static let emptyNearby = "no buses near you rn — Marguerite might be napping 😴"
    static let greetingMorning = "gm, where we going?"
    static let greetingAfternoon = "where to, Card?"
    static let greetingEvening = "late night move?"

    static var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 4..<12: greetingMorning
        case 12..<18: greetingAfternoon
        default: greetingEvening
        }
    }
}
