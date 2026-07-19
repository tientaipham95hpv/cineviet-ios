import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(HomeData)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var selectedMovie: Movie?
    private var sectionErrors: [String] = []

    let movieService: MovieServicing
    private let watchHistoryService: WatchHistoryServicing

    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing) {
        self.movieService = movieService
        self.watchHistoryService = watchHistoryService
    }

    func load(force: Bool = false) async {
        if !force, case .loaded = state { return }
        state = .loading
        sectionErrors = []

        async let featured = fetch(MovieListQuery(limit: 10, featured: "1"))
        async let latest = fetch(MovieListQuery(limit: 22))
        async let cinema = fetch(MovieListQuery(limit: 18, cinema: "1"))
        async let series = fetch(MovieListQuery(limit: 18, type: "series"))
        async let single = fetch(MovieListQuery(limit: 18, type: "movie"))
        async let anime = fetch(MovieListQuery(limit: 18, type: "anime"))
        async let tvShows = fetch(MovieListQuery(limit: 18, type: "tvshows"))
        async let bilingual = fetch(MovieListQuery(limit: 18, bilingual: "1"))
        async let history = watchHistoryService.continueWatching(limit: 12)

        let historyItems = await history
        let continueWatching = await withTaskGroup(of: (Int, ContinueWatchingMovie)?.self) { group in
            for (position, item) in historyItems.prefix(12).enumerated() {
                group.addTask {
                    guard let movie = try? await self.movieService.detail(idOrSlug: String(item.movieId)) else { return nil }
                    return (position, ContinueWatchingMovie(movie: movie, history: item))
                }
            }
            var items: [(Int, ContinueWatchingMovie)] = []
            for await item in group { if let item { items.append(item) } }
            return items.sorted { $0.0 < $1.0 }.map(\.1)
        }

        var data = await HomeData(
            featured: featured,
            latest: latest,
            cinema: cinema,
            series: series,
            single: single,
            anime: anime,
            tvShows: tvShows,
            bilingual: bilingual
        )
        data.continueWatching = continueWatching
        if data.isEmpty {
            let detail = sectionErrors.first ?? "API không trả về phim."
            state = .failed("Không tải được trang chủ: \(detail)")
        } else {
            state = .loaded(data)
        }
    }

    func retry() async {
        await load(force: true)
    }

    private func fetch(_ query: MovieListQuery) async -> [Movie] {
        do {
            return try await movieService.list(query).movies
        } catch {
            // Flutter loads Home sections independently and keeps successful
            // sections visible when one request fails.
            sectionErrors.append(error.localizedDescription)
            return []
        }
    }
}
