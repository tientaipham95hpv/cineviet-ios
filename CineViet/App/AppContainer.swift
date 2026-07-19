import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let tokenStore: TokenStore
    let settings: AppSettings
    let apiClient: APIClient
    let authenticationService: AuthenticationServicing
    let movieService: MovieServicing
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing

    init(
        tokenStore: TokenStore,
        settings: AppSettings,
        apiClient: APIClient,
        authenticationService: AuthenticationServicing,
        movieService: MovieServicing,
        watchHistoryService: WatchHistoryServicing,
        libraryService: LibraryServicing
    ) {
        self.tokenStore = tokenStore
        self.settings = settings
        self.apiClient = apiClient
        self.authenticationService = authenticationService
        self.movieService = movieService
        self.watchHistoryService = watchHistoryService
        self.libraryService = libraryService
    }

    static let live: AppContainer = {
        let tokenStore = KeychainTokenStore()
        let settings = AppSettings()
        let apiClient = APIClient(tokenStore: tokenStore)
        return AppContainer(
            tokenStore: tokenStore,
            settings: settings,
            apiClient: apiClient,
            authenticationService: AuthenticationService(apiClient: apiClient, tokenStore: tokenStore),
            movieService: MovieService(apiClient: apiClient),
            watchHistoryService: WatchHistoryService(apiClient: apiClient),
            libraryService: LibraryService(apiClient: apiClient)
        )
    }()
}
