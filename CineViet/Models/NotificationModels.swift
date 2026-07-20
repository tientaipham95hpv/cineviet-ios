import Foundation

struct UserNotification: Decodable, Identifiable, Equatable {
    let id: String
    let type: String?
    let title: String
    let description: String?
    let link: String?
    let at: String?
    let sender: String?

    var externalURL: URL? {
        guard let link, let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}

struct UserNotificationsResponse: Decodable, Equatable {
    let notifications: [UserNotification]
    let unreadCount: Int
}

struct NotificationSettings: Codable, Equatable {
    var phimMoi: Bool
    var tapMoi: Bool
    var watchParty: Bool
    var uuDai: Bool

    enum CodingKeys: String, CodingKey {
        case phimMoi = "phim_moi"
        case tapMoi = "tap_moi"
        case watchParty = "watch_party"
        case uuDai = "uu_dai"
    }
}

struct NotificationSettingUpdate: Encodable {
    let phimMoi: Bool?
    let tapMoi: Bool?
    let watchParty: Bool?
    let uuDai: Bool?

    enum CodingKeys: String, CodingKey {
        case phimMoi = "phim_moi"
        case tapMoi = "tap_moi"
        case watchParty = "watch_party"
        case uuDai = "uu_dai"
    }
}
