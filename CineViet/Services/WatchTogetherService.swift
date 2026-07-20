import Foundation
import SocketIO

struct WatchTogetherCreateResult { let code: String; let room: WatchTogetherState? }

enum WatchTogetherError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

@MainActor
final class WatchTogetherService: ObservableObject {
    @Published private(set) var state: WatchTogetherState?
    @Published private(set) var messages: [WatchTogetherMessage] = []
    @Published private(set) var connected = false
    @Published private(set) var isHost = false
    @Published private(set) var roomClosed = false
    private let apiClient: APIClient
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private(set) var code: String?
    var socketID: String? { socket?.sid }

    init(apiClient: APIClient) { self.apiClient = apiClient }

    func publicRooms() async throws -> [WatchRoom] {
        struct Envelope: Decodable { let rooms: [WatchRoom] }
        let result: Envelope = try await apiClient.send(APIRequest(method: .get, path: "/watch-party/rooms"))
        return result.rooms.filter { !$0.code.isEmpty }
    }

    func create(movie: Movie, videoURL: String, hostName: String = "CineViet", maxMembers: Int = 8, isPublic: Bool = true) async throws -> WatchTogetherCreateResult {
        let url = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { throw WatchTogetherError.message("Phim này chưa có link phát để tạo phòng") }
        let payload: [String: Any] = ["hostName": hostName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Chủ phòng", "videoUrl": url, "movieTitle": movie.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Watch Party", "maxMembers": maxMembers, "isPublic": isPublic]
        let reply = try await connectAndAck(event: "create-room", payload: payload, timeout: 15)
        let error = reply["error"] as? String ?? ""
        guard error.isEmpty else { throw WatchTogetherError.message(error) }
        guard let code = reply["code"] as? String, !code.isEmpty else { throw WatchTogetherError.message("Không tạo được phòng") }
        let room = decode(WatchTogetherState.self, from: reply["room"])
        retain(code: code, host: true, room: room)
        return .init(code: code, room: room)
    }

    func join(_ rawCode: String, userName: String = "CineViet") async throws -> WatchTogetherState? {
        let roomCode = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !roomCode.isEmpty else { throw WatchTogetherError.message("Nhập mã phòng") }
        let reply = try await connectAndAck(event: "join-room", payload: ["code": roomCode, "userName": userName], timeout: 12)
        let error = reply["error"] as? String ?? ""
        guard error.isEmpty else { throw WatchTogetherError.message(error) }
        let room = decode(WatchTogetherState.self, from: reply["room"])
        retain(code: room?.code.nonEmpty ?? roomCode, host: room?.hostSocketId == socket?.sid, room: room)
        return room
    }

    func sendMessage(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, connected else { return }
        socket?.emitWithAck("chat-message", ["text": text]).timingOut(after: 12) { _ in }
    }

    func sync(currentTime: Double, playing: Bool) { guard connected else { return }; socket?.emit("sync-state", ["currentTime": currentTime, "playing": playing]) }

    func leave(forceDelete: Bool = false) async {
        guard let socket else { return }
        let shouldClose = forceDelete || isHost
        if shouldClose { socket.emit("close-room", ["code": code as Any]); _ = await withCheckedContinuation { continuation in socket.emitWithAck("close-room", ["code": code as Any]).timingOut(after: 0.9) { _ in continuation.resume() } } }
        else { socket.emit("leave-room") }
        clear(disconnect: true)
    }

    private func connectAndAck(event: String, payload: [String: Any], timeout: Double) async throws -> [String: Any] {
        if socket != nil { await leave(forceDelete: isHost) }
        let manager = SocketManager(socketURL: AppEnvironment.siteBaseURL, config: [.path("/socket.io"), .compress, .reconnects(true)])
        self.manager = manager
        let socket = manager.defaultSocket; self.socket = socket
        return try await withCheckedThrowingContinuation { continuation in
            var completed = false
            func finish(_ result: Result<[String: Any], Error>) { guard !completed else { return }; completed = true; continuation.resume(with: result) }
            socket.on(clientEvent: .connect) { _, _ in socket.emitWithAck(event, payload).timingOut(after: timeout) { data in
                guard let first = data.first as? [String: Any] else { finish(.failure(WatchTogetherError.message("Kết nối quá thời gian"))); return }
                finish(.success(first))
            } }
            socket.on(clientEvent: .error) { _, _ in finish(.failure(WatchTogetherError.message("Không kết nối được Xem chung"))) }
            socket.connect(timeoutAfter: timeout) { finish(.failure(WatchTogetherError.message("Kết nối quá thời gian"))) }
        }
    }

    private func retain(code: String, host: Bool, room: WatchTogetherState?) {
        self.code = code.uppercased(); isHost = host; connected = true; roomClosed = false; state = room; messages = room?.messages ?? []
        socket?.removeAllHandlers()
        socket?.on("room-state") { [weak self] data, _ in guard let self, let raw = data.first, let value = self.decode(WatchTogetherState.self, from: raw) else { return }; self.state = value; self.messages = value.messages; NotificationCenter.default.post(name: .watchTogetherRoomState, object: self, userInfo: ["from": (raw as? [String: Any])?["_from"] as Any]) }
        socket?.on("chat-message") { [weak self] data, _ in guard let self, let message = self.decode(WatchTogetherMessage.self, from: data.first), !self.messages.contains(where: { $0.id == message.id }) else { return }; self.messages.append(message) }
        socket?.on("room-closed") { [weak self] _, _ in guard let self else { return }; self.clear(disconnect: true, closed: true); NotificationCenter.default.post(name: .watchTogetherRoomClosed, object: self) }
        socket?.on(clientEvent: .connect) { [weak self] _, _ in self?.connected = true }
        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in self?.connected = false }
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: Any?) -> T? { guard let object, JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }; return try? JSONDecoder.cineViet.decode(type, from: data) }
    private func clear(disconnect: Bool, closed: Bool = false) { if disconnect { socket?.disconnect() }; socket = nil; manager = nil; connected = false; roomClosed = closed; isHost = false; code = nil; state = nil; messages = [] }
}

extension Notification.Name {
    static let watchTogetherRoomState = Notification.Name("cineviet.watchTogether.roomState")
    static let watchTogetherRoomClosed = Notification.Name("cineviet.watchTogether.roomClosed")
}
