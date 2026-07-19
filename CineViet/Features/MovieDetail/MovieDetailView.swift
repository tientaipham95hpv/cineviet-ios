import SwiftUI

private struct PlayerLaunch: Identifiable { let id = UUID(); let movie: Movie; let server: EpisodeServer; let episode: EpisodeItem }
private enum DetailSection: String, CaseIterable, Identifiable { case episodes = "Tập phim", cast = "Diễn viên", related = "Đề xuất"; var id: Self { self } }

struct MovieDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: MovieDetailViewModel
    let watchHistoryService: WatchHistoryServicing
    @State private var playerLaunch: PlayerLaunch?
    @State private var selectedSection: DetailSection = .episodes
    @State private var synopsisExpanded = false
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var showingRating = false
    @State private var showingComments = false

    init(movie: Movie, movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing) {
        _viewModel = StateObject(wrappedValue: MovieDetailViewModel(movie: movie, movieService: movieService, libraryService: libraryService)); self.watchHistoryService = watchHistoryService
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                switch viewModel.state {
                case .loading: ProgressView("Đang tải thông tin phim…").tint(CineVietTheme.accent).frame(maxWidth: .infinity).frame(minHeight: 600)
                case .failed(let message): ContentMessage(icon: "exclamationmark.triangle", title: "Không tải được thông tin phim", message: message).frame(minHeight: 520).onTapGesture { Task { await viewModel.retry() } }
                case .loaded: content(proxy)
                }
            }
        }
        .background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar).hidesFloatingNavigation().task { await viewModel.load() }
        .fullScreenCover(item: $playerLaunch) { launch in PlayerView(movie: launch.movie, server: launch.server, episode: launch.episode, watchHistoryService: watchHistoryService).background(Color.black.ignoresSafeArea()).interactiveDismissDisabled() }
        .sheet(isPresented: $showingRating) { RatingSheet(viewModel: viewModel) }
        .sheet(isPresented: $showingComments) { CommentsSheet(viewModel: viewModel) }
        .alert("Tạo playlist", isPresented: $showingNewPlaylist) { TextField("Tên playlist", text: $newPlaylistName); Button("Tạo và thêm phim") { let name = newPlaylistName; newPlaylistName = ""; Task { await viewModel.createPlaylist(name: name) } }.disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Button("Huỷ", role: .cancel) {} }
        .alert("CineViet", isPresented: Binding(get: { viewModel.message != nil }, set: { if !$0 { viewModel.message = nil } })) { Button("OK") { viewModel.message = nil } } message: { Text(viewModel.message ?? "") }
    }

    private func content(_ proxy: ScrollViewProxy) -> some View {
        let movie = viewModel.displayedMovie
        return VStack(alignment: .leading, spacing: 0) {
            hero(movie)
            VStack(alignment: .leading, spacing: 18) {
                primaryActions(movie, proxy); title(movie); metadata(movie); synopsis(movie); actions(movie); tabs(movie); section(movie)
            }.padding(.top, 16)
        }.padding(.bottom, 44)
    }

    private func hero(_ movie: Movie) -> some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: movie.backdropURL) { phase in if case .success(let image) = phase { image.resizable().scaledToFill() } else { CineVietTheme.panel } }.frame(maxWidth: .infinity).frame(height: 320).clipped()
            LinearGradient(colors: [.black.opacity(0.2), .clear, CineVietTheme.background], startPoint: .top, endPoint: .bottom)
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.headline.bold()).frame(width: 48, height: 48).background(.ultraThinMaterial, in: Circle()).overlay { Circle().stroke(.white.opacity(0.25)) } }.accessibilityLabel("Quay lại").padding(.leading, 16).padding(.top, 10)
        }
    }

    private func primaryActions(_ movie: Movie, _ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Button { if let source = viewModel.firstPlayableSource { playerLaunch = PlayerLaunch(movie: movie, server: source.server, episode: source.episode) } } label: { Label(viewModel.firstPlayableSource == nil ? "Chưa có nguồn" : "Xem phim", systemImage: viewModel.firstPlayableSource == nil ? "play.slash" : "play.fill").frame(maxWidth: .infinity, minHeight: 52) }.buttonStyle(DetailCTAStyle(primary: true)).disabled(viewModel.firstPlayableSource == nil).accessibilityHint("Mở trình phát toàn màn hình")
            Button { selectedSection = .episodes; animate { proxy.scrollTo("detail-sections", anchor: .top) } } label: { Label("Tập phim", systemImage: "list.bullet").frame(maxWidth: .infinity, minHeight: 52) }.buttonStyle(DetailCTAStyle(primary: false)).disabled(movie.episodes.isEmpty)
        }.padding(.horizontal, 18)
    }

    private func title(_ movie: Movie) -> some View { VStack(alignment: .leading, spacing: 6) { Text(movie.title).font(.system(size: 30, weight: .bold, design: .rounded)); if let original = movie.titleEn.trimmedNonEmpty, original.caseInsensitiveCompare(movie.title) != .orderedSame { Text(original).font(.title3).foregroundStyle(CineVietTheme.textMuted) } }.padding(.horizontal, 20) }

    @ViewBuilder private func metadata(_ movie: Movie) -> some View {
        let values: [String] = [movie.rating.flatMap { $0 > 0 ? String(format: "★ %.1f", $0) : nil }, movie.quality.trimmedNonEmpty, movie.releaseYear.flatMap { $0 > 1800 ? String($0) : nil }, movie.duration.flatMap { $0 > 0 ? "\($0) phút" : nil }, movie.totalEpisodes.flatMap { $0 > 0 ? "\($0) tập" : nil }, movie.episodeCurrent.trimmedNonEmpty, movie.language.trimmedNonEmpty, movie.country.trimmedNonEmpty].compactMap { $0 }
        if !values.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(values, id: \.self) { value in Text(value).font(.caption.bold()).padding(.horizontal, 11).padding(.vertical, 8).background(CineVietTheme.panel, in: Capsule()).overlay { Capsule().stroke(CineVietTheme.border) } } }.padding(.horizontal, 20) } }
    }

    @ViewBuilder private func synopsis(_ movie: Movie) -> some View {
        if let text = movie.description.trimmedNonEmpty { VStack(alignment: .leading, spacing: 8) { Text("Nội dung phim").font(.headline); Text(text).foregroundStyle(CineVietTheme.textMuted).lineSpacing(5).lineLimit(synopsisExpanded ? nil : 4); Button(synopsisExpanded ? "Thu gọn" : "Xem thêm") { animate { synopsisExpanded.toggle() } }.font(.subheadline.bold()).foregroundStyle(CineVietTheme.accent).frame(minHeight: 44) }.padding(.horizontal, 20) }
    }

    private func actions(_ movie: Movie) -> some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
            action(viewModel.isFavorite ? "heart.fill" : "heart", viewModel.isFavorite ? "Đã thích" : "Yêu thích", busy: viewModel.isFavoriteBusy) { Task { await viewModel.toggleFavorite() } }
            Menu { ForEach(viewModel.playlists) { list in Button(list.name) { Task { await viewModel.addToPlaylist(list) } } }; Divider(); Button("Tạo playlist mới…") { showingNewPlaylist = true } } label: { actionLabel("plus", "Playlist") }
            action("star", "Đánh giá") { showingRating = true }; action("bubble.left", "Bình luận") { showingComments = true }
            ShareLink(item: canonicalURL(movie), subject: Text(movie.title), message: Text("Xem \(movie.title) trên CineViet")) { actionLabel("square.and.arrow.up", "Chia sẻ") }
        }.padding(.horizontal, 14) }
    }

    private func action(_ icon: String, _ text: String, busy: Bool = false, perform: @escaping () -> Void) -> some View { Button(action: perform) { if busy { ProgressView().tint(.white).frame(width: 78, minHeight: 64) } else { actionLabel(icon, text) } }.buttonStyle(DetailActionStyle()).disabled(busy).accessibilityLabel(text) }
    private func actionLabel(_ icon: String, _ text: String) -> some View { VStack(spacing: 7) { Image(systemName: icon).font(.title3).frame(height: 25); Text(text).font(.caption2).lineLimit(1) }.frame(width: 78, minHeight: 64).contentShape(Rectangle()) }
    private func canonicalURL(_ movie: Movie) -> URL { URL(string: "https://cineviet.live/phim/\(movie.routeKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? movie.routeKey)")! }

    @ViewBuilder private func tabs(_ movie: Movie) -> some View {
        let available = DetailSection.allCases.filter { $0 == .episodes ? !movie.episodes.isEmpty : ($0 == .cast ? (!movie.cast.isEmpty || !movie.directors.isEmpty) : !movie.related.isEmpty) }
        if !available.isEmpty { HStack(spacing: 0) { ForEach(available) { item in Button { animate { selectedSection = item } } label: { Text(item.rawValue).font(.subheadline.weight(selectedSection == item ? .bold : .regular)).foregroundStyle(selectedSection == item ? CineVietTheme.accent : CineVietTheme.textMuted).frame(maxWidth: .infinity, minHeight: 50).overlay(alignment: .bottom) { if selectedSection == item { Capsule().fill(CineVietTheme.accent).frame(height: 3).padding(.horizontal, 14) } } } } }.overlay(alignment: .bottom) { Rectangle().fill(CineVietTheme.border).frame(height: 1) }.id("detail-sections").onAppear { if !available.contains(selectedSection), let first = available.first { selectedSection = first } } }
    }

    @ViewBuilder private func section(_ movie: Movie) -> some View {
        switch selectedSection {
        case .episodes: if let server = viewModel.selectedServer { VStack(alignment: .leading, spacing: 14) { HStack { Text(movie.episodeCurrent.trimmedNonEmpty ?? "Danh sách tập").font(.headline); Spacer(); if movie.episodes.count > 1 { Menu { ForEach(Array(movie.episodes.enumerated()), id: \.offset) { index, item in Button(item.name) { viewModel.selectServer(index) } } } label: { Label(server.name, systemImage: "chevron.down").padding(10).overlay { RoundedRectangle(cornerRadius: 10).stroke(CineVietTheme.border) } } } }; LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) { ForEach(server.items) { episode in Button { playerLaunch = PlayerLaunch(movie: movie, server: server, episode: episode) } label: { Text(episode.name).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 58).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(CineVietTheme.border) } }.buttonStyle(EpisodeButtonStyle()).disabled(PlayerViewModel.directMediaURL(for: episode) == nil).opacity(PlayerViewModel.directMediaURL(for: episode) == nil ? 0.45 : 1) } } }.padding(20)
        case .cast: VStack(alignment: .leading, spacing: 14) { ForEach(movie.directors.filter { !$0.name.isEmpty }, id: \.name) { Text("Đạo diễn: \($0.name)").font(.subheadline) }; LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 16) { ForEach(movie.cast.filter { !$0.name.isEmpty }.prefix(30), id: \.name) { person in VStack { Circle().fill(CineVietTheme.panel).frame(width: 64, height: 64).overlay { Text(String(person.name.prefix(1))).font(.title2.bold()).foregroundStyle(CineVietTheme.accent) }; Text(person.name).font(.caption).multilineTextAlignment(.center).lineLimit(2) } } } }.padding(20)
        case .related: ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) { ForEach(movie.related) { MovieCardView(movie: $0) } }.padding(20) }
        }
    }
    private func animate(_ changes: () -> Void) { if reduceMotion { changes() } else { withAnimation(.easeInOut(duration: 0.22), changes) } }
}

