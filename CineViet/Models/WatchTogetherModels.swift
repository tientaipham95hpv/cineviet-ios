import Foundation

struct WatchRoom: Decodable, Identifiable, Equatable {
    let code: String
    let movieTitle: String
    let videoUrl: String
    let memberCount: Int
    let maxMembers: Int
    var id: String { code }

    init(from decoder: Decoder) throws {
        let raw = try [String: JSONValue](from: decoder)
        code = raw["code"]?.stringValue ?? ""
        movieTitle = raw["movieTitle"]?.stringValue.nonEmpty ?? "Phòng xem chung"
        videoUrl = raw["videoUrl"]?.stringValue ?? ""
        memberCount = raw["memberCount"]?.intValue ?? 0
        maxMembers = raw["maxMembers"]?.intValue ?? 8
    }
}

struct WatchTogetherMember: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    init(from decoder: Decoder) throws {
        let raw = try [String: JSONValue](from: decoder)
        id = raw["id"]?.stringValue ?? ""
        name = raw["name"]?.stringValue.nonEmpty ?? "Thành viên"
    }
}

struct WatchTogetherMessage: Decodable, Identifiable, Equatable {
    let id: String
    let type: String
    let payload: String
    let userName: String?
    var isSystem: Bool { type == "system" }
    init(from decoder: Decoder) throws {
        let raw = try [String: JSONValue](from: decoder)
        id = raw["id"]?.stringValue.nonEmpty ?? String(Int(Date().timeIntervalSince1970 * 1000))
        type = raw["type"]?.stringValue.nonEmpty ?? "text"
        payload = raw["payload"]?.stringValue ?? ""
        userName = raw["userName"]?.stringValue.nonEmpty
    }
}

struct WatchTogetherState: Decodable, Equatable {
    let code: String
    let movieTitle: String
    let videoUrl: String
    let hostSocketId: String
    let members: [WatchTogetherMember]
    let currentTime: Double
    let playing: Bool
    let messages: [WatchTogetherMessage]
    init(from decoder: Decoder) throws {
        let raw = try [String: JSONValue](from: decoder)
        code = raw["code"]?.stringValue ?? ""
        movieTitle = raw["movieTitle"]?.stringValue.nonEmpty ?? "Phòng xem chung"
        videoUrl = raw["videoUrl"]?.stringValue ?? ""
        hostSocketId = raw["hostSocketId"]?.stringValue ?? ""
        members = raw["members"]?.decodedArray(WatchTogetherMember.self) ?? []
        currentTime = raw["currentTime"]?.doubleValue ?? 0
        playing = raw["playing"] == .bool(true)
        messages = raw["messages"]?.decodedArray(WatchTogetherMessage.self) ?? []
    }
}

private extension JSONValue {
    func decodedArray<T: Decodable>(_ type: T.Type) -> [T]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder.cineViet.decode([T].self, from: data)
    }
}
