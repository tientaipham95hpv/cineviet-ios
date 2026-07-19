import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    let logout: () -> Void
    let watchHistoryService: WatchHistoryServicing

    init(movieService: MovieServicing, watchHistoryService: WatchHistoryServicing, logout: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(movieService: movieService))
        self.watchHistoryService = watchHistoryService
        self.logout = logout
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color.black.ignoresSafeArea())
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
                        MovieDetailView(movie: movie, movieService: viewModel.movieService, watchHistoryService: watchHistoryService)
                    }
                }
        }
        .tint(.orange)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Đang tải phim…")
                .tint(.orange)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
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
                    if let hero = data.featured.first {
                        heroView(hero)
                            .onTapGesture { viewModel.selectedMovie = hero }
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

    private func heroView(_ movie: Movie) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: movie.backdropURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(height: 310)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(movie.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                if !movie.metadataLine.isEmpty {
                    Text(movie.metadataLine).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(height: 310)
        .contentShape(Rectangle())
    }

    private func movieSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .font(.title2.bold())
                .padding(.horizontal, 16)
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
}
