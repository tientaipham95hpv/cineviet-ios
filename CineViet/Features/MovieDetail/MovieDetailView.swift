import SwiftUI

struct MovieDetailView: View {
    @StateObject private var viewModel: MovieDetailViewModel
    let watchHistoryService: WatchHistoryServicing
    @State private var newPlaylistName = ""
    @State private var showingNewPlaylist = false

    init(movie: Movie, movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing) {
        _viewModel = StateObject(wrappedValue: MovieDetailViewModel(movie: movie, movieService: movieService, libraryService: libraryService))
        self.watchHistoryService = watchHistoryService
    }

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .loading: ProgressView("Đang tải thông tin phim…").tint(CineVietTheme.accent).frame(maxWidth: .infinity, minHeight: 500)
            case .failed(let message): ContentMessage(icon: "exclamationmark.triangle", title: "Không tải được thông tin phim", message: message).frame(minHeight: 450).onTapGesture { Task { await viewModel.retry() } }
            case .loaded: detailContent
            }
        }
        .background(detailBackground)
        .foregroundStyle(.white)
        .navigationTitle(viewModel.displayedMovie.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("Tạo playlist", isPresented: $showingNewPlaylist) {
            TextField("Tên playlist", text: $newPlaylistName)
            Button("Tạo và thêm phim") { let name = newPlaylistName; newPlaylistName = ""; Task { await viewModel.createPlaylist(name: name) } }
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Huỷ", role: .cancel) { }
        }
    }

    private var detailContent: some View {
        let movie = viewModel.displayedMovie
        return VStack(alignment: .leading, spacing: 26) {
            cinematicHeader(movie)
            actionPanel(movie)
            if !movie.description.isEmpty { glassPanel(title: "Nội dung") { Text(movie.description).lineSpacing(5).foregroundStyle(.white.opacity(0.88)) } }
            if !movie.episodes.isEmpty { episodesSection(movie) }
            peopleSection(movie)
            if !movie.related.isEmpty { relatedSection(movie.related) }
        }.padding(.bottom, 38)
    }

    private func cinematicHeader(_ movie: Movie) -> some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: movie.backdropURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() } else { CineVietTheme.secondaryBackground }
            }.frame(height: 390).clipped()
            LinearGradient(colors: [.clear, CineVietTheme.background.opacity(0.45), CineVietTheme.background], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 16) {
                AsyncImage(url: movie.posterURL) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { Color.white.opacity(0.08) }
                }.frame(width: 112, height: 164).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.2)) }.shadow(radius: 18)
                VStack(alignment: .leading, spacing: 8) {
                    Text(movie.title).font(.title.bold()).lineLimit(3)
                    if !movie.titleEn.isEmpty { Text(movie.titleEn).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    FlowChips(values: metadata(movie), accentFirst: true)
                }
                Spacer(minLength: 0)
            }.padding(16).cineGlass(cornerRadius: 24, tint: CineVietTheme.accent).padding(.horizontal, 14)
        }.frame(height: 390)
    }

    private func actionPanel(_ movie: Movie) -> some View {
        VStack(spacing: 12) {
            if let source = viewModel.firstPlayableSource {
                NavigationLink { PlayerView(movie: movie, server: source.server, episode: source.episode, watchHistoryService: watchHistoryService) } label: {
                    Label("XEM PHIM", systemImage: "play.fill").font(.headline.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black)
            } else {
                Label(viewModel.hasEmbedOnlySource ? "Nguồn phim hiện chỉ hỗ trợ trình phát nhúng" : "Phim chưa có nguồn phát", systemImage: "play.slash.fill")
                    .font(.subheadline.bold()).foregroundStyle(CineVietTheme.textMuted).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .cineGlass(cornerRadius: 14, tint: CineVietTheme.brandRed)
            }
            HStack {
                Button { Task { await viewModel.toggleFavorite() } } label: { Label(viewModel.isFavorite ? "Đã yêu thích" : "Yêu thích", systemImage: viewModel.isFavorite ? "heart.fill" : "heart") }.buttonStyle(.bordered)
                Menu { ForEach(viewModel.playlists) { playlist in Button(playlist.name) { Task { await viewModel.addToPlaylist(playlist) } } }; Divider(); Button("Tạo playlist mới…") { showingNewPlaylist = true } } label: { Label("Playlist", systemImage: "text.badge.plus") }.buttonStyle(.bordered)
            }
            if let error = viewModel.libraryError { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(16).cineGlass(cornerRadius: 22, tint: CineVietTheme.accent).padding(.horizontal, 16)
    }

    private func episodesSection(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionHeader(title: "Tập phim")
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 9) { ForEach(Array(movie.episodes.enumerated()), id: \.offset) { index, server in Button(server.name) { viewModel.selectServer(index) }.buttonStyle(.borderedProminent).tint(index == viewModel.selectedServerIndex ? .orange : .gray.opacity(0.45)) } }.padding(.horizontal, 16) }
            if let server = viewModel.selectedServer { LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) { ForEach(server.items) { episode in
                if PlayerViewModel.directMediaURL(for: episode) != nil { NavigationLink { PlayerView(movie: movie, server: server, episode: episode, watchHistoryService: watchHistoryService) } label: { Label(episode.name, systemImage: "play.fill").lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 9).cineGlass(cornerRadius: 14, tint: CineVietTheme.accent) } }
                else { Label(episode.name, systemImage: "nosign").lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(.secondary).cineGlass(cornerRadius: 14) }
            } }.padding(.horizontal, 16) }
        }
    }

    @ViewBuilder private func peopleSection(_ movie: Movie) -> some View { if !movie.directors.isEmpty || !movie.cast.isEmpty { glassPanel(title: "Diễn viên & đạo diễn") { VStack(alignment: .leading, spacing: 8) { ForEach(movie.directors.prefix(5), id: \.name) { Text("Đạo diễn: \($0.name)").foregroundStyle(.secondary) }; Text(movie.cast.prefix(20).map(\.name).joined(separator: " • ")).foregroundStyle(.secondary) } } } }
    private func relatedSection(_ movies: [Movie]) -> some View { VStack(alignment: .leading, spacing: 12) { GlassSectionHeader(title: "Có thể bạn thích"); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) { ForEach(movies) { MovieCardView(movie: $0) } }.padding(.horizontal, 16) } } }
    private func glassPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(.title3.bold()); content() }.frame(maxWidth: .infinity, alignment: .leading).padding(16).cineGlass(cornerRadius: 22).padding(.horizontal, 16) }
    private func metadata(_ movie: Movie) -> [String] { [movie.releaseYear.map(String.init), movie.quality.nonEmpty, movie.language.nonEmpty, movie.rating.map { String(format: "★ %.1f", $0) }].compactMap { $0 } + movie.genres.prefix(3) }
    private var detailBackground: some View { ZStack { CineVietTheme.background.ignoresSafeArea(); RadialGradient(colors: [CineVietTheme.accent.opacity(0.15), .clear], center: .topTrailing, startRadius: 20, endRadius: 520).ignoresSafeArea() } }
}

private struct FlowChips: View {
    let values: [String]; var accentFirst = false
    var body: some View { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 7) { ForEach(Array(values.enumerated()), id: \.offset) { index, value in Text(value).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 5).background((accentFirst && index == 0 ? CineVietTheme.accent : Color.white).opacity(0.14), in: Capsule()).overlay { Capsule().stroke((accentFirst && index == 0 ? CineVietTheme.accent : Color.white).opacity(0.25)) } } } } }
}
