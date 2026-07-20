import SwiftUI

enum CatalogPreset: Hashable, Identifiable {
    case all, series, single, cinema, animation, bilingual

    var id: String { title }
    var title: String {
        switch self {
        case .all: "Khám phá"
        case .series: "Phim bộ"
        case .single: "Phim lẻ"
        case .cinema: "Phim chiếu rạp"
        case .animation: "Hoạt hình"
        case .bilingual: "Phim song ngữ"
        }
    }

    func apply(to query: inout MovieListQuery) {
        switch self {
        case .all: break
        case .series: query.type = "series"
        case .single: query.type = "single"
        case .cinema: query.cinema = "1"
        case .animation: query.type = "hoathinh"
        case .bilingual: query.bilingual = "1"
        }
    }
}

@MainActor final class CatalogViewModel: ObservableObject {
    @Published var text = ""
    @Published var type = ""
    @Published var genre = ""
    @Published var country = ""
    @Published var year = ""
    @Published var sort = "created_at"
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = true
    @Published private(set) var errorMessage: String?

    let movieService: MovieServicing
    let preset: CatalogPreset
    private var page = 1
    private var searchTask: Task<Void, Never>?
    private var requestGeneration = 0

    init(movieService: MovieServicing, preset: CatalogPreset = .all) {
        self.movieService = movieService
        self.preset = preset
    }

    deinit { searchTask?.cancel() }

    func reload(debounce: Bool = false) {
        searchTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        searchTask = Task { [weak self] in
            if debounce { try? await Task.sleep(nanoseconds: 400_000_000) }
            guard !Task.isCancelled, let self else { return }
            await self.fetch(reset: true, generation: generation)
        }
    }

    func loadMoreIfNeeded(_ movie: Movie) {
        guard movie.id == movies.last?.id, canLoadMore, !isLoading, !isLoadingMore else { return }
        let generation = requestGeneration
        Task { [weak self] in await self?.fetch(reset: false, generation: generation) }
    }

