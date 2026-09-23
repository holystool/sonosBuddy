import SwiftUI

// MARK: - 音量控制条组件
public struct VolumeSliderView: View {
    @Bindable var controller: SonosController

    private var volume: Double {
        Double(controller.currentGroup?.volume ?? 0)
    }

    private var isMuted: Bool {
        controller.currentGroup?.isMuted ?? false
    }

    public var body: some View {
        HStack(spacing: 10) {
            // 静音切换按钮
            Button {
                Task {
                    await controller.dispatch(intent: .setMute(
                        groupId: controller.currentGroup?.id ?? "",
                        isMuted: !isMuted
                    ))
                }
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : volumeIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isMuted ? Color.red : Color.secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)

            // 音量滑块
            Slider(
                value: Binding(
                    get: { isMuted ? 0 : volume },
                    set: { newVal in
                        controller.setVolume(Int(newVal), commitImmediately: false)
                    }
                ),
                in: 0...100,
                step: 1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        controller.setVolume(Int(volume), commitImmediately: true)
                    }
                }
            )
            .tint(isMuted ? .secondary : .accentColor)

            // 音量数值百分比
            Text("\(isMuted ? 0 : Int(volume))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var volumeIcon: String {
        if volume == 0 {
            return "speaker.fill"
        } else if volume < 35 {
            return "speaker.wave.1.fill"
        } else if volume < 70 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}
