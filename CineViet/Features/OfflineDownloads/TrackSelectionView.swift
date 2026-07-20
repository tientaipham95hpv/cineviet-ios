import SwiftUI

struct TrackSelection: Identifiable {
    let id = UUID()
    let server: EpisodeServer
    let episode: EpisodeItem
    var audioKeys: Set<String>
    var subtitleKeys: Set<String>
}

struct TrackSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State var selection: TrackSelection
    let onConfirm: (TrackSelection) -> Void

    private var audio: [EpisodeAudioSource] { selection.episode.audioSources.filter { URL(string: $0.url)?.scheme?.hasPrefix("http") == true } }
    private var subtitles: [EpisodeSubtitleTrack] { selection.episode.subtitles.filter { URL(string: $0.url)?.scheme?.hasPrefix("http") == true } }

    var body: some View {
        NavigationStack {
            Form {
                if !audio.isEmpty {
                    Section("Audio tải về") {
                        ForEach(audio) { track in toggleRow(track.label, selected: selection.audioKeys.contains(track.key)) {
                            toggle(track.key, in: &selection.audioKeys)
                        } }
                    } footer: { Text("Server song ngữ có thể tải nhiều bản âm thanh. Bỏ chọn track không cần để tiết kiệm dung lượng.") }
                }
                if !subtitles.isEmpty {
                    Section("Phụ đề tải về") {
                        ForEach(subtitles) { track in toggleRow(track.label, selected: selection.subtitleKeys.contains(track.lang)) {
                            toggle(track.lang, in: &selection.subtitleKeys)
                        } }
                    }
                }
                Section { Label("Video chính luôn được tải. Audio và phụ đề đã chọn được lưu hoàn toàn trên thiết bị.", systemImage: "iphone.and.arrow.forward") }
            }
            .navigationTitle("Chọn nội dung tải")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Tải xuống") { onConfirm(selection) }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggleRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(label).foregroundStyle(.primary); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary) } }
        .accessibilityValue(selected ? "Đã chọn" : "Chưa chọn")
    }
    private func toggle(_ key: String, in values: inout Set<String>) { if values.contains(key) { values.remove(key) } else { values.insert(key) } }
}
