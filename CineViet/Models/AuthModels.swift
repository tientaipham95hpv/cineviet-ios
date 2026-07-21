import Foundation

struct AuthResponse: Decodable {
    let accessToken: String?
    let token: String?
    let refreshToken: String?
    let user: User?

    func tokens(fallbackRefreshToken: String? = nil) throws -> TokenPair {
        guard let access = (accessToken ?? token)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !access.isEmpty else { throw NetworkError.serverMessage("Không nhận được token") }
        return TokenPair(accessToken: access, refreshToken: refreshToken ?? fallbackRefreshToken)
    }
}

struct CurrentUserResponse: Decodable {
    let user: User

    init(from decoder: Decoder) throws {
        if let envelope = try? UserEnvelope(from: decoder) {
            user = envelope.user
        } else {
            user = try User(from: decoder)
        }
    }

    private struct UserEnvelope: Decodable {
        let user: User
    }
}

struct RefreshTokenRequest: Encodable { let refreshToken: String }

struct LoginRequest: Encodable {
    let email: String
    let password: String
    let mobileKey: String
}

struct GoogleLoginRequest: Encodable {
    let idToken: String
    let remember: Bool
}

struct ProfileUpdateRequest: Encodable {
    let name: String
}

struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
}

struct MembershipSummary: Decodable, Equatable {
    let entitlement: Entitlement?

    struct Entitlement: Decodable, Equatable {
        let active: Bool
        let remainingDays: Int?
        let expiresAt: String?
        let source: String?
    }
}

/// Flutter intentionally keeps `/auth/me` as a dynamic map. This model only
/// types fields that Flutter reads and preserves all remaining JSON fields.
struct User: Decodable, Identifiable, Equatable {
    let id: String
    let email: String?
    let name: String?
    let username: String?
    let avatar: String?
    let role: String?
    let userRole: String?
    let type: String?
    let isVip: Bool
    let status: String?
    let vipExpiresAt: String?
    let raw: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let raw = try [String: JSONValue](from: decoder)
        self.raw = raw
        let identifier = raw["id"]?.stringValue.nonEmpty
            ?? raw["_id"]?.stringValue.nonEmpty
            ?? raw["email"]?.stringValue.nonEmpty
        guard let identifier else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "User id is missing"))
        }
        id = identifier
        email = raw["email"]?.stringValue.nonEmpty
        name = raw["name"]?.stringValue.nonEmpty
        username = raw["username"]?.stringValue.nonEmpty
        avatar = UserPayload.avatarURL(from: raw)
        role = raw["role"]?.stringValue.nonEmpty
        userRole = raw["user_role"]?.stringValue.nonEmpty
        type = raw["type"]?.stringValue.nonEmpty
        status = raw["status"]?.stringValue.nonEmpty
        vipExpiresAt = raw["vip_expires_at"]?.stringValue.nonEmpty ?? raw["vipExpiresAt"]?.stringValue.nonEmpty
        isVip = raw["is_vip"] == .bool(true) || raw["is_vip"]?.intValue == 1 || status?.lowercased() == "vip"
    }
}

enum UserPayload {
    static func avatarURL(from raw: [String: JSONValue]) -> String? {
        let maps = [raw, raw["user"]?.object, raw["profile"]?.object, raw["author"]?.object, raw["account"]?.object].compactMap { $0 }
        for map in maps {
            for key in ["avatar", "user_avatar", "userAvatar", "avatarUrl", "avatar_url", "photo_url", "photoUrl", "picture", "image"] {
                if let value = map[key]?.stringValue.nonEmpty { return value }
            }
        }
        return nil
    }
}
