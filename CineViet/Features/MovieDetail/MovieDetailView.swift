import SwiftUI

struct MovieDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MovieDetailViewModel
    let watchHistoryService: WatchHistoryServicing
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedSection = 0

    init(movie: Movie, movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing) {
        _viewModel = StateObject(wrappedValue: MovieDetailViewModel(movie: movie, movieService: movieService, libraryService: libraryService))
        self.watchHistoryService = watchHistoryService
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                switch viewModel.state {
                case .loading: ProgressView("Đang tải thông tin phim…").tint(CineVietTheme.accent).frame(maxWidth: .infinity, minHeight: 600)
                case .failed(let message): ContentMessage(icon: "exclamationmark.triangle", title: "Không tải được thông tin phim", message: message).frame(minHeight: 520).onTapGesture { Task { await viewModel.retry() } }
                case .loaded: detailContent(proxy)
                }
            }
        }
        .background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .alert("Tạo playlist", isPresented: $showingNewPlaylist) {
            TextField("Tên playlist", text: $newPlaylistName)
            Button("Tạo và thêm phim") { let name = newPlaylistName; newPlaylistName = ""; Task { await viewModel.createPlaylist(name: name) } }.disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Huỷ", role: .cancel) { }
        }
    }

    private func detailContent(_ proxy: ScrollViewProxy) -> some View {
        let movie = viewModel.displayedMovie
        return VStack(alignment: .leading, spacing: 0) {
            backdrop(movie)
            VStack(alignment: .leading, spacing: 18) {
                primaryActions(movie, proxy)
                titleBlock(movie)
                metadata(movie)
                description(movie)
                socialActions
                contentTabs(proxy)
                episodes(movie)
                people(movie)
                recommendations(movie)
            }.padding(.top, 14)
        }.padding(.bottom, 40)
    }

    private func backdrop(_ movie: Movie) -> some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: movie.backdropURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() } else { CineVietTheme.panel }
            }.frame(height: 315).clipped()
            LinearGradient(colors: [.black.opacity(0.08), .clear, CineVietTheme.background.opacity(0.38)], startPoint: .top, endPoint: .bottom)
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.bold()).frame(width: 48, height: 48).background(.black.opacity(0.58), in: Circle()).overlay { Circle().stroke(.white.opacity(0.3)) } }
                .padding(.leading, 18).padding(.top, 14)
        }
    }

    private func primaryActions(_ movie: Movie, _ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            if let source = viewModel.firstPlayableSource {
                NavigationLink { PlayerView(movie: movie, server: source.server, episode: source.episode, watchHistoryService: watchHistoryService) } label: { Label("Xem phim", systemImage: "play.fill").font(.headline.bold()).frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black)
            } else { Label("Chưa có nguồn", systemImage: "play.slash").frame(maxWidth: .infinity).padding(.vertical, 11).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 15)) }
            Button { selectedSection = 0; withAnimation { proxy.scrollTo("episodes", anchor: .top) } } label: { Label("Tập phim", systemImage: "list.bullet").font(.headline.bold()).frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
        }.padding(.horizontal, 18)
    }

    private func titleBlock(_ movie: Movie) -> some View { VStack(alignment: .leading, spacing: 5) { Text(movie.title).font(.system(size: 31, weight: .bold, design: .rounded)).lineLimit(2); if !movie.titleEn.isEmpty { Text(movie.titleEn).font(.title3).foregroundStyle(CineVietTheme.textMuted) } }.padding(.horizontal, 20) }

    private func metadata(_ movie: Movie) -> some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
            if let rating = movie.rating { metaChip(String(format: "IMDb %.1f", rating), filled: true) }
            metaChip(movie.type == "series" ? "P" : "L", filled: true)
            if !movie.quality.isEmpty { metaChip(movie.quality) }
            if let year = movie.releaseYear { metaChip(String(year)) }
            if let duration = movie.duration { metaChip("\(duration) phút") }
            if !movie.episodeCurrent.isEmpty { metaChip(movie.episodeCurrent) }
        }.padding(.horizontal, 20) }
    }

    private func metaChip(_ text: String, filled: Bool = false) -> some View { Text(text).font(.caption.bold()).foregroundStyle(filled ? .black : .white).padding(.horizontal, 10).padding(.vertical, 7).background(filled ? Color.white : CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 8)).overlay { if !filled { RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.65)) } } }

    @ViewBuilder private func description(_ movie: Movie) -> some View { if !movie.description.isEmpty { Text(movie.description).font(.body).lineSpacing(5).foregroundStyle(CineVietTheme.textMuted).lineLimit(4).padding(.horizontal, 20) } }

    private var socialActions: some View {
        HStack { actionButton(viewModel.isFavorite ? "heart.fill" : "heart", viewModel.isFavorite ? "Đã thích" : "Yêu thích") { Task { await viewModel.toggleFavorite() } }; Menu { ForEach(viewModel.playlists) { item in Button(item.name) { Task { await viewModel.addToPlaylist(item) } } }; Divider(); Button("Tạo playlist mới…") { showingNewPlaylist = true } } label: { actionLabel("plus", "Thêm vào") }; actionButton("face.smiling", "Đánh giá") { }; actionButton("bubble.left.and.bubble.right.fill", "Bình luận") { }; actionButton("paperplane.fill", "Chia sẻ") { } }.padding(.horizontal, 8)
    }

    private func actionButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View { Button(action: action) { actionLabel(icon, title) }.frame(maxWidth: .infinity) }
    private func actionLabel(_ icon: String, _ title: String) -> some View { VStack(spacing: 8) { Image(systemName: icon).font(.title2).frame(height: 28); Text(title).font(.caption2).foregroundStyle(CineVietTheme.textMuted).lineLimit(1) }.foregroundStyle(.white).frame(maxWidth: .infinity) }

    private func contentTabs(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) { sectionTab("Tập phim", 0); sectionTab("Diễn viên", 1); sectionTab("Đề xuất", 2) }.overlay(alignment: .bottom) { Rectangle().fill(CineVietTheme.border).frame(height: 1) }.padding(.top, 4)
    }
    private func sectionTab(_ title: String, _ index: Int) -> some View { Button { selectedSection = index } label: { Text(title).font(.subheadline.weight(selectedSection == index ? .bold : .regular)).foregroundStyle(selectedSection == index ? CineVietTheme.accent : CineVietTheme.textMuted).frame(maxWidth: .infinity).padding(.vertical, 14).overlay(alignment: .bottom) { if selectedSection == index { Capsule().fill(CineVietTheme.accent).frame(height: 3).padding(.horizontal, 12) } } } }

    @ViewBuilder private func episodes(_ movie: Movie) -> some View {
        if selectedSection == 0, let server = viewModel.selectedServer {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Label(movie.episodeCurrent.nonEmpty ?? "Danh sách tập", systemImage: "list.bullet").font(.headline); Spacer(); Menu { ForEach(Array(movie.episodes.enumerated()), id: \.offset) { i, source in Button(source.name) { viewModel.selectServer(i) } } } label: { Label(server.name, systemImage: "chevron.down").font(.subheadline).padding(.horizontal, 12).padding(.vertical, 9).overlay { RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.65)) } } }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) { ForEach(server.items) { episode in
                    if PlayerViewModel.directMediaURL(for: episode) != nil { NavigationLink { PlayerView(movie: movie, server: server, episode: episode, watchHistoryService: watchHistoryService) } label: { Text(episode.name).font(.headline).frame(maxWidth: .infinity, minHeight: 76).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(CineVietTheme.border) } } } else { Text(episode.name).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 76).background(CineVietTheme.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 12)) }
                } }
            }.padding(.horizontal, 20).padding(.top, 16).id("episodes")
        }
    }

    @ViewBuilder private func people(_ movie: Movie) -> some View { if selectedSection == 1 { VStack(alignment: .leading, spacing: 12) { ForEach(movie.directors.prefix(5), id: \.name) { Text("Đạo diễn: \($0.name)") }; Text(movie.cast.prefix(30).map(\.name).joined(separator: " • ")).foregroundStyle(CineVietTheme.textMuted) }.padding(20) } }
    @ViewBuilder private func recommendations(_ movie: Movie) -> some View { if selectedSection == 2 { if movie.related.isEmpty { ContentMessage(icon: "sparkles", title: "Chưa có đề xuất", message: "Danh sách phim liên quan đang được cập nhật.").frame(minHeight: 220) } else { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) { ForEach(movie.related) { MovieCardView(movie: $0) } }.padding(20) } } } }
}