private struct DetailCTAStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.bold())
            .foregroundStyle(primary ? .black : .white)
            .background(primary ? CineVietTheme.accent : CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(primary ? CineVietTheme.accent : .white.opacity(0.25)) }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct DetailActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(CineVietTheme.border) }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EpisodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RatingSheet: View {
    @Environment(\.dismiss) private var dismiss; @ObservedObject var viewModel: MovieDetailViewModel
    var body: some View { NavigationStack { VStack(spacing: 22) { if let stats = viewModel.ratingStats { Text(String(format: "%.1f / 10", stats.average)).font(.largeTitle.bold()); if stats.total > 0 { Text("\(stats.total) lượt đánh giá").foregroundStyle(.secondary) } }; LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) { ForEach(1...10, id: \.self) { value in Button { Task { await viewModel.rate(value) } } label: { VStack { Image(systemName: (viewModel.ratingStats?.userRating ?? 0) >= value ? "star.fill" : "star"); Text("\(value)") }.frame(maxWidth: .infinity, minHeight: 52) }.buttonStyle(.bordered).tint(.yellow).disabled(viewModel.isSubmitting) } }; Spacer() }.padding().background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white).navigationTitle("Đánh giá phim").toolbar { Button("Đóng") { dismiss() } } }.presentationDetents([.medium]) }
}

