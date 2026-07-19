import Foundation
import Security

struct TokenPair: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
}

protocol TokenStore {
    func load() throws -> TokenPair?
    func save(_ tokens: TokenPair) throws
    func clear() throws
}

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): return "Keychain error: \(status)"
        case .invalidData: return "Keychain data is invalid."
        }
    }
}

final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(
        service: String = "live.cineviet.ios",
        account: String = "auth.tokens"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> TokenPair? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw KeychainError.invalidData }
        do { return try JSONDecoder().decode(TokenPair.self, from: data) }
        catch { throw KeychainError.invalidData }
    }

    func save(_ tokens: TokenPair) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemAdd(
            baseQuery.merging([kSecValueData as String: data]) { _, new in new } as CFDictionary,
            nil
        )
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
