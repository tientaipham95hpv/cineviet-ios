import Foundation

enum NetworkError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case unauthorized
    case decoding(String)
    case transport(String)
    case missingToken
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL không hợp lệ."
        case .invalidResponse: return "Phản hồi máy chủ không hợp lệ."
        case .httpStatus(let status): return "Máy chủ trả về lỗi HTTP \(status)."
        case .unauthorized: return "Phiên đăng nhập đã hết hạn."
        case .decoding(let message): return "Không đọc được dữ liệu: \(message)"
        case .transport(let message): return message
        case .missingToken: return "Chưa có phiên đăng nhập."
        case .serverMessage(let message): return message
        }
    }
}
