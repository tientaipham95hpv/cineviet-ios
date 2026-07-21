import SwiftUI

struct MembershipTag: View {
    let isAdmin: Bool
    var body: some View {
        Label(isAdmin ? "Administrator" : "VIP", systemImage: "crown.fill")
            .font(.caption2.weight(.black))
            .foregroundStyle(isAdmin ? .black : Color(red: 0.85, green: 0.70, blue: 1))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(isAdmin ? Color.yellow.opacity(0.9) : Color.purple.opacity(0.28), in: Capsule())
            .overlay { Capsule().stroke(isAdmin ? Color.yellow : Color.purple.opacity(0.8), lineWidth: 1) }
            .accessibilityLabel(isAdmin ? "Administrator" : "VIP")
    }
}

struct UserAvatar: View {
    let name: String
    let url: URL?
    let isVIP: Bool
    var size: CGFloat = 48

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle().fill(LinearGradient(colors: [CineVietTheme.accent, CineVietTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { initials }
                }.clipShape(Circle()).padding(3)
            } else { initials }
            if isVIP {
                Circle().fill(.black.opacity(0.9)).frame(width: size * 0.30, height: size * 0.30)
                    .overlay { Image(systemName: "crown.fill").font(.system(size: size * 0.13, weight: .bold)).foregroundStyle(.yellow) }
                    .offset(x: size * 0.08, y: -size * 0.05)
            }
        }
        .frame(width: size, height: size)
        .overlay { Circle().stroke(isVIP ? Color.yellow : CineVietTheme.accent.opacity(0.75), lineWidth: isVIP ? max(2, size * 0.045) : 2) }
        .accessibilityLabel("Ảnh đại diện của \(name)")
    }

    private var initials: some View { Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.black) }
}