    private func fetch(reset: Bool, generation: Int) async {
        if reset { isLoading = true; page = 1; errorMessage = nil } else { isLoadingMore = true }
        defer {
            if generation == requestGeneration { isLoading = false; isLoadingMore = false }
        }
        do {
            var query = MovieListQuery(page: page, limit: 30)
            query.search = text.trimmingCharacters(in: .whitespacesAndNewlines)
            query.type = type
            query.genre = genre
            query.country = country
            query.year = year
            query.sort = sort
            preset.apply(to: &query)
            let rows = try await movieService.list(query).movies
            guard !Task.isCancelled, generation == requestGeneration else { return }
            if reset {
                movies = rows
            } else {
                movies.append(contentsOf: rows.filter { row in !movies.contains(where: { $0.id == row.id }) })
            }
            canLoadMore = rows.count == query.limit
            if canLoadMore { page += 1 }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private enum RecentSearchStore {
    private static let key = "cineviet.ios.recent-searches"
    static var items: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    @discardableResult static func add(_ raw: String) -> [String] {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return items }
        var values = items.filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        values.insert(value, at: 0)
        values = Array(values.prefix(8))
        UserDefaults.standard.set(values, forKey: key)
        return values
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

struct SearchView: View {
    let movieService: MovieServicing
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing

    var body: some View {
        CatalogView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService, preset: .all, showsSearch: true)
    }
}

struct CatalogView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: CatalogViewModel
    @State private var selectedMovie: Movie?
    @State private var showingFilters = false
    @State private var recentSearches = RecentSearchStore.items
    @FocusState private var searchFocused: Bool

    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing
    let showsSearch: Bool

    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing, preset: CatalogPreset, showsSearch: Bool = false) {
        _viewModel = StateObject(wrappedValue: CatalogViewModel(movieService: movieService, preset: preset))
        self.watchHistoryService = watchHistoryService
        self.libraryService = libraryService
        self.showsSearch = showsSearch
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header
                        if showsSearch { searchField; suggestions }
                        content(width: proxy.size.width)
                        Color.clear.frame(height: 92)
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { viewModel.reload() }
                .background(background)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { if viewModel.movies.isEmpty { viewModel.reload() } }
            .sheet(isPresented: $showingFilters) {
                CatalogFilterSheet(type: $viewModel.type, genre: $viewModel.genre, country: $viewModel.country, year: $viewModel.year, sort: $viewModel.sort) { viewModel.reload() }
            }
            .navigationDestination(isPresented: Binding(get: { selectedMovie != nil }, set: { if !$0 { selectedMovie = nil } })) {
                if let movie = selectedMovie {
                    MovieDetailView(movie: movie, movieService: viewModel.movieService, watchHistoryService: watchHistoryService, libraryService: libraryService)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.preset.title).font(.largeTitle.bold()).foregroundStyle(.primary)
                Text(showsSearch ? "Tìm bộ phim dành cho bạn" : "Chọn phim và bắt đầu thưởng thức")
                    .font(.subheadline).foregroundStyle(CineVietTheme.textMuted)
            }
            Spacer(minLength: 8)
            Button { showingFilters = true } label: {
                Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(filtersActive ? .black : .primary)
                    .frame(width: 48, height: 48)
                    .background(filtersActive ? CineVietTheme.accent : CineVietTheme.panel, in: Circle())
                    .overlay { Circle().stroke(CineVietTheme.border, lineWidth: 1) }
            }
            .accessibilityLabel(filtersActive ? "Bộ lọc đang được áp dụng" : "Mở bộ lọc")
        }
        .padding(.horizontal, 16)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(searchFocused ? CineVietTheme.accent : CineVietTheme.textMuted)
            TextField("Tên phim, diễn viên…", text: $viewModel.text)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { commitSearch() }
                .onChange(of: viewModel.text) { _ in viewModel.reload(debounce: true) }
            if !viewModel.text.isEmpty {
                Button { viewModel.text = ""; viewModel.reload() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(CineVietTheme.textMuted).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Xóa từ khóa")
            }
        }
        .padding(.leading, 16).padding(.trailing, 4)
        .frame(minHeight: 56)
        .background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(searchFocused ? CineVietTheme.accent : CineVietTheme.border, lineWidth: searchFocused ? 1.5 : 1) }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var suggestions: some View {
        if showsSearch, viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tìm kiếm gần đây").font(.headline)
                    Spacer()
                    Button("Xóa") { RecentSearchStore.clear(); recentSearches = [] }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(CineVietTheme.accent).frame(minHeight: 44)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentSearches, id: \.self) { item in
                            Button { viewModel.text = item; commitSearch() } label: {
                                Label(item, systemImage: "clock.arrow.circlepath")
                                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .background(CineVietTheme.panel, in: Capsule())
                                    .overlay { Capsule().stroke(CineVietTheme.border, lineWidth: 1) }
                            }
                            .foregroundStyle(.primary).accessibilityLabel("Tìm lại \(item)")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private func content(width: CGFloat) -> some View {
        if viewModel.isLoading && viewModel.movies.isEmpty {
            skeletonGrid(width: width)
        } else if let error = viewModel.errorMessage, viewModel.movies.isEmpty {
            stateCard(icon: "wifi.exclamationmark", title: "Không tải được phim", message: error, action: "Thử lại") { viewModel.reload() }
        } else if viewModel.movies.isEmpty {
            let query = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
            stateCard(icon: "magnifyingglass", title: query.isEmpty ? "Chưa có phim để khám phá" : "Không tìm thấy phim", message: query.isEmpty ? "Hãy thử tải lại danh sách phim." : "Không có kết quả phù hợp với “\(query)”. Hãy thử từ khóa hoặc bộ lọc khác.", action: filtersActive ? "Xóa bộ lọc" : nil) {
                viewModel.type = ""; viewModel.genre = ""; viewModel.country = ""; viewModel.year = ""; viewModel.sort = "created_at"; viewModel.reload()
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Phim mới cập nhật" : "Kết quả tìm kiếm").font(.title3.bold())
                    Spacer()
                    Text("\(viewModel.movies.count)+ phim").font(.caption.weight(.semibold)).foregroundStyle(CineVietTheme.textMuted)
                }
                .padding(.horizontal, 16)
                LazyVGrid(columns: columns(for: width), spacing: 20) {
                    ForEach(viewModel.movies) { movie in
                        Button { select(movie) } label: { SearchMovieCard(movie: movie) }
                            .buttonStyle(.plain)
                            .onAppear { viewModel.loadMoreIfNeeded(movie) }
                    }
                    if viewModel.isLoadingMore {
                        ProgressView().tint(CineVietTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func skeletonGrid(width: CGFloat) -> some View {
        LazyVGrid(columns: columns(for: width), spacing: 20) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: 15).fill(CineVietTheme.panel).aspectRatio(0.69, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4).fill(CineVietTheme.panel).frame(height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(CineVietTheme.panel).frame(width: 70, height: 10)
                }
                .opacity(0.75)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityLabel("Đang tải phim")
    }

    private func stateCard(icon: String, title: String, message: String, action: String?, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 38, weight: .semibold)).foregroundStyle(CineVietTheme.accent)
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.center)
            if let action { Button(action, action: perform).buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black).controlSize(.large) }
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 36).cineGlass(cornerRadius: 22)
        .padding(.horizontal, 16)
    }

