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
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                switch viewModel.state {
                case .loading: ProgressView("Đang tải thông tin phim…").tint(CineVietTheme.accent).frame(maxWidth: .infinity).frame(minHeight: 600)
                case .failed(let message): ContentMessage(icon: "exclamationmark.triangle", title: "Không tải được thông tin phim", message: message).frame(maxWidth: .infinity).frame(minHeight: 520).onTapGesture { Task { await viewModel.retry() } }
                case .loaded: content(proxy, width: geometry.size.width)
                }
                }
            }
            .frame(width: geometry.size.width)
        }
        .background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar).hidesFloatingNavigation().task { await viewModel.load() }
        .fullScreenCover(item: $playerLaunch) { launch in PlayerView(movie: launch.movie, server: launch.server, episode: launch.episode, watchHistoryService: watchHistoryService).background(Color.black.ignoresSafeArea()).interactiveDismissDisabled() }
        .sheet(isPresented: $showingRating) { RatingSheet(viewModel: viewModel) }
        .sheet(isPresented: $showingComments) { CommentsSheet(viewModel: viewModel) }
        .alert("Tạo playlist", isPresented: $showingNewPlaylist) { TextField("Tên playlist", text: $newPlaylistName); Button("Tạo và thêm phim") { let name = newPlaylistName; newPlaylistName = ""; Task { await viewModel.createPlaylist(name: name) } }.disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Button("Huỷ", role: .cancel) {} }
        .alert("CineViet", isPresented: Binding(get: { viewModel.message != nil }, set: { if !$0 { viewModel.message = nil } })) { Button("OK") { viewModel.message = nil } } message: { Text(viewModel.message ?? "") }
    }

    private func content(_ proxy: ScrollViewProxy, width: CGFloat) -> some View {
        let movie = viewModel.displayedMovie
        return VStack(alignment: .leading, spacing: 0) {
            hero(movie).frame(width: width)
            VStack(alignment: .leading, spacing: 22) {
                primaryActions(movie, proxy)
                title(movie)
                metadata(movie)
                synopsis(movie)
                actions(movie)
                tabs(movie)
                section(movie)
            }
            .padding(.vertical, 22)
            .frame(width: max(0, width - 24), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(CineVietTheme.secondaryBackground.opacity(0.96))
                    .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.07)) }
            )
            .frame(width: width, alignment: .center)
            .offset(y: -24)
        }.frame(width: width, alignment: .leading).padding(.bottom, 24)
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
            Button { if let source = viewModel.firstPlayableSource { playerLaunch = PlayerLaunch(movie: movie, server: source.server, episode: source.episode) } } label: { ViewThatFits { Label(viewModel.firstPlayableSource == nil ? "Chưa có nguồn" : "Xem phim", systemImage: viewModel.firstPlayableSource == nil ? "play.slash" : "play.fill"); Image(systemName: viewModel.firstPlayableSource == nil ? "play.slash" : "play.fill") }.frame(maxWidth: .infinity, minHeight: 52) }.buttonStyle(DetailCTAStyle(primary: true)).disabled(viewModel.firstPlayableSource == nil).accessibilityHint("Mở trình phát toàn màn hình")
            Button { selectedSection = .episodes; animate { proxy.scrollTo("detail-sections", anchor: .top) } } label: { ViewThatFits { Label("Tập phim", systemImage: "list.bullet"); Image(systemName: "list.bullet") }.frame(maxWidth: .infinity, minHeight: 52) }.buttonStyle(DetailCTAStyle(primary: false)).disabled(movie.episodes.isEmpty)
        }
        .padding(8)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 14)
    }

    private func title(_ movie: Movie) -> some View { VStack(alignment: .leading, spacing: 6) { Text(movie.title).font(.system(size: 30, weight: .bold, design: .rounded)); if let original = movie.titleEn.trimmedNonEmpty, original.caseInsensitiveCompare(movie.title) != .orderedSame { Text(original).font(.title3).foregroundStyle(CineVietTheme.textMuted) } }.padding(.horizontal, 18) }

    @ViewBuilder private func metadata(_ movie: Movie) -> some View {
        let values: [String] = [movie.rating.flatMap { $0 > 0 ? String(format: "★ %0.1f", $0) : nil }, movie.quality.trimmedNonEmpty, movie.releaseYear.flatMap { $0 > 1800 ? String($0) : nil }, movie.duration.flatMap { $0 > 0 ? "\($0) phút" : nil }, movie.totalEpisodes.flatMap { $0 > 0 ? "\($0) tập" : nil }, movie.episodeCurrent.trimmedNonEmpty, movie.language.trimmedNonEmpty, movie.country.trimmedNonEmpty].compactMap { $0 }
        if !values.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(values, id: \.self) { value in Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.horizontal, 13).padding(.vertical, 9).background(.white.opacity(0.075), in: Capsule()).overlay { Capsule().stroke(.white.opacity(0.10)) } } }.padding(.horizontal, 18) } }
    }

    @ViewBuilder private func synopsis(_ movie: Movie) -> some View {
        if let text = movie.description.trimmedNonEmpty { VStack(alignment: .leading, spacing: 8) { Text("Nội dung phim").font(.headline); Text(text).foregroundStyle(CineVietTheme.textMuted).lineSpacing(5).lineLimit(synopsisExpanded ? nil : 4); Button(synopsisExpanded ? "Thu gọn" : "Xem thêm") { animate { synopsisExpanded.toggle() } }.font(.subheadline.bold()).foregroundStyle(CineVietTheme.accent).frame(minHeight: 44) }.padding(.horizontal, 18) }
    }

    private func actions(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Tiện ích", icon: "sparkles")
            HStack(alignment: .top, spacing: 0) {
                action(viewModel.isFavorite ? "heart.fill" : "heart", viewModel.isFavorite ? "Đã thích" : "Yêu thích", accent: .pink, busy: viewModel.isFavoriteBusy) { Task { await viewModel.toggleFavorite() } }
                Menu { ForEach(viewModel.playlists) { list in Button(list.name) { Task { await viewModel.addToPlaylist(list) } } }; Divider(); Button("Tạo playlist mới…") { showingNewPlaylist = true } } label: { actionLabel("text.badge.plus", "Playlist", accent: .cyan) }
                    .buttonStyle(DetailActionStyle()).accessibilityLabel("Playlist")
                action("star.fill", "Đánh giá", accent: .yellow) { showingRating = true }
                action("bubble.left.fill", "Bình luận", accent: .mint) { showingComments = true }
                ShareLink(item: canonicalURL(movie), subject: Text(movie.title), message: Text("Xem \(movie.title) trên CineViet")) { actionLabel("square.and.arrow.up", "Chia sẻ", accent: .orange) }
                    .buttonStyle(DetailActionStyle()).accessibilityLabel("Chia sẻ")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }.padding(.horizontal, 18)
    }

    private func action(_ icon: String, _ text: String, accent: Color, busy: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { busy ? AnyView(ProgressView().tint(accent).frame(maxWidth: .infinity, minHeight: 68)) : AnyView(actionLabel(icon, text, accent: accent)) }
            .buttonStyle(DetailActionStyle()).disabled(busy).accessibilityLabel(text)
    }
    private func actionLabel(_ icon: String, _ text: String, accent: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(accent).frame(height: 28)
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.88)).lineLimit(1).minimumScaleFactor(0.62)
        }.frame(maxWidth: .infinity, minHeight: 68).contentShape(Rectangle())
    }
    private func sectionHeading(_ title: String, icon: String) -> some View { Label(title, systemImage: icon).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white) }
    private func canonicalURL(_ movie: Movie) -> URL { AppEnvironment.siteBaseURL.appendingPathComponent("movie").appendingPathComponent(movie.routeKey) }

    @ViewBuilder private func tabs(_ movie: Movie) -> some View {
        let available = DetailSection.allCases.filter { $0 == .episodes ? !movie.episodes.isEmpty : ($0 == .cast ? (!movie.cast.isEmpty || !movie.directors.isEmpty) : !movie.related.isEmpty) }
        if !available.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(available) { item in Button { animate { selectedSection = item } } label: { Text(item.rawValue).font(.system(size: 14, weight: selectedSection == item ? .bold : .medium, design: .rounded)).foregroundStyle(selectedSection == item ? .black : CineVietTheme.textMuted).padding(.horizontal, 18).frame(minHeight: 42).background(selectedSection == item ? CineVietTheme.accent : CineVietTheme.panel, in: Capsule()).overlay { Capsule().stroke(selectedSection == item ? CineVietTheme.accent : CineVietTheme.border, lineWidth: 0.8) } }.buttonStyle(.plain) } }.padding(.horizontal, 18).padding(.vertical, 4) }.id("detail-sections").onAppear { if !available.contains(selectedSection), let first = available.first { selectedSection = first } } }
    }

    @ViewBuilder private func section(_ movie: Movie) -> some View {
        switch selectedSection {
        case .episodes: if let server = viewModel.selectedServer { VStack(alignment: .leading, spacing: 16) { HStack(spacing: 12) { Text(movie.episodeCurrent.trimmedNonEmpty ?? "Danh sách tập").font(.headline); Spacer(minLength: 8); if movie.episodes.count > 1 { Menu { ForEach(Array(movie.episodes.enumerated()), id: \.offset) { index, item in Button(item.name) { viewModel.selectServer(index) } } } label: { Label(server.name, systemImage: "chevron.down").font(.subheadline.weight(.semibold)).lineLimit(1).padding(.horizontal, 14).frame(minHeight: 42).background(CineVietTheme.panel, in: Capsule()).overlay { Capsule().stroke(CineVietTheme.border) } } } }; LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) { ForEach(server.items) { episode in Button { playerLaunch = PlayerLaunch(movie: movie, server: server, episode: episode) } label: { Text(episode.name).font(.system(size: 14, weight: .semibold, design: .rounded)).frame(maxWidth: .infinity, minHeight: 56).background(LinearGradient(colors: [CineVietTheme.panel, CineVietTheme.secondaryBackground], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CineVietTheme.border.opacity(0.9)) } }.buttonStyle(EpisodeButtonStyle()).disabled(PlayerViewModel.directMediaURL(for: episode) == nil).opacity(PlayerViewModel.directMediaURL(for: episode) == nil ? 0.45 : 1) } } }.padding(.horizontal, 18).padding(.top, 12) }
        case .cast: VStack(alignment: .leading, spacing: 14) { ForEach(movie.directors.filter { !$0.name.isEmpty }, id: \.name) { Text("Đạo diễn: \($0.name)").font(.subheadline) }; LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 16) { ForEach(movie.cast.filter { !$0.name.isEmpty }.prefix(30), id: \.name) { person in VStack { Circle().fill(CineVietTheme.panel).frame(width: 64, height: 64).overlay { Text(String(person.name.prefix(1))).font(.title2.bold()).foregroundStyle(CineVietTheme.accent) }; Text(person.name).font(.caption).multilineTextAlignment(.center).lineLimit(2) } } } }.padding(20)
        case .related: ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) { ForEach(movie.related) { MovieCardView(movie: $0) } }.padding(20) }
        }
    }
    private func animate(_ changes: () -> Void) { if reduceMotion { changes() } else { withAnimation(.easeInOut(duration: 0.22), changes) } }
}

