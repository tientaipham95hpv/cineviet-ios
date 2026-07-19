import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    let logout: () -> Void
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing
    @State private var featuredIndex = 0
    @State private var catalogPreset: CatalogPreset?

    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, libraryService: LibraryServicing, logout: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(movieService: movieService, watchHistoryService: watchHistoryService))
        self.watchHistoryService = watchHistoryService
        self.libraryService = libraryService
        self.logout = logout
    }

    var body: some View {
        NavigationStack {
            content
                .background(homeBackground)
                .navigationTitle("CineViet")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: logout) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        .accessibilityLabel("Đăng xuất")
                    }
                }
                .navigationDestination(
                    isPresented: Binding(
                        get: { viewModel.selectedMovie != nil },
                        set: { isPresented in
                            if !isPresented { viewModel.selectedMovie = nil }
                        }
                    )
                ) {
                    if let movie = viewModel.selectedMovie {
                        MovieDetailView(movie: movie, movieService: viewModel.movieService, watchHistoryService: watchHistoryService, libraryService: libraryService)
                    }
                }
                .navigationDestination(item: $catalogPreset) { preset in
                    CatalogView(movieService: viewModel.movieService, watchHistoryService: watchHistoryService, libraryService: libraryService, preset: preset)
                }
        }
        .tint(CineVietTheme.accent)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Đang tải phim…")
                .tint(CineVietTheme.accent)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(CineVietTheme.accent)
                Text("Không tải được trang chủ")
                    .font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                Button("Thử lại") { Task { await viewModel.retry() } }
                    .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let data):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    homeHeader
                    categoryChips
                    if !data.featured.isEmpty {
                        featuredCarousel(Array(data.featured.prefix(7)))
                    }
                    ForEach(data.sections) { section in
                        movieSection(section)
                    }
                }
                .padding(.bottom, 32)
            }
            .refreshable { await viewModel.retry() }
        }
    }

    private var homeHeader: some View {
        HStack(spacing: 12) {
            ZStack { RoundedRectangle(cornerRadius: 13).fill(CineVietTheme.accent); Text("CV").font(.system(size: 17, weight: .black)).foregroundStyle(.black) }.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) { Text("CINEVIET").font(.headline.bold()).tracking(1.4); Text("Kho phim của người Việt").font(.caption).foregroundStyle(CineVietTheme.textMuted) }
            Spacer()
            Image(systemName: "bell").font(.headline).frame(width: 42, height: 42).cineGlass(cornerRadius: 15)
        }.padding(.horizontal, 18).padding(.top, 8)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 9) {
            categoryChip("Tất cả", preset: .all); categoryChip("Phim bộ", preset: .series); categoryChip("Phim lẻ", preset: .single); categoryChip("Chiếu rạp", preset: .cinema); categoryChip("Hoạt hình", preset: .animation); categoryChip("Song ngữ", preset: .bilingual)
        }.padding(.horizontal, 18) }
    }

    private func categoryChip(_ title: String, preset: CatalogPreset) -> some View {
        Button { catalogPreset = preset } label: { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(CineVietTheme.textMuted).padding(.horizontal, 15).padding(.vertical, 9).background(CineVietTheme.panel, in: Capsule()).overlay { Capsule().stroke(CineVietTheme.border) } }
    }

    private func featuredCarousel(_ movies: [Movie]) -> some View {
        let index = min(featuredIndex, max(movies.count - 1, 0))
        let movie = movies[index]
        return VStack(spacing: 17) {
            HStack { Text("PHIM NỔI BẬT").font(.caption.bold()).tracking(1.5).foregroundStyle(CineVietTheme.accent); Spacer(); Text("\(index + 1)/\(movies.count)").font(.caption).foregroundStyle(CineVietTheme.textMuted) }.padding(.horizontal, 20)
            TabView(selection: $featuredIndex) {
                ForEach(Array(movies.enumerated()), id: \.element.id) { position, item in
                    AsyncImage(url: item.posterURL) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() } else { CineVietTheme.panel }
                    }
                    .frame(width: 220, height: 320).clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 25).stroke(position == index ? CineVietTheme.accent.opacity(0.9) : .white.opacity(0.22), lineWidth: position == index ? 2 : 1) }
                    .shadow(color: position == index ? CineVietTheme.accent.opacity(0.2) : .black.opacity(0.4), radius: 20, y: 10)
                    .tag(position).padding(.horizontal, 58)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 326)

            VStack(spacing: 10) {
                Text(movie.title).font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2)
                if !movie.titleEn.isEmpty { Text(movie.titleEn).font(.subheadline).foregroundStyle(CineVietTheme.textMuted).lineLimit(1) }
                HStack(spacing: 8) {
                    Button { viewModel.selectedMovie = movie } label: { Label("Xem phim", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black)
                    Button { viewModel.selectedMovie = movie } label: { Label("Thông tin", systemImage: "info.circle").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.bordered).tint(.white)
                }.padding(.horizontal, 32)
                featuredMetadata(movie)
                if !movie.description.isEmpty { Text(movie.description).font(.subheadline).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 24) }
            }
        }
        .padding(.top, 8)
    }

    private func featuredMetadata(_ movie: Movie) -> some View {
        HStack(spacing: 7) {
            if let rating = movie.rating { chip(String(format: "IMDb %.1f", rating), accent: true) }
            if !movie.quality.isEmpty { chip(movie.quality, accent: true) }
            if let year = movie.releaseYear { chip(String(year)) }
            if !movie.type.isEmpty { chip(movie.type == "series" ? "Phim bộ" : "Phim lẻ") }
        }
    }

    private func chip(_ value: String, accent: Bool = false) -> some View {
        Text(value).font(.caption2.bold()).foregroundStyle(accent ? CineVietTheme.accent : .white)
            .padding(.horizontal, 7).padding(.vertical, 5).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(accent ? CineVietTheme.accent.opacity(0.8) : .white.opacity(0.28)) }
    }

    private func movieSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { GlassSectionHeader(title: section.title); Spacer(); Button("Xem tất cả") { catalogPreset = preset(for: section.title) }.font(.caption.bold()).foregroundStyle(CineVietTheme.accent).padding(.trailing, 18) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(section.movies) { movie in
                        MovieCardView(movie: movie)
                            .onTapGesture { viewModel.selectedMovie = movie }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func preset(for title: String) -> CatalogPreset {
        let value = title.lowercased()
        if value.contains("phim bộ") { return .series }
        if value.contains("phim lẻ") { return .single }
        if value.contains("hoạt hình") { return .animation }
        if value.contains("chiếu rạp") { return .cinema }
        if value.contains("song ngữ") { return .bilingual }
        return .all
    }

    private var homeBackground: some View {
        ZStack {
            CineVietTheme.background.ignoresSafeArea()
            RadialGradient(colors: [CineVietTheme.accent.opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 430).ignoresSafeArea()
            RadialGradient(colors: [CineVietTheme.accentDeep.opacity(0.11), .clear], center: .bottomLeading, startRadius: 10, endRadius: 500).ignoresSafeArea()
        }
    }
}
