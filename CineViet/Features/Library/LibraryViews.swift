import SwiftUI

private enum LibrarySection: String, CaseIterable, Identifiable {
    case favorites = "Yêu thích"
    case playlists = "Playlist"
    case history = "Đang xem"
    var id: String { rawValue }
    var icon: String {
        switch self { case .favorites: "heart.fill"; case .playlists: "rectangle.stack.fill"; case .history: "play.circle.fill" }
    }
}

@MainActor final class LibraryViewModel: ObservableObject {
    @Published private(set) var favorites: [Movie] = []
    @Published private(set) var playlists: [CinePlaylist] = []
    @Published private(set) var history: [WatchHistoryItem] = []
    @Published private(set) var historyMovies: [Int: Movie] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var removingFavoriteIDs: Set<Int> = []
    @Published private(set) var removingHistoryIDs: Set<Int> = []
    @Published var errorMessage: String?

    let movieService: MovieServicing
    let historyService: WatchHistoryServicing
    let libraryService: LibraryServicing

    init(movieService: MovieServicing, historyService: WatchHistoryServicing, libraryService: LibraryServicing) {
        self.movieService = movieService; self.historyService = historyService; self.libraryService = libraryService
    }

    func load() async {
        isLoading = true; errorMessage = nil
        async let favoriteRequest = libraryService.favorites()
        async let playlistRequest = libraryService.playlists()
        let historyRows = await historyService.continueWatching(limit: 30)
        do {
            let (favoriteRows, playlistRows) = try await (favoriteRequest, playlistRequest)
            favorites = favoriteRows; playlists = playlistRows; history = historyRows
            await loadHistoryMovies(historyRows)
        } catch { errorMessage = error.localizedDescription; history = historyRows; await loadHistoryMovies(historyRows) }
        isLoading = false
    }

    func removeFavorite(_ movie: Movie) async {
        guard !removingFavoriteIDs.contains(movie.id), let index = favorites.firstIndex(of: movie) else { return }
        removingFavoriteIDs.insert(movie.id); favorites.remove(at: index)
        do { try await libraryService.toggleFavorite(movieID: movie.id, add: false) }
        catch { favorites.insert(movie, at: min(index, favorites.count)); errorMessage = error.localizedDescription }
        removingFavoriteIDs.remove(movie.id)
    }

    func removeHistory(_ item: WatchHistoryItem) async {
        guard !removingHistoryIDs.contains(item.movieId) else { return }
        removingHistoryIDs.insert(item.movieId)
        history.removeAll { $0.movieId == item.movieId }
        historyMovies[item.movieId] = nil
        await historyService.delete(movieID: item.movieId)
        removingHistoryIDs.remove(item.movieId)
    }

