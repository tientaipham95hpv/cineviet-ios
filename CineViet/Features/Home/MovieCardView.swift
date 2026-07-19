import SwiftUI

struct MovieCardView: View {
    let movie: Movie

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    ZStack { placeholder; ProgressView().tint(.orange) }
                @unknown default:
                    placeholder
                }
            }
            .frame(width: 138, height: 202)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if !movie.quality.isEmpty {
                    Text(movie.quality).font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 4)
                        .cineGlass(cornerRadius: 10, tint: .orange).padding(7)
                }
            }

            Text(movie.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 138, alignment: .leading)

            if !movie.metadataLine.isEmpty {
                Text(movie.metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 138, alignment: .leading)
            }
        }
        .padding(8)
        .cineGlass(cornerRadius: 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(movie.title)
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.08)
            Image(systemName: "film")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}
