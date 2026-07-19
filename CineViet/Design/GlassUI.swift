import SwiftUI

enum CineVietTheme {
    static let accent = Color.orange
    static let background = Color(red: 0.025, green: 0.03, blue: 0.055)
    static let secondaryBackground = Color(red: 0.07, green: 0.08, blue: 0.12)
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
