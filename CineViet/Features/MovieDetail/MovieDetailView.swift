import SwiftUI

struct MovieDetailView: View {
    @StateObject private var viewModel: MovieDetailViewModel
    let watchHistoryService: WatchHistoryServicing

    init(movie: Movie, movieService: MovieServicing, watchHistoryService: WatchHistoryServicing) {
        _viewModel = StateObject(wrappedValue: MovieDetailViewModel(movie: movie, movieService: movieService))
        self.watchHistoryService = watchHistoryService
    }

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .loading:
                ProgressView("Đang tải thông tin phim…")
                    .tint(.orange)
                    .frame(maxWidth: .infinity, minHeight: 400)
            case .failed(let message):
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Không tải được thông tin phim")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Thử lại") { Task { await viewModel.retry() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
                .padding()
            case .loaded:
                detailContent
            }
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle(viewModel.displayedMovie.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private var detailContent: some View {
        let movie = viewModel.displayedMovie
        return VStack(alignment: .leading, spacing: 20) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: movie.backdropURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else { Color.white.opacity(0.08) }
                }
                .frame(height: 280)
                .clipped()
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                Text(movie.title)
                    .font(.largeTitle.bold())
                    .lineLimit(3)
                    .padding(20)
            }

            VStack(alignment: .leading, spacing: 12) {
                if !movie.titleEn.isEmpty { Text(movie.titleEn).foregroundStyle(.secondary) }
                if !movie.metadataLine.isEmpty { Text(movie.metadataLine).foregroundStyle(.orange) }
                if !movie.genres.isEmpty { Text(movie.genres.joined(separator: " • ")).foregroundStyle(.secondary) }
                if !movie.description.isEmpty { Text(movie.description).lineSpacing(4) }
            }
            .padding(.horizontal, 16)

            if !movie.episodes.isEmpty {
                episodesSection(movie)
            }
            peopleSection(movie)
            if !movie.related.isEmpty { relatedSection(movie.related) }
        }
        .padding(.bottom, 32)
    }

    private func episodesSection(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tập phim").font(.title2.bold()).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(movie.episodes.enumerated()), id: \.offset) { index, server in
                        Button(server.name) { viewModel.selectServer(index) }
                            .buttonStyle(.borderedProminent)
                            .tint(index == viewModel.selectedServerIndex ? .orange : .gray)
                    }
                }
                .padding(.horizontal, 16)
            }
            if let server = viewModel.selectedServer {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(server.items) { episode in
                        NavigationLink {
                            PlayerView(movie: movie, server: server, episode: episode, watchHistoryService: watchHistoryService)
                        } label: {
                            HStack {
                                Text(episode.name)
                                Image(systemName: "play.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func peopleSection(_ movie: Movie) -> some View {
        if !movie.directors.isEmpty || !movie.cast.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Diễn viên & đạo diễn").font(.title2.bold())
                ForEach(movie.directors.prefix(5), id: \.name) { person in
                    Text("Đạo diễn: \(person.name)").foregroundStyle(.secondary)
                }
                Text(movie.cast.prefix(20).map(\.name).joined(separator: " • "))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
        }
    }

    private func relatedSection(_ movies: [Movie]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Có thể bạn thích").font(.title2.bold()).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(movies) { MovieCardView(movie: $0) }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
