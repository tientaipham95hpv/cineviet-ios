import SwiftUI

enum CatalogPreset: Hashable, Identifiable {
    case all, series, single, cinema, animation, bilingual
    var id: String { title }
    var title: String { switch self { case .all: "Tất cả phim"; case .series: "Phim bộ"; case .single: "Phim lẻ"; case .cinema: "Phim chiếu rạp"; case .animation: "Hoạt hình"; case .bilingual: "Phim song ngữ" } }
    func apply(to query: inout MovieListQuery) { switch self { case .all: break; case .series: query.type = "series"; case .single: query.type = "single"; case .cinema: query.cinema = "1"; case .animation: query.type = "hoathinh"; case .bilingual: query.bilingual = "1" } }
}

@MainActor final class CatalogViewModel: ObservableObject {
    @Published var text = ""; @Published var type = ""; @Published var genre = ""; @Published var country = ""; @Published var year = ""; @Published var sort = "created_at"
    @Published private(set) var movies: [Movie] = []; @Published private(set) var isLoading = false; @Published private(set) var isLoadingMore = false; @Published private(set) var canLoadMore = true; @Published private(set) var errorMessage: String?
    let movieService: MovieServicing; let preset: CatalogPreset
    private var page = 1; private var searchTask: Task<Void, Never>?
    init(movieService: MovieServicing, preset: CatalogPreset = .all) { self.movieService = movieService; self.preset = preset }
    func reload(debounce: Bool = false) { searchTask?.cancel(); searchTask = Task { if debounce { try? await Task.sleep(nanoseconds: 350_000_000) }; guard !Task.isCancelled else { return }; await fetch(reset: true) } }
    func loadMoreIfNeeded(_ movie: Movie) { guard movie.id == movies.last?.id, canLoadMore, !isLoading, !isLoadingMore else { return }; Task { await fetch(reset: false) } }
    private func fetch(reset: Bool) async {
        if reset { isLoading = true; page = 1 } else { isLoadingMore = true }
        defer { isLoading = false; isLoadingMore = false }
        do { var query = MovieListQuery(page: page, limit: 30); query.search = text.trimmingCharacters(in: .whitespacesAndNewlines); query.type = type; query.genre = genre; query.country = country; query.year = year; query.sort = sort; preset.apply(to: &query); let rows = try await movieService.list(query).movies; if reset { movies = rows } else { movies.append(contentsOf: rows.filter { row in !movies.contains(where: { $0.id == row.id }) }) }; canLoadMore = rows.count == query.limit; if canLoadMore { page += 1 }; errorMessage = nil } catch { errorMessage = error.localizedDescription }
    }
}

struct SearchView: View {
    let movieService: MovieServicing; let watchHistoryService: WatchHistoryServicing; let libraryService: LibraryServicing
    var body: some View { CatalogView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService, preset: .all, showsSearch: true) }
}

struct CatalogView: View {
    @StateObject private var viewModel: CatalogViewModel; @State private var selectedMovie: Movie?; @State private var showingFilters = false
    let watchHistoryService: WatchHistoryServicing; let libraryService: LibraryServicing; let showsSearch: Bool
    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing, preset: CatalogPreset, showsSearch: Bool = false) { _viewModel = StateObject(wrappedValue: CatalogViewModel(movieService: movieService, preset: preset)); self.watchHistoryService = watchHistoryService; self.libraryService = libraryService; self.showsSearch = showsSearch }
    var body: some View { NavigationStack { Group {
        if viewModel.isLoading && viewModel.movies.isEmpty { ProgressView("Đang tải phim…") }
        else if let error = viewModel.errorMessage, viewModel.movies.isEmpty { ContentMessage(icon: "wifi.exclamationmark", title: "Không tải được phim", message: error) }
        else if viewModel.movies.isEmpty { ContentMessage(icon: "film.stack", title: "Không có kết quả", message: "Hãy thử thay đổi từ khóa hoặc bộ lọc.") }
        else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 18) { ForEach(viewModel.movies) { movie in MovieCardView(movie: movie).onTapGesture { selectedMovie = movie }.onAppear { viewModel.loadMoreIfNeeded(movie) } }; if viewModel.isLoadingMore { ProgressView().tint(CineVietTheme.accent).gridCellColumns(2).padding() } }.padding() }.refreshable { viewModel.reload() } }
    }.background(CineVietTheme.background.ignoresSafeArea()).navigationTitle(viewModel.preset.title).toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingFilters = true } label: { Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") } } }.searchable(text: $viewModel.text, prompt: "Tên phim…").onChange(of: viewModel.text) { _ in viewModel.reload(debounce: true) }.task { if viewModel.movies.isEmpty { viewModel.reload() } }.sheet(isPresented: $showingFilters) { CatalogFilterSheet(type: $viewModel.type, genre: $viewModel.genre, country: $viewModel.country, year: $viewModel.year, sort: $viewModel.sort) { viewModel.reload() } }.navigationDestination(isPresented: Binding(get: { selectedMovie != nil }, set: { if !$0 { selectedMovie = nil } })) { if let movie = selectedMovie { MovieDetailView(movie: movie, movieService: viewModel.movieService, watchHistoryService: watchHistoryService, libraryService: libraryService) } } } }
    private var filtersActive: Bool { !viewModel.type.isEmpty || !viewModel.genre.isEmpty || !viewModel.country.isEmpty || !viewModel.year.isEmpty || viewModel.sort != "created_at" }
}

private struct CatalogFilterSheet: View {
    @Environment(\.dismiss) private var dismiss; @Binding var type: String; @Binding var genre: String; @Binding var country: String; @Binding var year: String; @Binding var sort: String; let apply: () -> Void
    var body: some View { NavigationStack { Form { Section("Loại phim") { Picker("Loại phim", selection: $type) { Text("Tất cả").tag(""); Text("Phim bộ").tag("series"); Text("Phim lẻ").tag("single"); Text("Hoạt hình").tag("hoathinh") } }; Section("Bộ lọc") { TextField("Thể loại", text: $genre); TextField("Quốc gia", text: $country); TextField("Năm phát hành", text: $year).keyboardType(.numberPad) }; Section("Sắp xếp") { Picker("Sắp xếp", selection: $sort) { Text("Mới cập nhật").tag("created_at"); Text("Năm phát hành").tag("release_year"); Text("Đánh giá").tag("rating"); Text("Lượt xem").tag("views") } }; Section { Button("Xóa bộ lọc", role: .destructive) { type = ""; genre = ""; country = ""; year = ""; sort = "created_at" } } }.navigationTitle("Lọc phim").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Áp dụng") { apply(); dismiss() } } } } }
}

struct ContentMessage: View { let icon: String; let title: String; let message: String; var body: some View { VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 38)).foregroundStyle(CineVietTheme.accent); Text(title).font(.title3.bold()); Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding() } }
