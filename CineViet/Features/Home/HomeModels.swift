import Foundation

struct HomeSection: Identifiable, Equatable {
    enum Kind: String {
        case continueWatching, latest, cinema, series, single, anime, tvShows, bilingual
    }

    let kind: Kind
    let title: String
    let movies: [Movie]
    var id: Kind { kind }
}

struct HomeData: Equatable {
    let featured: [Movie]
    let latest: [Movie]
    let cinema: [Movie]
    let series: [Movie]
    let single: [Movie]
    let anime: [Movie]
    let tvShows: [Movie]
    let bilingual: [Movie]
    var continueWatching: [Movie] = []

    var sections: [HomeSection] {
        [
            HomeSection(kind: .continueWatching, title: "Tiếp tục xem", movies: continueWatching),
            HomeSection(kind: .latest, title: "Mới cập nhật", movies: latest),
            HomeSection(kind: .cinema, title: "Phim chiếu rạp", movies: cinema),
            HomeSection(kind: .series, title: "Phim bộ", movies: series),
            HomeSection(kind: .single, title: "Phim lẻ", movies: single),
            HomeSection(kind: .anime, title: "Hoạt hình", movies: anime),
            HomeSection(kind: .tvShows, title: "TV Shows", movies: tvShows),
            HomeSection(kind: .bilingual, title: "Song ngữ", movies: bilingual),
        ].filter { !$0.movies.isEmpty }
    }

    var isEmpty: Bool {
        featured.isEmpty && sections.isEmpty
    }
}
