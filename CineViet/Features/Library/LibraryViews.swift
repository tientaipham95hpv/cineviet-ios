import SwiftUI

@MainActor final class FavoritesViewModel: ObservableObject {
    @Published private(set) var movies: [Movie] = []; @Published private(set) var isLoading = false; @Published var errorMessage: String?
    let libraryService: LibraryServicing; init(libraryService: LibraryServicing) { self.libraryService = libraryService }
    func load() async { isLoading = true; defer { isLoading = false }; do { movies = try await libraryService.favorites(); errorMessage = nil } catch { errorMessage = error.localizedDescription } }
}

struct FavoritesView: View {
    @StateObject private var viewModel: FavoritesViewModel; @State private var selectedMovie: Movie?
    let movieService: MovieServicing; let watchHistoryService: WatchHistoryServicing; let libraryService: LibraryServicing
    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing) { _viewModel = StateObject(wrappedValue: FavoritesViewModel(libraryService: libraryService)); self.movieService = movieService; self.watchHistoryService = watchHistoryService; self.libraryService = libraryService }
    var body: some View { NavigationStack { Group {
        if viewModel.isLoading && viewModel.movies.isEmpty { ProgressView("Đang tải yêu thích…") }
        else if let error = viewModel.errorMessage { ContentMessage(icon: "heart.slash", title: "Không tải được yêu thích", message: error) }
        else if viewModel.movies.isEmpty { ContentMessage(icon: "heart", title: "Chưa có phim yêu thích", message: "Thêm phim từ trang chi tiết để xem lại tại đây.") }
        else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 18) { ForEach(viewModel.movies) { movie in MovieCardView(movie: movie).onTapGesture { selectedMovie = movie } } }.padding() }.refreshable { await viewModel.load() } }
    }.navigationTitle("Yêu thích").background(CineVietTheme.background.ignoresSafeArea()).task { await viewModel.load() }.navigationDestination(isPresented: Binding(get: { selectedMovie != nil }, set: { if !$0 { selectedMovie = nil } })) { if let movie = selectedMovie { MovieDetailView(movie: movie, movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService) } } } }
}

@MainActor final class PlaylistsViewModel: ObservableObject {
    @Published private(set) var playlists: [CinePlaylist] = []; @Published private(set) var isLoading = false; @Published var errorMessage: String?
    let service: LibraryServicing; init(service: LibraryServicing) { self.service = service }
    func load() async { isLoading = true; defer { isLoading = false }; do { playlists = try await service.playlists(); errorMessage = nil } catch { errorMessage = error.localizedDescription } }
}

struct PlaylistsView: View {
    @StateObject private var viewModel: PlaylistsViewModel; let libraryService: LibraryServicing
    init(libraryService: LibraryServicing) { self.libraryService = libraryService; _viewModel = StateObject(wrappedValue: PlaylistsViewModel(service: libraryService)) }
    var body: some View { NavigationStack { Group {
        if viewModel.isLoading && viewModel.playlists.isEmpty { ProgressView("Đang tải playlist…") }
        else if let error = viewModel.errorMessage { ContentMessage(icon: "rectangle.stack.badge.exclamationmark", title: "Không tải được playlist", message: error) }
        else if viewModel.playlists.isEmpty { ContentMessage(icon: "rectangle.stack", title: "Chưa có playlist", message: "Tạo playlist từ trang chi tiết phim.") }
        else { List(viewModel.playlists) { item in NavigationLink { PlaylistDetailView(playlist: item, libraryService: libraryService) } label: { VStack(alignment: .leading, spacing: 5) { Text(item.name).font(.headline); Text("\(item.movieCount) phim • \(item.isPublic ? "Công khai" : "Riêng tư")").font(.caption).foregroundStyle(.secondary); if !item.description.isEmpty { Text(item.description).font(.subheadline) } }.padding(.vertical, 6) } }.scrollContentBackground(.hidden).refreshable { await viewModel.load() } }
    }.navigationTitle("Playlist").background(CineVietTheme.background.ignoresSafeArea()).task { await viewModel.load() }.onAppear { Task { await viewModel.load() } } } }
}

@MainActor final class PlaylistDetailViewModel: ObservableObject {
    @Published private(set) var detail: PlaylistDetail?; @Published private(set) var isLoading = false; @Published var errorMessage: String?; @Published var isDeleted = false
    let service: LibraryServicing; let initial: CinePlaylist
    init(playlist: CinePlaylist, service: LibraryServicing) { initial = playlist; self.service = service }
    func load() async { isLoading = true; defer { isLoading = false }; do { detail = try await service.playlistDetail(detail?.playlist ?? initial); errorMessage = nil } catch { errorMessage = error.localizedDescription } }
    func toggleVisibility() async { guard let detail else { return }; do { let updated = try await service.updatePlaylist(detail.playlist.id, isPublic: !detail.playlist.isPublic); self.detail = PlaylistDetail(playlist: updated, movies: detail.movies) } catch { errorMessage = error.localizedDescription } }
    func remove(_ movie: Movie) async { guard let detail else { return }; do { try await service.remove(movieID: movie.id, from: detail.playlist.id); self.detail = PlaylistDetail(playlist: detail.playlist, movies: detail.movies.filter { $0.id != movie.id }) } catch { errorMessage = error.localizedDescription } }
    func delete() async { do { try await service.deletePlaylist((detail?.playlist ?? initial).id); isDeleted = true } catch { errorMessage = error.localizedDescription } }
}

struct PlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss; @StateObject private var viewModel: PlaylistDetailViewModel; @State private var confirmDelete = false
    init(playlist: CinePlaylist, libraryService: LibraryServicing) { _viewModel = StateObject(wrappedValue: PlaylistDetailViewModel(playlist: playlist, service: libraryService)) }
    var body: some View { Group {
        if viewModel.isLoading && viewModel.detail == nil { ProgressView("Đang tải playlist…") }
        else if let error = viewModel.errorMessage, viewModel.detail == nil { ContentMessage(icon: "exclamationmark.triangle", title: "Không tải được playlist", message: error) }
        else if let detail = viewModel.detail { ScrollView { VStack(spacing: 18) {
            HStack { Label(detail.playlist.isPublic ? "Công khai" : "Riêng tư", systemImage: detail.playlist.isPublic ? "globe" : "lock.fill"); Spacer(); Button("Đổi chế độ") { Task { await viewModel.toggleVisibility() } } }.padding(16).cineGlass(cornerRadius: 20, tint: .orange).padding(.horizontal)
            if detail.movies.isEmpty { ContentMessage(icon: "rectangle.stack", title: "Playlist chưa có phim", message: "Thêm phim từ trang chi tiết.").frame(minHeight: 280) }
            else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 18) { ForEach(detail.movies) { movie in ZStack(alignment: .topTrailing) { MovieCardView(movie: movie); Button { Task { await viewModel.remove(movie) } } label: { Image(systemName: "xmark").padding(8).cineGlass(cornerRadius: 14, tint: .red) }.padding(6) } } }.padding() }
            Button("Xoá playlist", role: .destructive) { confirmDelete = true }.buttonStyle(.bordered).padding(.bottom, 30)
        } } }
    }.background(CineVietTheme.background.ignoresSafeArea()).navigationTitle(viewModel.detail?.playlist.name ?? viewModel.initial.name).task { await viewModel.load() }.onChange(of: viewModel.isDeleted) { if $0 { dismiss() } }.confirmationDialog("Xoá playlist này?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Xoá playlist", role: .destructive) { Task { await viewModel.delete() } }; Button("Huỷ", role: .cancel) { } } }
}
