import SwiftUI

enum CineVietTheme {
    // Canonical CineViet palette shared with Flutter CvColors and the website.
    static let accent = Color(red: 45 / 255, green: 224 / 255, blue: 160 / 255)
    static let accentDeep = Color(red: 7 / 255, green: 143 / 255, blue: 102 / 255)
    static let background = Color(red: 7 / 255, green: 9 / 255, blue: 13 / 255)
    static let secondaryBackground = Color(red: 16 / 255, green: 18 / 255, blue: 23 / 255)
    static let panel = Color(red: 23 / 255, green: 26 / 255, blue: 32 / 255)
    static let border = Color(red: 43 / 255, green: 48 / 255, blue: 56 / 255)
    static let brandRed = Color(red: 229 / 255, green: 9 / 255, blue: 47 / 255)
    static let textMuted = Color(red: 184 / 255, green: 196 / 255, blue: 212 / 255)
}

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 18
    var tint: Color = .white

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 7)
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
