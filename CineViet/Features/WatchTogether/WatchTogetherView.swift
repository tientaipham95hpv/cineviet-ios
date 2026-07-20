import SwiftUI

struct WatchTogetherLaunch: Identifiable { let id = UUID(); let movie: Movie; let server: EpisodeServer; let episode: EpisodeItem }

struct WatchTogetherView: View {
    @ObservedObject var service: WatchTogetherService
    let watchHistoryService: WatchHistoryServicing
    @State private var rooms: [WatchRoom] = []
    @State private var loading = true
    @State private var error: String?
    @State private var code = ""
    @State private var busy = false
    @State private var launch: WatchTogetherLaunch?

    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 18) {
                Text("Xem chung").font(.largeTitle.bold())
                HStack { TextField("Nhập mã phòng", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityLabel("Mã phòng"); Button { Task { await join(code) } } label: { Label("Vào", systemImage: "rectangle.portrait.and.arrow.right") }.buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black).frame(minHeight: 44).disabled(busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                HStack { Text("Phòng public").font(.title2.bold()); Spacer(); Button { Task { await load() } } label: { Label("Làm mới", systemImage: "arrow.clockwise") }.frame(minHeight: 44) }
                if loading { ProgressView("Đang tải phòng…").frame(maxWidth: .infinity).padding(.vertical, 30) }
                else if let error {
                    WatchTogetherPlaceholder(title: "Không tải được phòng", message: error, systemImage: "wifi.exclamationmark", actionTitle: "Thử lại") { Task { await load() } }
                } else if rooms.isEmpty {
                    WatchTogetherPlaceholder(title: "Chưa có phòng public", message: "Bạn có thể nhập mã phòng riêng tư ở trên.", systemImage: "person.2.slash")
                }
                else { LazyVStack(spacing: 10) { ForEach(rooms) { room in Button { Task { await join(room.code) } } label: { HStack { Image(systemName: "person.2.fill").frame(width: 44, height: 44).background(CineVietTheme.accent.opacity(0.15), in: Circle()); VStack(alignment: .leading) { Text(room.movieTitle).font(.headline); Text("\(room.code) • \(room.memberCount)/\(room.maxMembers) người").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.padding(12).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain).accessibilityHint("Vào phòng xem chung") } } }
            }.frame(maxWidth: 760, alignment: .leading).padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 100) }
            .background(CineVietTheme.background).refreshable { await load() }
        }.task { await load() }
        .fullScreenCover(item: $launch) { value in PlayerView(movie: value.movie, server: value.server, episode: value.episode, watchHistoryService: watchHistoryService, watchTogetherService: service).interactiveDismissDisabled() }
        .alert("Xem chung", isPresented: Binding(get: { error != nil && !loading && rooms.count > 0 }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        .overlay { if busy { ZStack { Color.black.opacity(0.3).ignoresSafeArea(); ProgressView("Đang vào phòng…").padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } } }
    }
    private func load() async { loading = true; error = nil; do { rooms = try await service.publicRooms() } catch { self.error = error.localizedDescription }; loading = false }
    private func join(_ raw: String) async {
        busy = true
        defer { busy = false }
        do {
            let state = try await service.join(raw)
            guard let state, !state.videoUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await service.leave()
                throw WatchTogetherError.message("Phòng \(raw.uppercased()) chưa có video để phát")
            }
            let movie = Movie(watchTogetherTitle: state.movieTitle, code: state.code, videoURL: state.videoUrl)
            guard let server = movie.episodes.first, let episode = server.items.first else {
                await service.leave()
                throw WatchTogetherError.message("Phòng \(state.code) chưa có video để phát")
            }
            launch = .init(movie: movie, server: server, episode: episode)
        } catch { self.error = error.localizedDescription }
    }
}

struct WatchTogetherPlaceholder: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(title: String, message: String, systemImage: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 38, weight: .semibold)).foregroundStyle(CineVietTheme.accent)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .accessibilityElement(children: .combine)
    }
}
