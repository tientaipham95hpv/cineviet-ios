import SwiftUI

struct WatchTogetherChatView: View {
    @ObservedObject var service: WatchTogetherService
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClose = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                roomHeader
                Divider()
                messageList
                Divider()
                composer
            }
            .background(CineVietTheme.background)
            .navigationTitle("Trò chuyện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { chatToolbar }
            .alert("Đóng phòng xem chung?", isPresented: $confirmClose) {
                Button("Huỷ", role: .cancel) {}
                Button("Đóng phòng", role: .destructive) {
                    Task { await service.leave(forceDelete: true); dismiss() }
                }
            } message: { Text("Mọi thành viên sẽ bị ngắt khỏi phòng.") }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var roomHeader: some View {
        HStack {
            Label(service.code ?? "", systemImage: "person.2.fill").font(.headline)
            Spacer()
            Text("\(service.state?.members.count ?? 0) người").foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder private var messageList: some View {
        if service.messages.isEmpty {
            WatchTogetherPlaceholder(
                title: "Chưa có tin nhắn",
                message: "Hãy bắt đầu trò chuyện với mọi người trong phòng.",
                systemImage: "message"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(service.messages.suffix(80).reversed())) { message in
                        WatchTogetherMessageRow(message: message)
                    }
                }
                .padding()
            }
        }
    }

    private var composer: some View {
        HStack {
            TextField("Nhập tin nhắn", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Tin nhắn")
            Button {
                service.sendMessage(text)
                text = ""
            } label: {
                Image(systemName: "paperplane.fill").frame(width: 44, height: 44)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !service.connected)
            .accessibilityLabel("Gửi tin nhắn")
        }
        .padding()
    }

    @ToolbarContentBuilder private var chatToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
        if service.isHost {
            ToolbarItem(placement: .confirmationAction) {
                Button("Đóng phòng", role: .destructive) { confirmClose = true }
            }
        }
    }
}

private struct WatchTogetherMessageRow: View {
    let message: WatchTogetherMessage

    var body: some View {
        VStack(alignment: message.isSystem ? .center : .leading, spacing: 3) {
            if !message.isSystem {
                Text(message.userName ?? "Thành viên")
                    .font(.caption.bold())
                    .foregroundStyle(CineVietTheme.accent)
            }
            Text(message.payload)
                .font(message.isSystem ? .body.italic() : .body)
                .foregroundStyle(message.isSystem ? .secondary : .primary)
        }
        .padding(10)
        .background(message.isSystem ? Color.clear : CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: message.isSystem ? .center : .leading)
        .id(message.id)
    }
}
