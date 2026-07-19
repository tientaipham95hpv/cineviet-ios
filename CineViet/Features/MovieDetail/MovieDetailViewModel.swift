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

    private let movieService: MovieServicing
    private let routeKey: String
    private let initialMovie: Movie

    init(movie: Movie, movieService: MovieServicing) {
        initialMovie = movie
        routeKey = movie.routeKey
        self.movieService = movieService
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

    func load() async {
        state = .loading
        do {
            let movie = try await movieService.detail(idOrSlug: routeKey)
            selectedServerIndex = 0
            state = .loaded(movie)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async { await load() }

    func selectServer(_ index: Int) {
        guard displayedMovie.episodes.indices.contains(index) else { return }
        selectedServerIndex = index
    }
}