private struct CommentsSheet: View {
    @Environment(\.dismiss) private var dismiss; @ObservedObject var viewModel: MovieDetailViewModel; @State private var text = ""; @State private var spoiler = false
    var body: some View { NavigationStack { VStack(spacing: 12) { HStack { TextField("Viết bình luận…", text: $text, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder); Button { Task { if await viewModel.addComment(text, spoiler: spoiler) { text = "" } } } label: { Image(systemName: "paperplane.fill").frame(width: 44, height: 44) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || viewModel.isSubmitting) }; Toggle("Có nội dung spoiler", isOn: $spoiler).font(.subheadline); if viewModel.isSocialLoading { ProgressView() }; List { if viewModel.comments.isEmpty && !viewModel.isSocialLoading { Text("Chưa có bình luận").foregroundStyle(.secondary) } else { ForEach(viewModel.comments) { item in VStack(alignment: .leading, spacing: 6) { Text(item.userName).font(.headline); if item.isSpoiler { Label("Có spoiler", systemImage: "eye.slash").font(.caption).foregroundStyle(.orange) }; Text(item.content); if !item.createdAt.isEmpty { Text(item.createdAt).font(.caption2).foregroundStyle(.secondary) } }.listRowBackground(CineVietTheme.panel) } } }.scrollContentBackground(.hidden) }.padding([.horizontal, .top]).background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white).navigationTitle("Bình luận").toolbar { Button("Đóng") { dismiss() } } } }
}

private extension String { var trimmedNonEmpty: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty || value.lowercased() == "null" || value == "0" ? nil : value } }