private struct DetailCTAStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.bold())
            .foregroundStyle(primary ? .black : .white)
            .background(primary ? LinearGradient(colors: [CineVietTheme.accent, CineVietTheme.accent.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [CineVietTheme.panel, CineVietTheme.secondaryBackground], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(primary ? .white.opacity(0.16) : .white.opacity(0.13), lineWidth: 0.8) }
            .shadow(color: primary ? CineVietTheme.accent.opacity(0.18) : .black.opacity(0.2), radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct DetailActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.58 : 1) : 0.42)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EpisodeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RatingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MovieDetailViewModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "star.circle.fill").font(.system(size: 54)).foregroundStyle(.yellow)
                    if let stats = viewModel.ratingStats {
                        Text(String(format: "%0.1f", stats.average)).font(.system(size: 46, weight: .bold, design: .rounded))
                        if stats.total > 0 { Text("\(stats.total) lượt đánh giá").foregroundStyle(CineVietTheme.textMuted) }
                    } else { Text("Chấm điểm phim").font(.title2.bold()) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 5), spacing: 9) {
                        ForEach(1...10, id: \.self) { value in
                            let selected = (viewModel.ratingStats?.userRating ?? 0) >= value
                            Button { Task { await viewModel.rate(value) } } label: {
                                VStack(spacing: 5) { Image(systemName: selected ? "star.fill" : "star"); Text("\(value)").font(.caption.bold()) }
                                    .foregroundStyle(selected ? .black : .white)
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .background(selected ? Color.yellow : CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.10)) }
                            }.buttonStyle(EpisodeButtonStyle()).disabled(viewModel.isSubmitting)
                        }
                    }
                    if viewModel.isSubmitting { ProgressView("Đang gửi đánh giá…").tint(CineVietTheme.accent) }
                }.padding(20)
            }
            .background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle("Đánh giá phim").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Đóng") { dismiss() } }
        }.presentationDetents([.medium, .large])
    }
}

