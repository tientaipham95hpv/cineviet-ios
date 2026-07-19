import SwiftUI

struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: selectedMovieBinding) {
                    if let movie = viewModel.selectedMovie {
                        MovieDetailView(movie: movie, movieService: viewModel.movieService, watchHistoryService: watchHistoryService, libraryService: libraryService)
                    }
                }
                .navigationDestination(isPresented: catalogBinding) {
                    if let preset = catalogPreset {
                        CatalogView(movieService: viewModel.movieService, watchHistoryService: watchHistoryService, libraryService: libraryService, preset: preset)
                    }
                }
        }
        .tint(CineVietTheme.accent)
        .task { await viewModel.load() }
    }

    private var selectedMovieBinding: Binding<Bool> {
        Binding(get: { viewModel.selectedMovie != nil }, set: { if !$0 { viewModel.selectedMovie = nil } })
    }

    private var catalogBinding: Binding<Bool> {
        Binding(get: { catalogPreset != nil }, set: { if !$0 { catalogPreset = nil } })
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            HomeLoadingView()
        case .failed(let message):
            HomeFailureView(message: message) { Task { await viewModel.retry() } }
        case .loaded(let data):
            if data.isEmpty {
                HomeEmptyView { Task { await viewModel.retry() } }
            } else {
                loadedHome(data)
            }
        }
    }

    private func loadedHome(_ data: HomeData) -> some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    homeHeader
                    if !data.featured.isEmpty { featuredHero(Array(data.featured.prefix(7)), width: geometry.size.width) }
                    categoryChips
                    if !data.continueWatching.isEmpty { continueWatchingSection(data.continueWatching) }
                    ForEach(data.sections) { movieSection($0) }
                }
                .frame(width: geometry.size.width, alignment: .leading)
                .padding(.bottom, 110)
            }
            .refreshable { await viewModel.retry() }
        }
    }

    private var homeHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CineVietTheme.accent)
                Image(systemName: "play.fill").font(.system(size: 17, weight: .black)).foregroundStyle(.black)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("CINEVIET").font(.system(size: 20, weight: .black, design: .rounded)).tracking(1.1)
                Text("Phim hay mỗi ngày").font(.caption).foregroundStyle(CineVietTheme.textMuted)
            }
            Spacer(minLength: 8)
            Menu {
                Button(role: .destructive, action: logout) { Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right") }
            } label: {
                Image(systemName: "person.crop.circle").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle()).overlay { Circle().stroke(.white.opacity(0.13)) }
            }
            .accessibilityLabel("Tài khoản")
        }
        .padding(.horizontal, 18).padding(.top, 8)
    }

    private func featuredHero(_ movies: [Movie], width: CGFloat) -> some View {
        let safeIndex = min(featuredIndex, max(0, movies.count - 1))
        return VStack(spacing: 12) {
            TabView(selection: $featuredIndex) {
                ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                    heroSlide(movie, width: width).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: width, height: min(510, max(430, width * 1.2)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: featuredIndex)
            if movies.count > 1 {
                HStack(spacing: 6) {
                    ForEach(movies.indices, id: \.self) { index in
                        Capsule().fill(index == safeIndex ? CineVietTheme.accent : .white.opacity(0.24))
                            .frame(width: index == safeIndex ? 20 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    private func heroSlide(_ movie: Movie, width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: movie.backdropURL ?? movie.posterURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { CineVietTheme.panel }
            }
            .frame(width: max(0, width - 24), height: min(510, max(430, width * 1.2)))
            .clipped()
            LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.2), CineVietTheme.background.opacity(0.98)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 12) {
                Label("PHIM NỔI BẬT", systemImage: "flame.fill")
                    .font(.system(size: 11, weight: .black, design: .rounded)).tracking(1.1).foregroundStyle(CineVietTheme.accent)
                Text(movie.title).font(.system(size: 30, weight: .black, design: .rounded)).lineLimit(2)
                featuredMetadata(movie)
                if let description = movie.description.nonEmpty {
                    Text(description).font(.system(size: 14, weight: .regular, design: .rounded)).foregroundStyle(.white.opacity(0.78)).lineLimit(3).lineSpacing(3)
                }
                HStack(spacing: 10) {
                    Button { viewModel.selectedMovie = movie } label: { Label("Xem ngay", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(HeroCTAStyle(primary: true))
                    Button { viewModel.selectedMovie = movie } label: { Label("Chi tiết", systemImage: "info.circle").frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(HeroCTAStyle(primary: false))
                }
            }
            .padding(20)
        }
        .frame(width: max(0, width - 24))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.12)) }
        .shadow(color: .black.opacity(0.42), radius: 24, y: 14)
        .padding(.horizontal, 12)
    }

    private func featuredMetadata(_ movie: Movie) -> some View {
        HStack(spacing: 7) {
            if let rating = movie.rating, rating > 0 { metadataPill(String(format: "★ %.1f", rating), accent: true) }
            if let quality = movie.quality.nonEmpty { metadataPill(quality, accent: true) }
            if let year = movie.releaseYear, year > 1800 { metadataPill(String(year)) }
            if let type = movie.type.nonEmpty { metadataPill(type == "series" ? "Phim bộ" : "Phim lẻ") }
        }
    }

    private func metadataPill(_ value: String, accent: Bool = false) -> some View {
        Text(value).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(accent ? CineVietTheme.accent : .white.opacity(0.9))
            .padding(.horizontal, 8).padding(.vertical, 5).background(.black.opacity(0.5), in: Capsule())
            .overlay { Capsule().stroke(accent ? CineVietTheme.accent.opacity(0.5) : .white.opacity(0.16)) }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                categoryChip("Khám phá", icon: "sparkles", preset: .all)
                categoryChip("Phim bộ", icon: "rectangle.stack", preset: .series)
                categoryChip("Phim lẻ", icon: "film", preset: .single)
                categoryChip("Chiếu rạp", icon: "ticket", preset: .cinema)
                categoryChip("Hoạt hình", icon: "face.smiling", preset: .animation)
                categoryChip("Song ngữ", icon: "captions.bubble", preset: .bilingual)
            }
            .padding(.horizontal, 18)
        }
    }

    private func categoryChip(_ title: String, icon: String, preset: CatalogPreset) -> some View {
        Button { catalogPreset = preset } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14).frame(minHeight: 44).background(CineVietTheme.panel.opacity(0.92), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.1)) }
        }.buttonStyle(.plain)
    }

    private func continueWatchingSection(_ items: [ContinueWatchingMovie]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader("Xem tiếp", subtitle: "Tiếp tục từ nơi bạn dừng lại", preset: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 13) {
                    ForEach(items) { item in
                        Button { viewModel.selectedMovie = item.movie } label: { ContinueWatchingCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 18)
            }
        }
    }

    private func movieSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader(section.title, subtitle: subtitle(for: section.kind), preset: preset(for: section.title))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 13) {
                    ForEach(section.movies) { movie in
                        Button { viewModel.selectedMovie = movie } label: { MovieCardView(movie: movie) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 18)
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String, preset: CatalogPreset?) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 21, weight: .bold, design: .rounded))
                Text(subtitle).font(.caption).foregroundStyle(CineVietTheme.textMuted)
            }
            Spacer()
            if let preset {
                Button { catalogPreset = preset } label: { Label("Tất cả", systemImage: "chevron.right").labelStyle(.titleAndIcon).font(.caption.bold()).frame(minHeight: 44) }
                    .foregroundStyle(CineVietTheme.accent)
            }
        }.padding(.horizontal, 18)
    }

    private func subtitle(for kind: HomeSection.Kind) -> String {
        switch kind {
        case .latest: return "Những tựa phim vừa lên sóng"
        case .cinema: return "Không khí màn ảnh rộng"
        case .series: return "Câu chuyện dài tập cuốn hút"
        case .single: return "Trọn vẹn trong một lần xem"
        case .anime: return "Thế giới hoạt hình đặc sắc"
        case .tvShows: return "Chương trình chọn lọc"
        case .bilingual: return "Xem phim và luyện ngôn ngữ"
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
            RadialGradient(colors: [CineVietTheme.accentDeep.opacity(0.18), .clear], center: .topTrailing, startRadius: 1, endRadius: 430).ignoresSafeArea()
        }
    }
}

