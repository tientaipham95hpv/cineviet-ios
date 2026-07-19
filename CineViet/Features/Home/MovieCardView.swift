import SwiftUI

struct MovieCardView: View {
    let movie: Movie

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                poster
                LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .center, endPoint: .bottom)
                if let episode = movie.episodeCurrent.nonEmpty {
                    Text(episode).font(.caption2.bold()).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.72), in: Capsule()).padding(8)
                }
            }
            .frame(width: 148, height: 216)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1) }
            .overlay(alignment: .topTrailing) { qualityBadge }
            .shadow(color: .black.opacity(0.42), radius: 14, y: 8)

            Text(movie.title).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(2).frame(width: 148, alignment: .leading)
            HStack(spacing: 6) {
                if let year = movie.releaseYear { Text(String(year)) }
                if let rating = movie.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill").foregroundStyle(CineVietTheme.accent) }
            }.font(.caption2.weight(.semibold)).foregroundStyle(CineVietTheme.textMuted)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine).accessibilityLabel(movie.title)
    }

    @ViewBuilder private var poster: some View {
        AsyncImage(url: movie.posterURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: placeholder
            case .empty: ZStack { placeholder; ProgressView().tint(CineVietTheme.accent) }
            @unknown default: placeholder
            }
        }
    }

    @ViewBuilder private var qualityBadge: some View {
        if !movie.quality.isEmpty {
            Text(movie.quality.uppercased()).font(.caption2.bold()).foregroundStyle(.black)
                .padding(.horizontal, 7).padding(.vertical, 5).background(CineVietTheme.accent, in: RoundedRectangle(cornerRadius: 7)).padding(8)
        }
    }

    private var placeholder: some View { ZStack { CineVietTheme.panel; Image(systemName: "film").font(.title).foregroundStyle(CineVietTheme.textMuted) } }
}
