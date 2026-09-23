import SwiftUI

// MARK: - 页面导航路由枚举
enum ActiveScreen {
    case player
    case settings
    case favorites
    case groupManager
}

// MARK: - 菜单栏主视图
public struct MenuBarView: View {
    @Bindable var controller: SonosController
    @StateObject private var speechManager = SpeechManager.shared
    @State private var activeScreen: ActiveScreen = .player
    @State private var hasCheckedAuth: Bool = false
    @State private var isDeviceMenuOpen: Bool = false

    private var isPlaying: Bool {
        controller.currentGroup?.playbackState.isPlaying ?? false
    }

    private var groupVolume: Int {
        controller.currentGroup?.volume ?? 7
    }

    private var memberDevices: [SonosDevice] {
        guard let group = controller.currentGroup, group.deviceIds.count > 1 else { return [] }
        return controller.allDevices.filter { group.deviceIds.contains($0.id) }
    }

    private var hasBottomStatus: Bool {
        true // 底部状态栏常驻（语音录音 -> 操作反馈 -> 维持 3 秒后自动显示当前 MCP 计数）
    }

    private var currentPanelHeight: CGFloat {
        if activeScreen != .player {
            return 380
        }
        var base = memberDevices.isEmpty ? 126 : 126 + CGFloat(memberDevices.count * 22)
        if hasBottomStatus {
            base += 24
        }
        if isDeviceMenuOpen {
            // 展开设备列表时统一给予充裕的大方空间（200px），避免计算偏差导致任何截断
            return max(base, 200)
        }
        return base
    }

