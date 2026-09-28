import SwiftUI

/// Stanford's palette, pushed a little louder and set on a near-black canvas.
enum Palette {
    static let cardinal = Color(hex: "8C1515")
    static let digitalRed = Color(hex: "B1040E")
    static let hotRed = Color(hex: "E4002B")
    static let poppy = Color(hex: "E98300")
    static let illuminating = Color(hex: "FEDD5C")
    static let lagunita = Color(hex: "00A0D2")
    static let palo = Color(hex: "00B398")
    static let plum = Color(hex: "B4218E")

    static let ink = Color(hex: "0C0809")
    static let surface = Color(hex: "171012")
    static let surfaceHigh = Color(hex: "221719")
    static let hairline = Color.white.opacity(0.10)
    static let text = Color(hex: "FBF6F5")
    static let subtext = Color(hex: "B8A7AA")

    static let heat = LinearGradient(
        colors: [hotRed, cardinal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let sunrise = LinearGradient(
        colors: [illuminating, poppy],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let glow = RadialGradient(
        colors: [cardinal.opacity(0.55), .clear],
        center: .top,
        startRadius: 0,
        endRadius: 420
    )
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let displayXL = rounded(34, .black)
    static let display = rounded(26, .black)
    static let title = rounded(20, .heavy)
    static let body = rounded(15, .semibold)
    static let caption = rounded(12, .bold)
    static let micro = rounded(10, .heavy)
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Keeps the agency's line colours readable on the dark canvas.
    var punchy: Color {
        let ui = UIColor(self)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard ui.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return Color(hue: hue, saturation: min(1, saturation * 1.15), brightness: max(brightness, 0.72))
    }
}

extension View {
    /// The soft, rounded, slightly glassy card used everywhere in the app.
    func cardSurface(_ radius: CGFloat = 26, highlighted: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(highlighted ? Palette.surfaceHigh : Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(highlighted ? Palette.hotRed.opacity(0.45) : Palette.hairline, lineWidth: 1)
                )
        )
    }

    func bounce(_ trigger: some Equatable) -> some View {
        modifier(BounceOnChange(trigger: trigger))
    }
}

private struct BounceOnChange<T: Equatable>: ViewModifier {
    let trigger: T
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: trigger) { _, _ in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { scale = 1.12 }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.6).delay(0.12)) { scale = 1 }
            }
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func pop() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
