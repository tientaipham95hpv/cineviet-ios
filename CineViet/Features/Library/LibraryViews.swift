import SwiftUI

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    let libraryService: LibraryServicing
    init(libraryService: LibraryServicing) { self.libraryService = libraryService }
    func load() async { isLoading = true; defer { isLoading = false }; do { movies = try await libraryService.favorites() } catch { errorMessage = error.localizedDescription } }
}

struct FavoritesView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @State private var selectedMovie: Movie?
    let movieService: MovieServicing
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing
    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing) {
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(libraryService: libraryService)); self.movieService = movieService; self.watchHistoryService = watchHistoryService; self.libraryService = libraryService
    }
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.movies.isEmpty { ProgressView("Đang tải yêu thích…") }
                else if let error = viewModel.errorMessage { ContentMessage(icon: "heart.slash", title: "Không tải được yêu thích", message: error) }
                else if viewModel.movies.isEmpty { ContentMessage(icon: "heart", title: "Chưa có phim yêu thích", message: "Thêm phim từ trang chi tiết để xem lại tại đây.") }
                else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 18) { ForEach(viewModel.movies) { movie in MovieCardView(movie: movie).onTapGesture { selectedMovie = movie } } }.padding() }.refreshable { await viewModel.load() } }
            }
            .navigationTitle("Yêu thích")
            .task { await viewModel.load() }
            .navigationDestination(isPresented: Binding(get: { selectedMovie != nil }, set: { if !$0 { selectedMovie = nil } })) { if let movie = selectedMovie { MovieDetailView(movie: movie, movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService) } }
        }
    }
}

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published private(set) var playlists: [CinePlaylist] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    let service: LibraryServicing
    init(service: LibraryServicing) { self.service = service }
    func load() async { isLoading = true; defer { isLoading = false }; do { playlists = try await service.playlists() } catch { errorMessage = error.localizedDescription } }
}

struct PlaylistsView: View {
    @StateObject private var viewModel: PlaylistsViewModel
    init(libraryService: LibraryServicing) { _viewModel = StateObject(wrappedValue: PlaylistsViewModel(service: libraryService)) }
    var body: some View { NavigationStack { Group {
        if viewModel.isLoading && viewModel.playlists.isEmpty { ProgressView("Đang tải playlist…") }
        else if let error = viewModel.errorMessage { ContentMessage(icon: "rectangle.stack.badge.exclamationmark", title: "Không tải được playlist", message: error) }
        else if viewModel.playlists.isEmpty { ContentMessage(icon: "rectangle.stack", title: "Chưa có playlist", message: "Tạo playlist từ trang chi tiết phim.") }
        else { List(viewModel.playlists) { item in VStack(alignment: .leading, spacing: 5) { Text(item.name).font(.headline); Text("\(item.movieCount) phim • \(item.isPublic ? "Công khai" : "Riêng tư")").font(.caption).foregroundStyle(.secondary); if !item.description.isEmpty { Text(item.description).font(.subheadline) } } }.refreshable { await viewModel.load() } }
    }.navigationTitle("Playlist").task { await viewModel.load() } } }
}