    public var body: some View {
        ZStack {
            switch activeScreen {
            case .player:
                playerContentView
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            case .settings:
                SettingsView(controller: controller, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeScreen = .player
                    }
                })
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            case .favorites:
                QueueView(controller: controller, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeScreen = .player
                    }
                })
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            case .groupManager:
                GroupManagerView(controller: controller, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeScreen = .player
                    }
                })
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            }
        }
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .onAppear {
            controller.checkAndResetQuotaCycleIfNeeded()
            // 未授权时自动跳转到设置页面引导用户完成 OAuth 登录
            if !hasCheckedAuth {
                hasCheckedAuth = true
                if controller.config.bearerToken.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeScreen = .settings
                    }
                }
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("SonosPanelResize"),
                object: CGSize(width: activeScreen == .player ? 260 : 310, height: currentPanelHeight)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SonosOpenSettings"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                activeScreen = .settings
                isDeviceMenuOpen = false
            }
        }
        .onChange(of: currentPanelHeight) { _, newHeight in
            NotificationCenter.default.post(
                name: NSNotification.Name("SonosPanelResize"),
                object: CGSize(width: activeScreen == .player ? 260 : 310, height: newHeight)
            )
        }
        .onChange(of: activeScreen) { _, newScreen in
            // 设置界面时常驻（点击外部不自动回收），主界面等其他页面保持点击外部自动回收
            NotificationCenter.default.post(
                name: NSNotification.Name("SonosSetPinned"),
                object: newScreen == .settings
            )
        }
        .accentColor(.brand)
    }

    // MARK: - 大幅精简紧凑主界面 (仅保留设备列表、播放、切歌、音量、语音输入)
    private var playerContentView: some View {
        ZStack(alignment: .topLeading) {
            // 主控制面板层
            VStack(spacing: 9) {
                // 1. 顶部：设备选择下拉按钮 + 麦克风控制按钮（左边设备，右边麦克风，不再被反馈覆盖或挤占）
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isDeviceMenuOpen.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "hifispeaker.2.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(controller.currentGroup?.name ?? L(.selectSpeaker))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Image(systemName: isDeviceMenuOpen ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isDeviceMenuOpen ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Sonos 收藏按钮
                    Button {
                        if isDeviceMenuOpen {
                            withAnimation(.easeInOut(duration: 0.18)) { isDeviceMenuOpen = false }
                        }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeScreen = .favorites
                        }
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help(L(.sonosFavorites))

                    // 语音输入控制按钮（支持窗口期超时自动退出执行）
                    Button {
                        if isDeviceMenuOpen {
                            withAnimation(.easeInOut(duration: 0.18)) { isDeviceMenuOpen = false }
                        }
                        speechManager.toggleRecording(
                            timeoutSeconds: controller.config.speechTimeoutSeconds,
                            onUpdate: { _ in },
                            onFinished: { finalText in
                                Task {
                                    await controller.executeNaturalLanguageCommand(finalText)
                                }
                            }
                        )
                    } label: {
                        ZStack {
                            if speechManager.isRecording {
                                Circle()
                                    .fill(Color.red.opacity(0.35))
                                    .frame(width: 26, height: 26)
                                    .scaleEffect(1.2)
                            }

                            Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    !controller.config.isVoiceEnabled ? Color.secondary.opacity(0.4) :
                                    speechManager.isRecording ? Color.red : Color.primary.opacity(0.8)
                                )
                                .frame(width: 26, height: 26)
                                .background(
                                    Circle().fill(
                                        speechManager.isRecording ? Color.red.opacity(0.2) :
                                        !controller.config.isVoiceEnabled ? Color.primary.opacity(0.03) :
                                        Color.primary.opacity(0.06)
                                    )
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.config.isVoiceEnabled)
                    .help(
                        !controller.config.isVoiceEnabled ? L(.enableVoiceFirst) :
                        speechManager.isRecording ? L(.stopRecording) : L(.voiceControlHint)
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

            // 2. 核心播控按键行 (上一曲、播放/暂停、下一曲)
            HStack(spacing: 26) {
                // 上一曲 (切歌)
                Button {
                    if isDeviceMenuOpen {
                        withAnimation(.easeInOut(duration: 0.18)) { isDeviceMenuOpen = false }
                    }
                    controller.previousTrack()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(L(.previousTrack))

                // 核心播放 / 暂停圆钮
                Button {
                    if isDeviceMenuOpen {
                        withAnimation(.easeInOut(duration: 0.18)) { isDeviceMenuOpen = false }
                    }
                    controller.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 42, height: 42)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 5, x: 0, y: 2)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 1.5)
                    }
                }
                .buttonStyle(.plain)
                .help(isPlaying ? L(.pause) : L(.play))

                // 下一曲 (切歌)
                Button {
                    if isDeviceMenuOpen {
                        withAnimation(.easeInOut(duration: 0.18)) { isDeviceMenuOpen = false }
                    }
                    controller.nextTrack()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(L(.nextTrack))
            }

            // 3. 统一总音量控制行
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                GeometryReader { geo in
                    let pct = min(1.0, max(0.0, Double(groupVolume) / 100.0))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 3.5)

                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * pct, height: 3.5)

                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                            .frame(width: 11, height: 11)
                            .offset(x: max(0, min(geo.size.width - 11, geo.size.width * pct - 5.5)))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if isDeviceMenuOpen {
                                    withAnimation(.easeInOut(duration: 0.18)) { isDeviceMenuOpen = false }
                                }
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                controller.setVolume(Int(fraction * 100), commitImmediately: false)
                            }
                            .onEnded { value in
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                controller.setVolume(Int(fraction * 100), commitImmediately: true)
                            }
                    )
                }
                .frame(height: 11)

                Text("\(groupVolume)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, memberDevices.isEmpty ? 10 : 2)

            // 4. 音箱组合时，自动出现组内各个音箱的单独音量控制条
            if !memberDevices.isEmpty {
                VStack(spacing: 5) {
                    ForEach(memberDevices) { dev in
                        HStack(spacing: 6) {
                            Text(dev.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading)
                                .lineLimit(1)

                            GeometryReader { geo in
                                let pct = min(1.0, max(0.0, Double(dev.volume) / 100.0))
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(height: 3)

                                    Capsule()
                                        .fill(Color.primary.opacity(0.4))
                                        .frame(width: geo.size.width * pct, height: 3)

                                    Circle()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                                        .frame(width: 9, height: 9)
                                        .offset(x: max(0, min(geo.size.width - 9, geo.size.width * pct - 4.5)))
                                }
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if isDeviceMenuOpen {
                                                withAnimation(.easeInOut(duration: 0.18)) { isDeviceMenuOpen = false }
                                            }
                                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                                            controller.setPlayerVolume(playerId: dev.id, volume: Int(fraction * 100), commitImmediately: false)
                                        }
                                        .onEnded { value in
                                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                                            controller.setPlayerVolume(playerId: dev.id, volume: Int(fraction * 100), commitImmediately: true)
                                        }
                                )
                            }
                            .frame(height: 9)

                            Text("\(dev.volume)")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            // 5. 底部：实时语音转写 / 操作执行结果反馈（不遮挡顶部下拉菜单）
            if speechManager.isRecording {
                // 语音录音中：实时展示识别出来的文字
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(nsColor: .systemRed))
                        .frame(width: 6, height: 6)

                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemRed))

                    Text(speechManager.recognizedText.isEmpty ? L(.listening) : speechManager.recognizedText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.12))
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 0.8)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let feedback = controller.lastActionFeedback, !feedback.isEmpty {
                // 执行结果反馈提示胶囊（清晰高对比度文字，维持 3 秒不变后自动切回 MCP 计数）
                HStack(spacing: 5) {
                    Image(systemName: feedback.contains("失败") || feedback.contains("未能") || feedback.contains("failed") || feedback.contains("error") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(feedback.contains("失败") || feedback.contains("未能") || feedback.contains("failed") || feedback.contains("error") ? Color(nsColor: .systemOrange) : Color(nsColor: .systemGreen))

                    Text(feedback.replacingOccurrences(of: "执行成功: ", with: "").replacingOccurrences(of: "Success: ", with: ""))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            controller.lastActionFeedback = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity)
                .task(id: feedback) {
                    do {
                        // 反馈文本维持 3 秒不变时，自动切回显示当前 MCP 计数
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        if !Task.isCancelled {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                controller.lastActionFeedback = nil
                            }
                        }
                    } catch {}
                }
            } else {
                // 常态 / 反馈维持 3 秒后显示：今日 MCP 请求计数
                HStack(spacing: 5) {
                    Image(systemName: "network")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.85))

                    Text(String(format: L(.todayMCP), "\(controller.todayRequestCount)"))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Circle()
                        .fill(controller.isConnected ? Color(nsColor: .systemGreen) : Color.secondary.opacity(0.4))
                        .frame(width: 5, height: 5)
                        .help(controller.isConnected ? L(.connected) : L(.disconnected))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .help(L(.todayMCPHint))
                .transition(.opacity)
            }
        }
        .frame(width: 260)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击播放器主区域空白处，自动收回下拉菜单
            if isDeviceMenuOpen {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isDeviceMenuOpen = false
                }
            }
        }

        // 浮层：下拉设备多选勾选菜单 (点击设备勾选/取消勾选不收回，点击播放器其他区域收回，多设备支持平滑滚动)
        if isDeviceMenuOpen {
            ScrollView(.vertical, showsIndicators: controller.allDevices.count > 3) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(controller.allDevices) { device in
                        let isSelected = controller.currentGroup?.deviceIds.contains(device.id) ?? false
                        Button {
                            // 点击切换组合，保持菜单展开不收回！
                            controller.toggleDeviceInCurrentGroup(deviceId: device.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))

                                Text(device.name)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)

                                if let model = device.modelName, !model.isEmpty {
                                    Text(model)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(controller.allDevices.count > 3 ? .visible : .never)
            .padding(6)
            .background(
                VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            .frame(width: 232)
            .frame(maxHeight: 148)
            .offset(x: 14, y: 38)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
        }
    }
    .frame(width: 260)
    }
}

// MARK: - 毛玻璃效果适配组件
public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(material: NSVisualEffectView.Material = .popover, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
