import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }

    static let arbiterBg      = Color(hex: "#050505")
    static let arbiterSurface = Color(hex: "#0A0A0B").opacity(0.9)
    static let arbiterCyan    = Color(hex: "#00F2FF")
    static let arbiterCyanLow = Color(hex: "#004A4D")
    static let arbiterBorder  = Color.white.opacity(0.15)
    static let arbiterText    = Color(hex: "#EBEBEB")
}

struct ArbiterPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.arbiterSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.clear],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
    }
}

struct ArbiterGlowPanel: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.28), radius: 22, x: 0, y: 0)
            .shadow(color: color.opacity(0.12), radius: 8, x: 0, y: 0)
    }
}

extension View {
    func glowEffect(color: Color) -> some View {
        modifier(ArbiterGlowPanel(color: color))
    }
}

struct ArbiterFont {
    /// Base bump applied to all mono text for legibility at typical window sizes.
    private static let sizeOffset: CGFloat = 2

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size + sizeOffset, weight: .regular, design: .monospaced)
    }
}
