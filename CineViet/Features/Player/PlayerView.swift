import AVKit
import SwiftUI

enum PlayerPanel: String, Identifiable {
    case episodes, servers, audio, subtitles, subtitleSettings
    var id: String { rawValue }
}

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: PlayerViewModel
    @State private var controlsVisible = true
    @State private var controlsLocked = false
    @State private var activePanel: PlayerPanel?
    @State private var hideTask: Task<Void, Never>?
    @State private var pictureInPictureRequestID = 0
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem, watchHistoryService: WatchHistoryServicing) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(movie: movie, server: server, episode: episode, watchHistoryService: watchHistoryService))
    }

    var body: some View {
        ZStack {
            Color.black
            PictureInPicturePlayerView(player: viewModel.player, requestID: $pictureInPictureRequestID)
            tapSurface
            subtitleLayer
            if controlsLocked { lockedOverlay }
            else if controlsVisible { controlOverlay.transition(.opacity) }
            statusLayer
            if let count = viewModel.autoNextCountdown { autoNextCard(count) }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .hidesFloatingNavigation()
        .sheet(item: $activePanel) { panel in selectionPanel(panel).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .onAppear {
            NotificationCenter.default.post(name: .cineVietPlayerDidAppear, object: nil)
            OrientationManager.landscape()
            viewModel.start()
            revealControls()
        }
        .onDisappear {
            hideTask?.cancel()
            viewModel.stop()
            OrientationManager.portrait()
            NotificationCenter.default.post(name: .cineVietPlayerDidDisappear, object: nil)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background: viewModel.applicationDidEnterBackground()
            case .inactive: viewModel.flushProgress()
            case .active: viewModel.applicationWillEnterForeground()
            @unknown default: break
            }
        }
    }

    private var tapSurface: some View {
        Color.black.opacity(controlsVisible || controlsLocked ? 0.001 : 0.002)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !controlsLocked else { return }
                controlsVisible ? hideControls() : revealControls()
            }
    }

    private var controlOverlay: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.82), .clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                centerTransport
                Spacer(minLength: 8)
                bottomControls
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .safeAreaPadding(.horizontal, 8)
            .safeAreaPadding(.vertical, 4)
            lockButton(locked: false)
        }
        .contentShape(Rectangle())
        .onTapGesture { revealControls() }
    }

    private var topBar: some View {
        HStack(spacing: 13) {
            roundButton("chevron.left", label: "Quay lại") { exitPlayer() }
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.movie.title).font(.headline.weight(.bold)).lineLimit(1)
                Text("\(viewModel.currentServer.name) • \(viewModel.currentEpisode.name) • \(viewModel.activeSourceLabel)")
                    .font(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            }
            Spacer()
            Button { interact { pictureInPictureRequestID += 1 } } label: { Image(systemName: "pip.enter").playerCircle() }.accessibilityLabel("Hình trong hình")
            AirPlayButton().frame(width: 42, height: 42).background(.black.opacity(0.45), in: Circle())
        }
    }

    private var centerTransport: some View {
        HStack(spacing: 30) {
            transportButton("backward.end.fill", label: "Tập trước", disabled: viewModel.previousEpisode == nil) { viewModel.playPreviousEpisode() }
            transportButton("gobackward.10", label: "Lùi 10 giây") { viewModel.skip(-10) }
            Button { interact { viewModel.togglePlayback() } } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 31, weight: .black)).frame(width: 70, height: 70)
                    .foregroundStyle(.black).background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 16)
            }
            transportButton("goforward.10", label: "Tới 10 giây") { viewModel.skip(10) }
            transportButton("forward.end.fill", label: "Tập sau", disabled: viewModel.nextEpisode == nil) { viewModel.playNextEpisode() }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 11) {
            timeline
            HStack(spacing: 10) {
                featureButton("rectangle.stack.fill", "Tự động", active: viewModel.isAutoPlayEnabled) { viewModel.isAutoPlayEnabled.toggle() }
                featureButton("server.rack", "Server") { activePanel = .servers }
                featureButton("captions.bubble.fill", "Phụ đề", active: viewModel.selectedSubtitleLanguage != "off") { activePanel = .subtitles }
                featureButton("list.bullet.rectangle.fill", "Tập phim") { activePanel = .episodes }
                featureButton("waveform", "Âm thanh", active: viewModel.selectedAudioKey != nil) { activePanel = .audio }
                Spacer(minLength: 6)
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { isScrubbing ? scrubPosition : viewModel.playbackPosition }, set: { scrubPosition = $0 }), in: 0...max(viewModel.playbackDuration, 1), onEditingChanged: { editing in
                isScrubbing = editing
                if editing { scrubPosition = viewModel.playbackPosition; hideTask?.cancel() }
                else { viewModel.seek(to: scrubPosition); revealControls() }
            }).tint(CineVietTheme.accent)
                .accessibilityLabel("Tiến độ phát")
                .accessibilityValue("\(time(isScrubbing ? scrubPosition : viewModel.playbackPosition)) trên \(time(viewModel.playbackDuration))")
                .accessibilityHint("Vuốt lên hoặc xuống để tua phim")
            HStack {
                Text(time(isScrubbing ? scrubPosition : viewModel.playbackPosition))
                Spacer()
                Text("-\(time(max(0, viewModel.playbackDuration - (isScrubbing ? scrubPosition : viewModel.playbackPosition))))")
            }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.78))
        }
    }

    private var lockedOverlay: some View {
        ZStack {
            Color.black.opacity(0.001).contentShape(Rectangle())
            lockButton(locked: true)
        }
    }

    private func lockButton(locked: Bool) -> some View {
        HStack {
            Button { controlsLocked.toggle(); controlsVisible = true; controlsLocked ? hideTask?.cancel() : revealControls() } label: {
                VStack(spacing: 5) {
                    Image(systemName: locked ? "lock.open.fill" : "lock.fill").font(.headline)
                    Text(locked ? "Mở khóa" : "Khóa").font(.caption2.bold())
                }.frame(width: 58, height: 58).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
                    .overlay { RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.14)) }
            }.accessibilityLabel(locked ? "Mở khóa điều khiển" : "Khóa điều khiển")
            Spacer()
        }.padding(.leading, 17)
    }

    private var subtitleLayer: some View {
        GeometryReader { geometry in
            if !viewModel.overlaySubtitles.isEmpty {
                CollisionSafeSubtitleLayout(
                    captions: viewModel.overlaySubtitles,
                    styles: viewModel.subtitleStyles,
                    dual: viewModel.selectedSubtitleLanguage == "dual",
                    minimumBottomInset: controlsVisible ? 96 : max(geometry.safeAreaInsets.bottom + 10, 12)
                )
            }
        }.allowsHitTesting(false)
    }

    @ViewBuilder private var statusLayer: some View {
        if viewModel.isLoading || viewModel.isBuffering {
            VStack(spacing: 9) { ProgressView().controlSize(.large).tint(CineVietTheme.accent); Text(viewModel.isLoading ? "Đang mở nguồn phim…" : "Đang tải dữ liệu…").font(.caption.bold()) }
                .padding(16).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        }
        if let message = viewModel.errorMessage {
            PlayerErrorCard(message: message, retry: { viewModel.retry(); revealControls() }, sources: { activePanel = .servers }, exit: exitPlayer)
        } else if let notice = viewModel.playbackNotice {
            VStack { Spacer(); Text(notice).font(.subheadline.bold()).padding(.horizontal, 15).padding(.vertical, 11).background(.black.opacity(0.8), in: Capsule()).overlay { Capsule().stroke(CineVietTheme.accent.opacity(0.4)) }.padding(.bottom, controlsVisible ? 112 : 24) }
                .transition(.move(edge: .bottom).combined(with: .opacity)).allowsHitTesting(false)
        }
    }

    private func autoNextCard(_ count: Int) -> some View {
        VStack { Spacer(); HStack { Spacer(); VStack(alignment: .leading, spacing: 9) {
            Text("TỰ CHUYỂN SAU \(count) GIÂY").font(.caption.bold()).foregroundStyle(CineVietTheme.accent)
            Text(viewModel.nextEpisode?.name ?? "Tập tiếp theo").font(.headline)
            HStack { Button("Xem ngay") { viewModel.playNextEpisode() }.buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black); Button("Hủy") { viewModel.cancelAutoNext() }.buttonStyle(.bordered) }
        }.padding(16).background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(CineVietTheme.accent.opacity(0.35)) }.frame(maxWidth: 330); Spacer().frame(width: 24) }.padding(.bottom, 24) }
    }

    @ViewBuilder private func selectionPanel(_ panel: PlayerPanel) -> some View {
        PlayerSelectionPanel(title: panelTitle(panel), subtitle: "\(viewModel.movie.title) • \(viewModel.currentEpisode.name)") {
            switch panel {
            case .servers:
                ForEach(viewModel.servers, id: \.name) { server in SelectionRow(title: server.name, detail: "\(server.items.count) tập", selected: server.name == viewModel.currentServer.name) { choose { viewModel.playServer(named: server.name) } } }
            case .episodes:
                ForEach(viewModel.currentServer.items) { episode in SelectionRow(title: episode.name, detail: PlayerViewModel.directMediaURL(for: episode) == nil ? "Chưa có nguồn trực tiếp" : "Sẵn sàng phát", selected: episode.id == viewModel.currentEpisode.id) { choose { viewModel.play(episode, server: viewModel.currentServer) } } }
            case .audio:
                SelectionRow(title: "Theo nguồn HLS chính", detail: "Âm thanh mặc định của nguồn", selected: viewModel.selectedAudioKey == nil) { choose { viewModel.selectAudio(nil) } }
                ForEach(viewModel.availableAudio) { source in SelectionRow(title: source.label.isEmpty ? source.key : source.label, detail: source.key, selected: source.key == viewModel.selectedAudioKey) { choose { viewModel.selectAudio(source) } } }
            case .subtitles:
                SelectionRow(title: "Tắt phụ đề", detail: nil, selected: viewModel.selectedSubtitleLanguage == "off") { choose { viewModel.selectSubtitle("off") } }
                if hasSubtitle("vi") && hasSubtitle("en") { SelectionRow(title: "Song ngữ Việt + Anh", detail: "Hiển thị đồng thời hai track ngoài", selected: viewModel.selectedSubtitleLanguage == "dual") { choose { viewModel.selectSubtitle("dual") } } }
                ForEach(viewModel.availableSubtitles) { track in SelectionRow(title: track.label.isEmpty ? track.lang.uppercased() : track.label, detail: track.format.uppercased(), selected: viewModel.selectedSubtitleLanguage == track.lang) { choose { viewModel.selectSubtitle(track.lang) } } }
                if !viewModel.availableSubtitles.isEmpty {
                    Button { activePanel = .subtitleSettings } label: { Label("Cài đặt phụ đề", systemImage: "textformat.size") }
                        .buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black).padding(.top, 8)
                }
            case .subtitleSettings:
                SubtitleSettingsPanel(styles: viewModel.subtitleStyles, onChange: { language, style in viewModel.updateSubtitleStyle(style, language: language) }, onReset: viewModel.resetSubtitleStyles)
            }
        }
    }

    private func featureButton(_ icon: String, _ title: String, active: Bool = false, action: @escaping () -> Void) -> some View { Button { interact(action) } label: { Label(title, systemImage: icon).playerPill(active: active) } }
    private func transportButton(_ icon: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View { Button { interact(action) } label: { Image(systemName: icon).font(.system(size: 27, weight: .semibold)).frame(width: 52, height: 52).background(.black.opacity(0.45), in: Circle()) }.disabled(disabled).opacity(disabled ? 0.35 : 1).accessibilityLabel(label) }
    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).playerCircle() }.accessibilityLabel(label) }
    private func interact(_ action: () -> Void) { action(); revealControls() }
    private func choose(_ action: () -> Void) { action(); activePanel = nil; revealControls() }
    private func revealControls() { guard !controlsLocked else { return }; withAnimation(.easeInOut(duration: 0.18)) { controlsVisible = true }; scheduleHide() }
    private func hideControls() { hideTask?.cancel(); withAnimation(.easeInOut(duration: 0.18)) { controlsVisible = false } }
    private func scheduleHide() { hideTask?.cancel(); guard !controlsLocked, activePanel == nil, !isScrubbing else { return }; hideTask = Task { try? await Task.sleep(nanoseconds: 4_000_000_000); guard !Task.isCancelled else { return }; await MainActor.run { hideControls() } } }
    private func exitPlayer() {
        viewModel.stop()
        OrientationManager.portrait()
        NotificationCenter.default.post(name: .cineVietPlayerDidDisappear, object: nil)
        dismiss()
    }
    private func time(_ seconds: Double) -> String { let value = max(0, Int(seconds.isFinite ? seconds : 0)); return String(format: "%02d:%02d", value / 60, value % 60) }
    private func panelTitle(_ panel: PlayerPanel) -> String { switch panel { case .episodes: return "Chọn tập phim"; case .servers: return "Chọn máy chủ"; case .audio: return "Chọn âm thanh"; case .subtitles: return "Chọn phụ đề"; case .subtitleSettings: return "Cài đặt phụ đề" } }
    private func hasSubtitle(_ language: String) -> Bool { viewModel.availableSubtitles.contains { $0.lang.lowercased().hasPrefix(language) } }
}