private struct HeroCTAStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(primary ? .black : .white)
            .background(primary ? CineVietTheme.accent : .white.opacity(configuration.isPressed ? 0.22 : 0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { if !primary { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18)) } }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct ContinueWatchingCard: View {
    let item: ContinueWatchingMovie
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: item.movie.backdropURL ?? item.movie.posterURL) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { CineVietTheme.panel }
                }
                .frame(width: 238, height: 134).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                VStack(spacing: 0) {
                    Spacer()
                    HStack { Image(systemName: "play.fill").font(.caption.bold()); Text(item.history.episodeName.nonEmpty ?? "Xem tiếp").font(.caption.bold()).lineLimit(1); Spacer() }.padding(10)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Color.white.opacity(0.18)
                            CineVietTheme.accent.frame(width: proxy.size.width * item.progress)
                        }
                    }.frame(height: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.12)) }
            Text(item.movie.title).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1).frame(width: 238, alignment: .leading)
            Text("Đã xem \(Int((item.progress * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(CineVietTheme.textMuted)
        }
        .foregroundStyle(.white).accessibilityElement(children: .combine)
        .accessibilityLabel("Xem tiếp \(item.movie.title), đã xem \(Int((item.progress * 100).rounded())) phần trăm")
    }
}

private struct HomeLoadingView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                HStack { SkeletonBlock(width: 180, height: 42); Spacer(); SkeletonBlock(width: 44, height: 44, radius: 22) }.padding(.horizontal, 18)
                SkeletonBlock(height: 460, radius: 28).padding(.horizontal, 12)
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 13) {
                        SkeletonBlock(width: 170, height: 24)
                        HStack(spacing: 13) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(width: 142, height: 260, radius: 15) } }
                    }.padding(.leading, 18)
                }
            }.padding(.top, 8).padding(.bottom, 100)
        }.background(CineVietTheme.background.ignoresSafeArea()).accessibilityLabel("Đang tải trang chủ")
    }
}

private struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = 12
    var body: some View { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(CineVietTheme.panel).frame(width: width, height: height).overlay { RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.025)) }.redacted(reason: .placeholder) }
}

private struct HomeFailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 44, weight: .semibold)).foregroundStyle(CineVietTheme.accent)
            Text("Không tải được trang chủ").font(.title2.bold())
            Text(message).font(.subheadline).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.center)
            Button(action: retry) { Label("Thử lại", systemImage: "arrow.clockwise").frame(minWidth: 140, minHeight: 48) }.buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white).background(CineVietTheme.background.ignoresSafeArea())
    }
}

private struct HomeEmptyView: View {
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack").font(.system(size: 44)).foregroundStyle(CineVietTheme.accent)
            Text("Chưa có phim để hiển thị").font(.title3.bold())
            Button("Tải lại", action: retry).frame(minHeight: 44).foregroundStyle(CineVietTheme.accent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.white).background(CineVietTheme.background.ignoresSafeArea())
    }
}
