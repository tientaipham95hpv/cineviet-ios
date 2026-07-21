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
    @State private var spin = false

    var body: some View {
        ZStack {
            // Keep the image completely inside the frame; the royal ring is drawn above it.
            Circle().fill(LinearGradient(colors: [CineVietTheme.accent, CineVietTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: initials
                    }
                }
                .clipShape(Circle())
                .padding(isVIP ? size * 0.105 : 3)
            } else { initials.padding(isVIP ? size * 0.105 : 3) }

            if isVIP {
                Circle()
                    .strokeBorder(
                        AngularGradient(gradient: Gradient(colors: [.brown, .yellow, .white, .yellow, .brown]), center: .center),
                        lineWidth: max(2.5, size * 0.065)
                    )
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .shadow(color: .yellow.opacity(0.95), radius: size * 0.12)
                    .overlay {
                        // Symmetric crown badge, centered at twelve o'clock.
                        Image(systemName: "crown.fill")
                            .font(.system(size: max(9, size * 0.18), weight: .black))
                            .foregroundStyle(.yellow)
                            .padding(size * 0.055)
                            .background(.black.opacity(0.92), in: Circle())
                            .overlay { Circle().stroke(.yellow, lineWidth: 1) }
                        .offset(y: -size * 0.47)
                    }
                ForEach(0..<4, id: \.self) { index in
                    Circle().fill(.white).frame(width: max(2, size * 0.045), height: max(2, size * 0.045))
                        .shadow(color: .white, radius: size * 0.08)
                        .offset(y: -size * 0.48)
                        .rotationEffect(.degrees(Double(index) * 90 + (spin ? 360 : 0)))
                }
            }
        }
        // Reserve one stable slot for both normal and VIP avatars. The crown
        // and sparkle ring are overlays and must never change ScrollView height.
        .frame(width: size + size * 0.22, height: size + size * 0.22)
        .onAppear { if isVIP { withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) { spin = true } } }
        .accessibilityLabel("Ảnh đại diện của \(name)")
    }

    private var initials: some View { Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.black) }
}
