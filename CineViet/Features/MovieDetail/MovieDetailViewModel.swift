import Combine
import Foundation

@MainActor
final class MovieDetailViewModel: ObservableObject {
    enum State {
        case loading
        case loaded(Movie)
        case failed(String)
    }

    @Published private(set) var state: State
    @Published var selectedServerIndex = 0
    @Published var selectedEpisode: EpisodeItem?
    @Published private(set) var isFavorite = false
    @Published private(set) var playlists: [CinePlaylist] = []
    @Published private(set) var libraryError: String?

    private let movieService: MovieServicing
    private let routeKey: String
    private let initialMovie: Movie
    private let libraryService: LibraryServicing

    init(movie: Movie, movieService: MovieServicing, libraryService: LibraryServicing) {
        initialMovie = movie
        routeKey = movie.routeKey
        self.movieService = movieService
        self.libraryService = libraryService
        state = .loading
    }

    var displayedMovie: Movie {
        if case .loaded(let movie) = state { return movie }
        return initialMovie
    }

    var selectedServer: EpisodeServer? {
        let servers = displayedMovie.episodes
        guard servers.indices.contains(selectedServerIndex) else { return nil }
        return servers[selectedServerIndex]
    }

    var firstPlayableSource: (server: EpisodeServer, episode: EpisodeItem)? {
        for server in displayedMovie.episodes {
            if let episode = server.items.first(where: { PlayerViewModel.directMediaURL(for: $0) != nil }) {
                return (server, episode)
            }
        }
        return nil
    }

    var hasEmbedOnlySource: Bool {
        displayedMovie.episodes.flatMap(\.items).contains { !$0.linkEmbed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func load() async {
        state = .loading
        do {
            let movie = try await movieService.detail(idOrSlug: routeKey)
            selectedServerIndex = movie.episodes.firstIndex(where: { server in
                server.items.contains { PlayerViewModel.directMediaURL(for: $0) != nil }
            }) ?? 0
            state = .loaded(movie)
            async let ids = libraryService.favoriteIDs()
            async let lists = try? libraryService.playlists()
            isFavorite = await ids.contains(movie.id)
            playlists = await lists ?? []
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func toggleFavorite() async {
        let next = !isFavorite
        do {
            try await libraryService.toggleFavorite(movieID: displayedMovie.id, add: next)
            isFavorite = next
        } catch { libraryError = error.localizedDescription }
    }

    func addToPlaylist(_ playlist: CinePlaylist) async {
        do { try await libraryService.add(movieID: displayedMovie.id, to: playlist.id) }
        catch { libraryError = error.localizedDescription }
    }

    func createPlaylist(name: String) async {
        do {
            let playlist = try await libraryService.createPlaylist(name: name, description: "", isPublic: false)
            playlists.append(playlist)
            try await libraryService.add(movieID: displayedMovie.id, to: playlist.id)
        } catch { libraryError = error.localizedDescription }
    }

    func retry() async { await load() }

    func selectServer(_ index: Int) {
        guard displayedMovie.episodes.indices.contains(index) else { return }
        selectedServerIndex = index
    }
}
