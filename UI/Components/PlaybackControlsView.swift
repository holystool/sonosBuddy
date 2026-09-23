import SwiftUI

// MARK: - 播放控制与底部音箱路由条 (深度还原 Sonos 官方播放器)
public struct PlaybackControlsView: View {
    @Bindable var controller: SonosController
    var onOpenQueue: () -> Void
    var onOpenGroupManager: () -> Void
    @StateObject private var speechManager = SpeechManager.shared

    private var isPlaying: Bool {
        controller.currentGroup?.playbackState.isPlaying ?? false
    }

    private var groupVolume: Int {
        controller.currentGroup?.volume ?? 7
    }

    public var body: some View {
        VStack(spacing: 16) {
            // 1. 核心播控按键行 (上一曲、大播放/暂停圆钮、下一曲)
            HStack(spacing: 36) {
                // 上一曲 (切歌)
                Button {
                    controller.previousTrack()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("上一曲")

                // 播放 / 暂停 (深灰大圆底 + 白色图标)
                Button {
                    controller.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.28))
                            .frame(width: 58, height: 58)
                            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)
                .help(isPlaying ? L(.pause) : L(.play))

                // 下一曲 (切歌)
                Button {
                    controller.nextTrack()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help(L(.nextTrack))
            }
            .padding(.top, 2)

            // 2. 主音量控制条 (喇叭图标 + 滑块 + 音量数字，还原截图 2)
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 16)

                GeometryReader { geo in
                    let pct = min(1.0, max(0.0, Double(groupVolume) / 100.0))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 4)

                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * pct, height: 4)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .offset(x: max(0, min(geo.size.width - 14, geo.size.width * pct - 7)))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                controller.setVolume(Int(fraction * 100), commitImmediately: false)
                            }
                            .onEnded { value in
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                controller.setVolume(Int(fraction * 100), commitImmediately: true)
                            }
                    )
                }
                .frame(height: 14)

                Text("\(groupVolume)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 20, alignment: .trailing)
            }
            .padding(.horizontal, 24)

            // 3. 底部功能栏 (收藏夹图标 | 音箱群组胶囊切换器 | 更多设置，完整复刻截图 2)
            HStack {
                // 播放队列与清单入口
                Button {
                    onOpenQueue()
                } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help(L(.viewQueueHint))

                Spacer()

                // 核心：音箱胶囊切换器 [ 2 卧室, Sonos Roam 🔀 ]
                Button {
                    onOpenGroupManager()
                } label: {
                    HStack(spacing: 6) {
                        // 带有数字徽标的音响图标
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "hifispeaker")
                                .font(.system(size: 12))
                            if let group = controller.currentGroup, group.deviceIds.count > 1 {
                                Text("\(group.deviceIds.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .offset(x: 5, y: -4)
                            }
                        }

                        Text(controller.currentGroup?.name ?? L(.selectSpeaker))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)

                        Image(systemName: "airplayaudio")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .help(L(.manageSpeakersHint))

                Spacer()

                // 语音输入控制按钮（替代原来的设置按钮）
                Button {
                    speechManager.toggleRecording(
                        onUpdate: { transcribed in
                            controller.lastActionFeedback = String(format: L(.listeningFeedback), transcribed)
                        },
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
                                .frame(width: 38, height: 38)
                                .scaleEffect(1.2)
                        }

                        Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(speechManager.isRecording ? Color.red : Color.white.opacity(0.85))
                            .frame(width: 38, height: 38)
                            .background(
                                Circle().fill(speechManager.isRecording ? Color.red.opacity(0.25) : Color.white.opacity(0.1))
                            )
                    }
                }
                .buttonStyle(.plain)
                .help(speechManager.isRecording ? L(.tapToStopRecord) : (Localizer.shared.isEnglish ? L(.tapVoiceControlEn) : L(.tapVoiceControl)))
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
    }
}
