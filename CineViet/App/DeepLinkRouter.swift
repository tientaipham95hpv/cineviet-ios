import Foundation

@MainActor
final class DeepLinkRouter: ObservableObject {
    enum Destination: Equatable {
        case movie(String)
        case watchRoom(String)
    }

    @Published private(set) var destination: Destination?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let destination = Self.destination(from: url) else { return false }
        self.destination = destination
        return true
    }

    @discardableResult
    func handle(userInfo: [AnyHashable: Any]) -> Bool {
        for key in ["url", "link", "deep_link", "deeplink"] {
            if let raw = userInfo[key] as? String, let url = URL(string: raw), handle(url) { return true }
        }
        if let slug = (userInfo["movie_slug"] ?? userInfo["movieSlug"] ?? userInfo["slug"]) as? String, !slug.isEmpty {
            destination = .movie(slug); return true
        }
        if let code = (userInfo["room_code"] ?? userInfo["roomCode"] ?? userInfo["code"]) as? String, !code.isEmpty {
            destination = .watchRoom(code.uppercased()); return true
        }
        return false
    }

    func consume() -> Destination? {
        defer { destination = nil }
        return destination
    }

    private static func destination(from url: URL) -> Destination? {
        guard ["http", "https", "cineviet"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        if url.scheme != "cineviet", url.host?.lowercased() != AppEnvironment.siteBaseURL.host?.lowercased() { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let marker = parts.firstIndex(where: { ["phim", "movie", "movies"].contains($0.lowercased()) }), parts.indices.contains(marker + 1) {
            return .movie(parts[marker + 1].removingPercentEncoding ?? parts[marker + 1])
        }
        if let marker = parts.firstIndex(where: { ["xem-chung", "watch-together", "watch-party", "room"].contains($0.lowercased()) }), parts.indices.contains(marker + 1) {
            return .watchRoom(parts[marker + 1].uppercased())
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        if let code = query?.first(where: { ["room", "code", "roomCode"].contains($0.name) })?.value, !code.isEmpty { return .watchRoom(code.uppercased()) }
        return nil
    }
}
