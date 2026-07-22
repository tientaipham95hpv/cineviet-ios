import SwiftUI

struct AppUpdateInfo: Decodable {
    let updateAvailable: Bool?
    let latestVersion: String?
    let latestBuild: String?
    let version: String?
    let build: String?
    let url: String?
    let downloadUrl: String?
    let notes: String?
    let releaseNotes: String?
}

struct UpdateInfoView: View {
    let service: AuthenticationServicing
    @Environment(\.openURL) private var openURL
    @State private var info: AppUpdateInfo?
    @State private var loading = true
    @State private var error: String?

    private var localVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    private var localBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }

    var body: some View {
        Form {
            Section("Phiên bản hiện tại") { Text("\(localVersion) (\(localBuild))").font(.title2.bold()) }
            if loading { Section { ProgressView("Đang kiểm tra cập nhật…") } }
            else if let error { Section { Text(error).foregroundStyle(.secondary); Button("Thử lại") { Task { await load() } } } }
            else if let info {
                Section("Trạng thái") {
                    Label(info.updateAvailable == true ? "Có phiên bản mới" : "Bạn đang dùng phiên bản mới nhất", systemImage: info.updateAvailable == true ? "arrow.down.circle.fill" : "checkmark.seal.fill")
                    if let latest = latestLabel(info), !latest.isEmpty { Text("Phiên bản mới: \(latest)") }
                    if let notes = info.notes ?? info.releaseNotes, !notes.isEmpty { Text(notes).foregroundStyle(.secondary) }
                    if info.updateAvailable == true, let raw = info.url ?? info.downloadUrl, let url = absoluteURL(raw) {
                        Button { openURL(url) } label: { Label("Mở trang cập nhật", systemImage: "safari.fill") }
                    }
                }
            }
        }
        .navigationTitle("Cập nhật ứng dụng")
        .task { await load() }
    }

    private func load() async {
        loading = true; error = nil
        do { info = try await service.appUpdate(platform: "ios", build: localBuild, version: localVersion) }
        catch { self.error = "Chưa kiểm tra được cập nhật. Vui lòng thử lại sau." }
        loading = false
    }
    private func latestLabel(_ value: AppUpdateInfo) -> String? { [value.latestVersion ?? value.version, (value.latestBuild ?? value.build).map { "+\($0)" }].compactMap { $0 }.joined() }
    private func absoluteURL(_ raw: String) -> URL? { URL(string: raw, relativeTo: AppEnvironment.siteBaseURL)?.absoluteURL }
}
