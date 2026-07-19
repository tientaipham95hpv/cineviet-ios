import SwiftUI

struct MovieCardView: View {
    let movie: Movie

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                poster
                LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)
                if let episode = movie.episodeCurrent.nonEmpty {
                    Text(episode)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(8)
                }
            }
            .frame(width: 142, height: 205)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.8) }
            .overlay(alignment: .topTrailing) { qualityBadge }
            .shadow(color: .black.opacity(0.34), radius: 12, y: 7)

            Text(movie.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 142, alignment: .leading)
                .frame(minHeight: 34, alignment: .topLeading)
            HStack(spacing: 7) {
                if let year = movie.releaseYear, year > 1800 { Text(String(year)) }
                if let rating = movie.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .foregroundStyle(CineVietTheme.accent)
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(CineVietTheme.textMuted)
        }
        .frame(width: 142, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(movie.title)
        .accessibilityAddTraits(.isButton)
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
        if let quality = movie.quality.nonEmpty {
            Text(quality.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(CineVietTheme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(7)
        }
    }

    private var placeholder: some View {
        ZStack {
            CineVietTheme.panel
            Image(systemName: "film.fill").font(.title2).foregroundStyle(CineVietTheme.textMuted.opacity(0.6))
        }
    }
}