    private var background: some View {
        LinearGradient(colors: [CineVietTheme.background, CineVietTheme.secondaryBackground.opacity(0.75), CineVietTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let minimum: CGFloat = width >= 700 ? 160 : 136
        return [GridItem(.adaptive(minimum: minimum, maximum: 210), spacing: width >= 700 ? 20 : 14, alignment: .top)]
    }

    private func commitSearch() {
        recentSearches = RecentSearchStore.add(viewModel.text)
        searchFocused = false
        viewModel.reload()
    }

    private func select(_ movie: Movie) {
        let query = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { recentSearches = RecentSearchStore.add(query) }
        if reduceMotion { selectedMovie = movie } else { withAnimation(.easeOut(duration: 0.18)) { selectedMovie = movie } }
    }

    private var filtersActive: Bool {
        !viewModel.type.isEmpty || !viewModel.genre.isEmpty || !viewModel.country.isEmpty || !viewModel.year.isEmpty || viewModel.sort != "created_at"
    }
}

private struct SearchMovieCard: View {
    let movie: Movie

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: movie.posterURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .empty: placeholder.overlay { ProgressView().tint(CineVietTheme.accent) }
                    default: placeholder
                    }
                }
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                if let episode = movie.episodeCurrent.nonEmpty {
                    Text(episode).font(.caption2.bold()).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.7), in: Capsule()).foregroundStyle(.white).padding(8)
                }
            }
            .aspectRatio(0.69, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(CineVietTheme.border.opacity(0.8), lineWidth: 0.8) }
            .overlay(alignment: .topTrailing) {
                if let quality = movie.quality.nonEmpty {
                    Text(quality.uppercased()).font(.system(size: 9, weight: .black)).foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 5).background(CineVietTheme.accent, in: RoundedRectangle(cornerRadius: 6)).padding(7)
                }
            }
            Text(movie.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).frame(minHeight: 36, alignment: .topLeading)
            HStack(spacing: 7) {
                if let year = movie.releaseYear, year > 1800 { Text(String(year)) }
                if let rating = movie.rating, rating > 0 { Label(String(format: "%.1f", rating), systemImage: "star.fill").foregroundStyle(CineVietTheme.accent) }
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(CineVietTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(movie.title)
        .accessibilityHint("Mở chi tiết phim")
        .accessibilityAddTraits(.isButton)
    }

    private var placeholder: some View {
        ZStack { CineVietTheme.panel; Image(systemName: "film.fill").font(.title2).foregroundStyle(CineVietTheme.textMuted.opacity(0.6)) }
    }
}

private struct CatalogFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var type: String
    @Binding var genre: String
    @Binding var country: String
    @Binding var year: String
    @Binding var sort: String
    let apply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Loại phim") {
                    Picker("Loại phim", selection: $type) { Text("Tất cả").tag(""); Text("Phim bộ").tag("series"); Text("Phim lẻ").tag("single"); Text("Hoạt hình").tag("hoathinh") }
                }
                Section("Bộ lọc") {
                    TextField("Thể loại", text: $genre)
                    TextField("Quốc gia", text: $country)
                    TextField("Năm phát hành", text: $year).keyboardType(.numberPad)
                }
                Section("Sắp xếp") {
                    Picker("Sắp xếp", selection: $sort) {
                        Text("Mới cập nhật").tag("created_at")
                        Text("Năm phát hành").tag("release_year")
                        Text("Đánh giá").tag("rating")
                        Text("Lượt xem").tag("view_count")
                        Text("Tên phim").tag("title")
                    }
                }
                Section { Button("Xóa bộ lọc", role: .destructive) { type = ""; genre = ""; country = ""; year = ""; sort = "created_at" } }
            }
            .navigationTitle("Lọc phim").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Áp dụng") { apply(); dismiss() } }
            }
        }
    }
}

struct ContentMessage: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(CineVietTheme.accent)
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding()
    }
}
