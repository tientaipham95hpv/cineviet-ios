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

struct RegisterRequest: Encodable {
    let name: String
    let email: String
    let password: String
    let passwordConfirmation: String
    let mobileKey: String

    enum CodingKeys: String, CodingKey {
        case name, email, password
        case passwordConfirmation = "password_confirmation"
        case mobileKey = "mobile_key"
    }
}

struct ForgotPasswordRequest: Encodable { let email: String }
struct ResetPasswordRequest: Encodable {
    let token: String
    let code: String
    let password: String
}

struct GoogleLoginRequest: Encodable {
    let idToken: String
    let remember: Bool
}

struct ProfileUpdateRequest: Encodable {
    let name: String
    let avatar: String?
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
        isVip = UserPayload.isVIP(from: raw)
    }
}

enum UserPayload {
    static func avatarURL(from raw: [String: JSONValue]) -> String? {
        let maps = nestedMaps(from: raw)
        for map in maps {
            for key in ["avatar", "user_avatar", "userAvatar", "avatarUrl", "avatar_url", "photo_url", "photoUrl", "picture", "image"] {
                if let value = map[key]?.stringValue.nonEmpty { return absoluteImageURL(value) }
            }
        }
        return nil
    }

    static func isVIP(from raw: [String: JSONValue]) -> Bool {
        let maps = nestedMaps(from: raw)
        if maps.contains(where: { map in
            ["is_vip", "isVip", "vip", "vip_active", "vipActive", "is_premium", "premium"]
                .contains { map[$0]?.boolValue == true }
        }) { return true }
        return maps.contains { map in
            ["status", "membership", "membership_type", "plan", "role", "user_role", "type"]
                .contains { key in ["vip", "premium"].contains(map[key]?.stringValue.lowercased()) }
        }
    }

    static func absoluteImageURL(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.lowercased() != "null" else { return nil }
        if value.hasPrefix("//") { return "https:\(value)" }
        if let url = URL(string: value), url.scheme != nil { return value }
        return AppEnvironment.siteBaseURL.appendingPathComponent(value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
    }

    private static func nestedMaps(from root: [String: JSONValue]) -> [[String: JSONValue]] {
        var result: [[String: JSONValue]] = []
        func collect(_ map: [String: JSONValue], depth: Int) {
            result.append(map)
            guard depth < 3 else { return }
            for key in ["user", "author", "profile", "account", "data"] {
                if let child = map[key]?.object { collect(child, depth: depth + 1) }
            }
        }
        collect(root, depth: 0)
        return result
    }
}