private struct PlayerSelectionPanel<Content: View>: View {
    let title: String; let subtitle: String; @ViewBuilder let content: Content
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) { self.title = title; self.subtitle = subtitle; self.content = content() }
    var body: some View { NavigationStack { ScrollView { LazyVStack(spacing: 9) { content }.padding(16) }.background(CineVietTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline).safeAreaInset(edge: .top) { Text(subtitle).font(.caption).foregroundStyle(CineVietTheme.textMuted).padding(.vertical, 5) } }.preferredColorScheme(.dark) }
}

private struct SelectionRow: View {
    let title: String; let detail: String?; let selected: Bool; let action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 12) { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? CineVietTheme.accent : CineVietTheme.textMuted); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.bold()); if let detail { Text(detail).font(.caption).foregroundStyle(CineVietTheme.textMuted) } }; Spacer() }.padding(14).background(selected ? CineVietTheme.accent.opacity(0.12) : CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 13)).overlay { RoundedRectangle(cornerRadius: 13).stroke(selected ? CineVietTheme.accent.opacity(0.55) : CineVietTheme.border) } }.buttonStyle(.plain).foregroundStyle(.white) }
}

private struct SubtitleSettingsPanel: View {
    let styles: [String: PlayerViewModel.SubtitleStyle]
    let onChange: (String, PlayerViewModel.SubtitleStyle) -> Void
    let onReset: () -> Void
    @State private var language = "vi"
    var body: some View {
        let style = styles[language] ?? (language == "en" ? .english : .vietnamese)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Ngôn ngữ", selection: $language) { Text("Phụ đề chính").tag("vi"); Text("Song ngữ / Anh").tag("en") }.pickerStyle(.segmented)
                CollisionSafeSubtitleLayout(
                    captions: ["vi": "Đây là nội dung phụ đề mẫu", "en": "Subtitle preview"],
                    styles: styles,
                    dual: true,
                    minimumBottomInset: 12
                ).frame(maxWidth: .infinity, minHeight: 190).background(.black, in: RoundedRectangle(cornerRadius: 12))
                Text(language == "vi" ? "Phụ đề chính" : "Song ngữ / Phụ đề Anh").font(.headline)
                Text("Font chữ").font(.subheadline.bold())
                Picker("Font chữ", selection: Binding(get: { style.font }, set: { onChange(language, styleWith(style, font: $0)) })) { ForEach(["Lora", "Plus Jakarta Sans", "Arial", "Tahoma"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
                Text("Cỡ chữ: \(Int(style.size))px")
                Slider(value: Binding(get: { style.size }, set: { onChange(language, styleWith(style, size: $0)) }), in: 10...(language == "vi" ? 50 : 40), step: 1).tint(CineVietTheme.accent)
                Text("Màu chữ").font(.subheadline.bold())
                HStack(spacing: 14) { ForEach(["FFFFFF", "FFFF99", "FFEB3B", "80D8FF", "FFB3C7"], id: \.self) { hex in Button { onChange(language, styleWith(style, colorHex: hex)) } label: { Circle().fill(Color.playerHex(hex)).frame(width: 36, height: 36).overlay { Circle().stroke(CineVietTheme.accent, lineWidth: style.colorHex == hex ? 3 : 1) } } } }
                Text("Vị trí: \(Int(style.bottom))% từ cạnh dưới")
                Slider(value: Binding(get: { style.bottom }, set: { onChange(language, styleWith(style, bottom: $0)) }), in: 2...30, step: 1).tint(CineVietTheme.accent)
                HStack { Button("Reset tất cả", action: onReset).buttonStyle(.bordered); Spacer(); Text("Thay đổi được áp dụng ngay").font(.caption).foregroundStyle(CineVietTheme.textMuted) }
            }.padding(20)
        }
    }
    private func styleWith(_ style: PlayerViewModel.SubtitleStyle, font: String? = nil, size: Double? = nil, colorHex: String? = nil, bottom: Double? = nil) -> PlayerViewModel.SubtitleStyle { .init(font: font ?? style.font, size: size ?? style.size, colorHex: colorHex ?? style.colorHex, bottom: bottom ?? style.bottom) }
}

/// Places VI and EN as independently styled views, measures their real wrapped
/// bounds, then separates their vertical boxes. User positions remain desired
/// anchors; collision resolution only moves the tracks enough to keep VI above
/// EN with a readable gap and within the visible landscape area.
private struct CollisionSafeSubtitleLayout: View {
    let captions: [String: String]
    let styles: [String: PlayerViewModel.SubtitleStyle]
    let dual: Bool
    let minimumBottomInset: CGFloat
    @State private var measured: [String: CGSize] = [:]
    private let gap: CGFloat = 12
    private let topInset: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let active = activeLanguages
            let frames = resolvedFrames(in: geometry.size, languages: active)
            ZStack(alignment: .topLeading) {
                ForEach(active, id: \.self) { language in
                    let style = styles[language] ?? (language == "en" ? .english : .vietnamese)
                    Text(captions[language]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                        .font(.custom(style.font, fixedSize: style.size).weight(.bold))
                        .foregroundStyle(Color.playerHex(style.colorHex))
                        .multilineTextAlignment(.center)
                        .lineSpacing(max(0, CGFloat(style.size) * 0.2))
                        .shadow(color: .black, radius: 4, x: 0, y: 1)
                        .shadow(color: .black, radius: 8, x: 0, y: 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: max(0, geometry.size.width - 56))
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: SubtitleSizePreferenceKey.self, value: [language: proxy.size])
                        })
                        .position(x: geometry.size.width / 2, y: (frames[language]?.midY ?? geometry.size.height / 2))
                }
            }
        }
        .onPreferenceChange(SubtitleSizePreferenceKey.self) { measured.merge($0) { _, new in new } }
    }

    private var activeLanguages: [String] {
        if dual { return ["vi", "en"].filter { !(captions[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        let language = captions["en"] != nil && captions["vi"] == nil ? "en" : "vi"
        return captions[language] == nil ? [] : [language]
    }

    private func resolvedFrames(in size: CGSize, languages: [String]) -> [String: CGRect] {
        guard size.height > 0 else { return [:] }
        func height(_ language: String) -> CGFloat {
            // Real SwiftUI measurement is preferred; this conservative fallback
            // protects the first layout pass and multiline/large-font captions.
            let style = styles[language] ?? (language == "en" ? .english : .vietnamese)
            return max(measured[language]?.height ?? CGFloat(style.size) * 2.5, CGFloat(style.size) * 1.3)
        }
        func desiredTop(_ language: String) -> CGFloat {
            let style = styles[language] ?? (language == "en" ? .english : .vietnamese)
            let bottom = max(minimumBottomInset, size.height * CGFloat(style.bottom / 100))
            return size.height - bottom - height(language)
        }
        guard languages.count == 2 else {
            guard let language = languages.first else { return [:] }
            let h = height(language)
            let top = min(max(topInset, desiredTop(language)), max(topInset, size.height - minimumBottomInset - h))
            return [language: CGRect(x: 28, y: top, width: max(0, size.width - 56), height: h)]
        }

        let enHeight = height("en"), viHeight = height("vi")
        var enTop = min(max(topInset + viHeight + gap, desiredTop("en")), size.height - minimumBottomInset - enHeight)
        var viTop = min(desiredTop("vi"), enTop - gap - viHeight)
        if viTop < topInset {
            viTop = topInset
            enTop = max(enTop, viTop + viHeight + gap)
        }
        if enTop + enHeight > size.height - minimumBottomInset {
            enTop = size.height - minimumBottomInset - enHeight
            viTop = min(viTop, enTop - gap - viHeight)
        }
        return [
            "vi": CGRect(x: 28, y: max(topInset, viTop), width: max(0, size.width - 56), height: viHeight),
            "en": CGRect(x: 28, y: max(topInset + viHeight + gap, enTop), width: max(0, size.width - 56), height: enHeight)
        ]
    }
}

private struct SubtitleSizePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) { value.merge(nextValue()) { _, new in new } }
}

private extension Color {
    static func playerHex(_ raw: String) -> Color {
        let value = UInt64(raw, radix: 16) ?? 0xFFFFFF
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

private struct PlayerErrorCard: View {
    let message: String; let retry: () -> Void; let sources: () -> Void; let exit: () -> Void
    var body: some View { VStack(spacing: 12) { Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(CineVietTheme.accent); Text("Không thể phát phim").font(.headline); Text(message).font(.subheadline).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.center); HStack { Button("Thử lại", action: retry).buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black); Button("Đổi nguồn", action: sources).buttonStyle(.bordered); Button("Thoát", action: exit).buttonStyle(.bordered) } }.padding(20).frame(maxWidth: 480).background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(CineVietTheme.border) }.padding() }
}

private extension View {
    func playerPill(active: Bool = false) -> some View { font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 10).background(active ? CineVietTheme.accent.opacity(0.2) : .black.opacity(0.5), in: Capsule()).overlay { Capsule().stroke(active ? CineVietTheme.accent.opacity(0.7) : .white.opacity(0.16)) }.foregroundStyle(active ? CineVietTheme.accent : .white) }
    func playerCircle() -> some View { frame(width: 42, height: 42).background(.black.opacity(0.5), in: Circle()).overlay { Circle().stroke(.white.opacity(0.14)) } }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.prioritizesVideoDevices = true; view.tintColor = .white; view.activeTintColor = UIColor(CineVietTheme.accent); return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
