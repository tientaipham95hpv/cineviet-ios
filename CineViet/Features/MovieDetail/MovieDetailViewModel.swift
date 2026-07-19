import Combine
import Foundation

@MainActor
final class MovieDetailViewModel: ObservableObject {
    enum State { case loading, loaded(Movie), failed(String) }

    @Published private(set) var state: State
    @Published var selectedServerIndex = 0
    @Published private(set) var isFavorite = false
    @Published private(set) var playlists: [CinePlaylist] = []
    @Published private(set) var comments: [MovieComment] = []
    @Published private(set) var ratingStats: RatingStats?
    @Published private(set) var isFavoriteBusy = false
    @Published private(set) var isSocialLoading = false
    @Published private(set) var isSubmitting = false
    @Published var message: String?

    private let movieService: MovieServicing
    private let routeKey: String
    private let initialMovie: Movie
    private let libraryService: LibraryServicing

    init(movie: Movie, movieService: MovieServicing, libraryService: LibraryServicing) {
        initialMovie = movie; routeKey = movie.routeKey
        self.movieService = movieService; self.libraryService = libraryService
        state = .loading
    }

    var displayedMovie: Movie { if case .loaded(let movie) = state { return movie }; return initialMovie }
    var selectedServer: EpisodeServer? {
        let servers = displayedMovie.episodes
        return servers.indices.contains(selectedServerIndex) ? servers[selectedServerIndex] : nil
    }
    var firstPlayableSource: (server: EpisodeServer, episode: EpisodeItem)? {
        for server in displayedMovie.episodes {
            if let episode = server.items.first(where: { PlayerViewModel.directMediaURL(for: $0) != nil }) { return (server, episode) }
        }
        return nil
    }

    func load() async {
        state = .loading
        do {
            let movie = try await movieService.detail(idOrSlug: routeKey)
            selectedServerIndex = movie.episodes.firstIndex { $0.items.contains { PlayerViewModel.directMediaURL(for: $0) != nil } } ?? 0
            state = .loaded(movie)
            async let ids = libraryService.favoriteIDs()
            async let lists = try? libraryService.playlists()
            isFavorite = await ids.contains(movie.id)
            playlists = await lists ?? []
            await refreshSocial()
        } catch { state = .failed(error.localizedDescription) }
    }

    func refreshSocial() async {
        isSocialLoading = true; defer { isSocialLoading = false }
        async let nextComments = try? libraryService.comments(movieID: displayedMovie.id)
        async let nextRating = try? libraryService.ratingStats(movieID: displayedMovie.id)
        comments = await nextComments ?? comments
        ratingStats = await nextRating ?? ratingStats
    }

    func toggleFavorite() async {
        guard !isFavoriteBusy else { return }
        isFavoriteBusy = true
        let previous = isFavorite; isFavorite.toggle()
        do { try await libraryService.toggleFavorite(movieID: displayedMovie.id, add: isFavorite); message = isFavorite ? "Đã thêm vào yêu thích" : "Đã bỏ khỏi yêu thích" }
        catch { isFavorite = previous; message = error.localizedDescription }
        isFavoriteBusy = false
    }

    func addToPlaylist(_ playlist: CinePlaylist) async {
        do { try await libraryService.add(movieID: displayedMovie.id, to: playlist.id); message = "Đã thêm vào \(playlist.name)" }
        catch { message = error.localizedDescription }
    }

    func createPlaylist(name: String) async {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !isSubmitting else { return }
        isSubmitting = true; defer { isSubmitting = false }
        do {
            let playlist = try await libraryService.createPlaylist(name: cleanName, description: "", isPublic: false)
            try await libraryService.add(movieID: displayedMovie.id, to: playlist.id)
            playlists.append(playlist)
            message = "Đã tạo playlist và thêm phim"
        } catch { message = error.localizedDescription }
    }

    func rate(_ value: Int) async {
        guard !isSubmitting else { return }; isSubmitting = true; defer { isSubmitting = false }
        do { ratingStats = try await libraryService.rate(movieID: displayedMovie.id, rating: value); message = "Đã chấm \(value)/10" }
        catch { message = error.localizedDescription }
    }

    func addComment(_ content: String, spoiler: Bool) async -> Bool {
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2, !isSubmitting else { return false }
        isSubmitting = true; defer { isSubmitting = false }
        do { let item = try await libraryService.addComment(movieID: displayedMovie.id, content: clean, isSpoiler: spoiler); comments.insert(item, at: 0); message = "Đã gửi bình luận"; return true }
        catch { message = error.localizedDescription; return false }
    }

    func retry() async { await load() }
    func selectServer(_ index: Int) { if displayedMovie.episodes.indices.contains(index) { selectedServerIndex = index } }
}
