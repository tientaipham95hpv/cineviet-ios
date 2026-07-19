import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    let movieService: MovieServicing
    private var task: Task<Void, Never>?

    init(movieService: MovieServicing) { self.movieService = movieService }

    func search() {
        task?.cancel()
        let queryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else { movies = []; errorMessage = nil; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            isLoading = true; errorMessage = nil
            defer { isLoading = false }
            do {
                var query = MovieListQuery(); query.search = queryText; query.limit = 40
                movies = try await movieService.list(query).movies
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @State private var selectedMovie: Movie?
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing

    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(movieService: movieService))
        self.watchHistoryService = watchHistoryService
        self.libraryService = libraryService
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading { ProgressView("Đang tìm phim…") }
                else if let error = viewModel.errorMessage { ContentMessage(icon: "wifi.exclamationmark", title: "Không tìm được phim", message: error) }
                else if viewModel.movies.isEmpty { ContentMessage(icon: "magnifyingglass", title: "Tìm phim CineViet", message: "Nhập tên phim, diễn viên hoặc từ khóa.") }
                else {
                    ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 18) {
                        ForEach(viewModel.movies) { movie in MovieCardView(movie: movie).onTapGesture { selectedMovie = movie } }
                    }.padding() }
                }
            }
            .navigationTitle("Tìm kiếm")
            .searchable(text: $viewModel.text, prompt: "Tên phim…")
            .onChange(of: viewModel.text) { _ in viewModel.search() }
            .navigationDestination(isPresented: Binding(get: { selectedMovie != nil }, set: { if !$0 { selectedMovie = nil } })) {
                if let movie = selectedMovie { MovieDetailView(movie: movie, movieService: viewModel.movieService, watchHistoryService: watchHistoryService, libraryService: libraryService) }
            }
        }
    }
}

struct ContentMessage: View {
    let icon: String; let title: String; let message: String
    var body: some View { VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 38)).foregroundStyle(CineVietTheme.accent); Text(title).font(.title3.bold()); Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding() }
}