private struct CommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MovieDetailViewModel
    @State private var text = ""
    @State private var spoiler = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if viewModel.comments.isEmpty && !viewModel.isSocialLoading { ContentMessage(icon: "bubble.left", title: "Chưa có bình luận", message: "Hãy là người đầu tiên chia sẻ cảm nhận.") }
                    else { ForEach(viewModel.comments) { item in commentCard(item) } }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                VStack(spacing: 10) {
                    Toggle("Đánh dấu nội dung spoiler", isOn: $spoiler).font(.subheadline)
                    HStack(alignment: .bottom, spacing: 10) {
                        TextField("Viết bình luận…", text: $text, axis: .vertical).lineLimit(1...4).padding(12).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Button { Task { if await viewModel.addComment(text, spoiler: spoiler) { text = "" } } } label: { Image(systemName: "paperplane.fill").frame(width: 48, height: 48).background(CineVietTheme.accent, in: Circle()).foregroundStyle(.black) }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || viewModel.isSubmitting)
                    }
                }.padding(14).background(.ultraThinMaterial)
            }
            .overlay { if viewModel.isSocialLoading { ProgressView().tint(CineVietTheme.accent) } }
            .background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle("Bình luận").navigationBarTitleDisplayMode(.inline).toolbar { Button("Đóng") { dismiss() } }
        }.presentationDetents([.medium, .large])
    }
    private func commentCard(_ item: MovieComment) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Image(systemName: "person.crop.circle.fill").foregroundStyle(CineVietTheme.accent); Text(item.userName).font(.headline); Spacer(); if item.isSpoiler { Label("Spoiler", systemImage: "eye.slash.fill").font(.caption).foregroundStyle(.orange) } }
            Text(item.content).foregroundStyle(.white.opacity(0.9))
            if !item.createdAt.isEmpty { Text(item.createdAt).font(.caption2).foregroundStyle(CineVietTheme.textMuted) }
        }.padding(.vertical, 8).listRowBackground(CineVietTheme.panel.opacity(0.72)).listRowSeparator(.hidden)
    }
}

private extension String { var trimmedNonEmpty: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty || value.lowercased() == "null" || value == "0" ? nil : value } }