    func createPlaylist(name: String, description: String, isPublic: Bool) async -> Bool {
        do { playlists.insert(try await libraryService.createPlaylist(name: name, description: description, isPublic: isPublic), at: 0); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    private func loadHistoryMovies(_ rows: [WatchHistoryItem]) async {
        await withTaskGroup(of: (Int, Movie?).self) { group in
            for id in Set(rows.map(\.movieId)).prefix(12) { group.addTask { [movieService] in (id, try? await movieService.detail(idOrSlug: String(id))) } }
            for await (id, movie) in group { if let movie { historyMovies[id] = movie } }
        }
    }
}

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @State private var section: LibrarySection = .favorites
    @State private var selectedMovie: Movie?
    @State private var showingCreate = false
    let movieService: MovieServicing; let watchHistoryService: WatchHistoryServicing; let libraryService: LibraryServicing

    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing) {
        self.movieService = movieService; self.watchHistoryService = watchHistoryService; self.libraryService = libraryService
        _viewModel = StateObject(wrappedValue: LibraryViewModel(movieService: movieService, historyService: watchHistoryService, libraryService: libraryService))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        header
                        sectionPicker
                        content(width: proxy.size.width)
                        Color.clear.frame(height: 96)
                    }.padding(.top, 10)
                }
                .refreshable { await viewModel.load() }
                .background(CineVietTheme.background.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { if viewModel.favorites.isEmpty && viewModel.playlists.isEmpty && viewModel.history.isEmpty { await viewModel.load() } }
            .sheet(isPresented: $showingCreate) { PlaylistEditorSheet(title: "Tạo playlist", name: "", description: "", isPublic: false, save: viewModel.createPlaylist) }
            .alert("Có lỗi xảy ra", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) { Button("Thử lại") { Task { await viewModel.load() } }; Button("Đóng", role: .cancel) {} } message: { Text(viewModel.errorMessage ?? "") }
            .navigationDestination(isPresented: Binding(get: { selectedMovie != nil }, set: { if !$0 { selectedMovie = nil } })) { if let movie = selectedMovie { MovieDetailView(movie: movie, movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService) } }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) { Text("Thư viện").font(.largeTitle.bold()); Text("Mọi thứ bạn đã lưu, ở cùng một nơi").font(.subheadline).foregroundStyle(CineVietTheme.textMuted) }
            Spacer()
            if section == .playlists { Button { showingCreate = true } label: { Image(systemName: "plus").font(.headline).frame(width: 48, height: 48).background(CineVietTheme.accent, in: Circle()).foregroundStyle(.black) }.accessibilityLabel("Tạo playlist") }
        }.padding(.horizontal, 16)
    }

    private var sectionPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ForEach(LibrarySection.allCases) { sectionButton($0) } }.padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(LibrarySection.allCases) { sectionButton($0) } }.padding(.horizontal, 16) }
        }
    }

    private func sectionButton(_ item: LibrarySection) -> some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { section = item } } label: {
            Label(item.rawValue, systemImage: item.icon).font(.subheadline.weight(.bold)).padding(.horizontal, 16).frame(minHeight: 46)
                .background(section == item ? CineVietTheme.accent : CineVietTheme.panel, in: Capsule()).foregroundStyle(section == item ? .black : .primary)
                .overlay { Capsule().stroke(CineVietTheme.border, lineWidth: section == item ? 0 : 1) }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func content(width: CGFloat) -> some View {
        if viewModel.isLoading && viewModel.favorites.isEmpty && viewModel.playlists.isEmpty && viewModel.history.isEmpty { loadingGrid(width: width) }
        else { switch section { case .favorites: favorites(width: width); case .playlists: playlists; case .history: history } }
    }

    @ViewBuilder private func favorites(width: CGFloat) -> some View {
        if viewModel.favorites.isEmpty { state(icon: "heart", title: "Chưa có phim yêu thích", message: "Nhấn biểu tượng trái tim ở trang chi tiết để lưu phim tại đây.") }
        else { LazyVGrid(columns: columns(width), spacing: 20) { ForEach(viewModel.favorites) { movie in ZStack(alignment: .topTrailing) { Button { selectedMovie = movie } label: { MovieCardView(movie: movie) }.buttonStyle(.plain); Button { Task { await viewModel.removeFavorite(movie) } } label: { Image(systemName: "heart.slash.fill").font(.subheadline.bold()).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle()).foregroundStyle(.red) }.disabled(viewModel.removingFavoriteIDs.contains(movie.id)).accessibilityLabel("Bỏ yêu thích \(movie.title)") }.opacity(viewModel.removingFavoriteIDs.contains(movie.id) ? 0.55 : 1) } }.padding(.horizontal, 16) }
    }

    @ViewBuilder private var playlists: some View {
        if viewModel.playlists.isEmpty { state(icon: "rectangle.stack", title: "Chưa có playlist", message: "Tạo playlist đầu tiên để sắp xếp những phim bạn muốn xem.", action: "Tạo playlist") { showingCreate = true } }
        else { LazyVStack(spacing: 12) { ForEach(viewModel.playlists) { item in NavigationLink { PlaylistDetailView(playlist: item, movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService) } label: { PlaylistRow(playlist: item) }.buttonStyle(.plain) } }.padding(.horizontal, 16) }
    }

    @ViewBuilder private var history: some View {
        if viewModel.history.isEmpty {
            state(icon: "play.circle", title: "Chưa có phim đang xem", message: "Tiến độ xem sẽ tự động xuất hiện tại đây.")
        } else {
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.history.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Button {
                            if let movie = viewModel.historyMovies[item.movieId] { selectedMovie = movie }
                        } label: {
                            HistoryRow(item: item, movie: viewModel.historyMovies[item.movieId])
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.historyMovies[item.movieId] == nil)

                        Button(role: .destructive) {
                            Task { await viewModel.removeHistory(item) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.title3).padding(10)
                        }
                        .accessibilityLabel("Xóa \(viewModel.historyMovies[item.movieId]?.title ?? "phim") khỏi Xem tiếp")
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func columns(_ width: CGFloat) -> [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 14), count: width >= 900 ? 5 : width >= 650 ? 4 : width >= 390 ? 3 : 2) }
    private func loadingGrid(width: CGFloat) -> some View { LazyVGrid(columns: columns(width), spacing: 20) { ForEach(0..<8, id: \.self) { _ in RoundedRectangle(cornerRadius: 16).fill(CineVietTheme.panel).aspectRatio(0.69, contentMode: .fit).accessibilityHidden(true) } }.padding(.horizontal, 16).redacted(reason: .placeholder) }
    private func state(icon: String, title: String, message: String, action: String? = nil, perform: @escaping () -> Void = {}) -> some View { VStack(spacing: 14) { Image(systemName: icon).font(.system(size: 38)).foregroundStyle(CineVietTheme.accent); Text(title).font(.title3.bold()); Text(message).font(.subheadline).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.center); if let action { Button(action, action: perform).buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black) } }.frame(maxWidth: .infinity, minHeight: 300).padding(24) }
}

