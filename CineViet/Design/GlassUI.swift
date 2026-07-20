import SwiftUI
import UIKit

enum CineVietTheme {
    // Canonical CineViet palette shared with Flutter CvColors and the website.
    static let accent = Color(red: 45 / 255, green: 224 / 255, blue: 160 / 255)
    static let accentDeep = Color(red: 7 / 255, green: 143 / 255, blue: 102 / 255)
    static let background = adaptive(light: UIColor(red: 0.95, green: 0.97, blue: 0.97, alpha: 1), dark: UIColor(red: 7 / 255, green: 9 / 255, blue: 13 / 255, alpha: 1))
    static let secondaryBackground = adaptive(light: UIColor(red: 0.91, green: 0.94, blue: 0.94, alpha: 1), dark: UIColor(red: 16 / 255, green: 18 / 255, blue: 23 / 255, alpha: 1))
    static let panel = adaptive(light: .white, dark: UIColor(red: 23 / 255, green: 26 / 255, blue: 32 / 255, alpha: 1))
    static let border = adaptive(light: UIColor(red: 0.76, green: 0.80, blue: 0.81, alpha: 1), dark: UIColor(red: 43 / 255, green: 48 / 255, blue: 56 / 255, alpha: 1))
    static let brandRed = Color(red: 229 / 255, green: 9 / 255, blue: 47 / 255)
    static let textMuted = adaptive(light: UIColor(red: 0.29, green: 0.34, blue: 0.37, alpha: 1), dark: UIColor(red: 184 / 255, green: 196 / 255, blue: 212 / 255, alpha: 1))

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

struct GlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 18
    var tint: Color = .white

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(CineVietTheme.panel.opacity(colorScheme == .dark ? 0.44 : 0.72), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(colorScheme == .dark ? tint.opacity(0.16) : CineVietTheme.border.opacity(0.65), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 14, y: 7)
    }
}

extension View {
    func cineGlass(cornerRadius: CGFloat = 18, tint: Color = .white) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint))
    }
}

struct GlassSectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(CineVietTheme.accent).frame(width: 4, height: 22)
            Text(title).font(.title3.bold())
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}