struct FavoritesView: View {
    let movieService: MovieServicing; let watchHistoryService: WatchHistoryServicing; let libraryService: LibraryServicing
    var body: some View { LibraryView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService) }
}

private struct PlaylistRow: View {
    let playlist: CinePlaylist
    var body: some View { HStack(spacing: 14) { ZStack { RoundedRectangle(cornerRadius: 16).fill(CineVietTheme.accent.opacity(0.16)); Image(systemName: "rectangle.stack.fill").font(.title2).foregroundStyle(CineVietTheme.accent) }.frame(width: 66, height: 72); VStack(alignment: .leading, spacing: 6) { Text(playlist.name).font(.headline).lineLimit(2); Text("\(playlist.movieCount) phim  •  \(playlist.isPublic ? "Công khai" : "Riêng tư")").font(.caption.weight(.medium)).foregroundStyle(CineVietTheme.textMuted); if !playlist.description.isEmpty { Text(playlist.description).font(.caption).foregroundStyle(CineVietTheme.textMuted).lineLimit(1) } }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(CineVietTheme.textMuted) }.padding(12).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 20)).overlay { RoundedRectangle(cornerRadius: 20).stroke(CineVietTheme.border, lineWidth: 1) }.accessibilityElement(children: .combine) }
}

private struct HistoryRow: View {
    let item: WatchHistoryItem; let movie: Movie?
    var progress: Double { min(max(item.positionSeconds / max(item.durationSeconds, 1), 0), 1) }
    var body: some View { HStack(spacing: 14) { AsyncImage(url: movie?.posterURL) { image in image.resizable().scaledToFill() } placeholder: { ZStack { CineVietTheme.panel; Image(systemName: "film") } }.frame(width: 82, height: 112).clipShape(RoundedRectangle(cornerRadius: 14)); VStack(alignment: .leading, spacing: 7) { Text(movie?.title ?? "Đang tải thông tin phim…").font(.headline).lineLimit(2); Text([item.episodeName, item.serverName].filter { !$0.isEmpty }.joined(separator: " • ")).font(.caption).foregroundStyle(CineVietTheme.textMuted).lineLimit(1); ProgressView(value: progress).tint(CineVietTheme.accent); Text("Đã xem \(Int(progress * 100))%").font(.caption2.weight(.semibold)).foregroundStyle(CineVietTheme.textMuted); Label("Tiếp tục xem", systemImage: "play.fill").font(.caption.bold()).foregroundStyle(CineVietTheme.accent) }; Spacer() }.padding(12).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 20)).overlay { RoundedRectangle(cornerRadius: 20).stroke(CineVietTheme.border, lineWidth: 1) }.accessibilityElement(children: .combine) }
}

@MainActor final class PlaylistDetailViewModel: ObservableObject {
    @Published private(set) var detail: PlaylistDetail?; @Published private(set) var isLoading = false; @Published var errorMessage: String?; @Published var isDeleted = false
    let service: LibraryServicing; let initial: CinePlaylist
    init(playlist: CinePlaylist, service: LibraryServicing) { initial = playlist; self.service = service }
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await service.playlistDetail(detail?.playlist ?? initial)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    func update(name: String, description: String, isPublic: Bool) async -> Bool { guard let detail else { return false }; do { let updated = try await service.updatePlaylist(detail.playlist.id, name: name, description: description, isPublic: isPublic); self.detail = PlaylistDetail(playlist: updated, movies: detail.movies); return true } catch { errorMessage = error.localizedDescription; return false } }
    func remove(_ movie: Movie) async { guard let detail else { return }; do { try await service.remove(movieID: movie.id, from: detail.playlist.id); self.detail = PlaylistDetail(playlist: detail.playlist, movies: detail.movies.filter { $0.id != movie.id }) } catch { errorMessage = error.localizedDescription } }
    func delete() async { do { try await service.deletePlaylist((detail?.playlist ?? initial).id); isDeleted = true } catch { errorMessage = error.localizedDescription } }
}

struct PlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlaylistDetailViewModel
    @State private var confirmDelete = false
    @State private var showingEditor = false
    @State private var selectedMovie: Movie?
    let movieService: MovieServicing
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing

    init(playlist: CinePlaylist, movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing) {
        self.movieService = movieService
        self.watchHistoryService = watchHistoryService
        self.libraryService = libraryService
        _viewModel = StateObject(wrappedValue: PlaylistDetailViewModel(playlist: playlist, service: libraryService))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                ProgressView("Đang tải playlist…")
            } else if let detail = viewModel.detail {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(detail.playlist.isPublic ? "Công khai" : "Riêng tư", systemImage: detail.playlist.isPublic ? "globe" : "lock.fill")
                                Spacer()
                                Button("Chỉnh sửa") { showingEditor = true }
                            }
                            if !detail.playlist.description.isEmpty {
                                Text(detail.playlist.description).foregroundStyle(CineVietTheme.textMuted)
                            }
                        }
                        .padding(16)
                        .cineGlass(cornerRadius: 20, tint: CineVietTheme.accent)
                        .padding(.horizontal)

                        if detail.movies.isEmpty {
                            ContentMessage(icon: "rectangle.stack", title: "Playlist chưa có phim", message: "Thêm phim từ trang chi tiết.")
                                .frame(minHeight: 280)
                        } else {
                            ForEach(detail.movies) { movie in
                                HStack {
                                    Button { selectedMovie = movie } label: { MovieCardView(movie: movie) }
                                        .buttonStyle(.plain)
                                    Spacer()
                                    Button(role: .destructive) { Task { await viewModel.remove(movie) } } label: {
                                        Label("Gỡ", systemImage: "minus.circle.fill")
                                    }
                                    .frame(minWidth: 60)
                                }
                                .padding(.horizontal)
                            }
                            Button("Xoá playlist", role: .destructive) { confirmDelete = true }
                                .buttonStyle(.bordered)
                                .padding(.bottom, 30)
                        }
                    }
                }
            } else if let error = viewModel.errorMessage {
                ContentMessage(icon: "exclamationmark.triangle", title: "Không tải được playlist", message: error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Đang mở playlist…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CineVietTheme.background.ignoresSafeArea())
        .navigationTitle(viewModel.detail?.playlist.name ?? viewModel.initial.name)
        .hidesFloatingNavigation()
        .task { await viewModel.load() }
        .onChange(of: viewModel.isDeleted) { if $0 { dismiss() } }
        .sheet(isPresented: $showingEditor) {
            let item = viewModel.detail?.playlist ?? viewModel.initial
            PlaylistEditorSheet(title: "Chỉnh sửa playlist", name: item.name, description: item.description, isPublic: item.isPublic, save: viewModel.update)
        }
        .confirmationDialog("Xoá playlist này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá playlist", role: .destructive) { Task { await viewModel.delete() } }
            Button("Huỷ", role: .cancel) {}
        }
        .navigationDestination(isPresented: Binding(get: { selectedMovie != nil }, set: { if !$0 { selectedMovie = nil } })) {
            if let movie = selectedMovie {
                MovieDetailView(movie: movie, movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService)
            }
        }
    }
}

private struct PlaylistEditorSheet: View {
    @Environment(\.dismiss) private var dismiss; let title: String; @State var name: String; @State var description: String; @State var isPublic: Bool; let save: (String, String, Bool) async -> Bool; @State private var isSaving = false
    var body: some View { NavigationStack { Form { Section("Thông tin") { TextField("Tên playlist", text: $name); TextField("Mô tả", text: $description, axis: .vertical).lineLimit(3...6) }; Section { Toggle(isOn: $isPublic) { Label(isPublic ? "Công khai" : "Riêng tư", systemImage: isPublic ? "globe" : "lock.fill") } } }.scrollContentBackground(.hidden).background(CineVietTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Đang lưu…" : "Lưu") { isSaving = true; Task { if await save(name.trimmingCharacters(in: .whitespacesAndNewlines), description.trimmingCharacters(in: .whitespacesAndNewlines), isPublic) { dismiss() }; isSaving = false } }.disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } } }
}
