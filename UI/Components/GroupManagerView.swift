import SwiftUI

// MARK: - 音箱列表与各音箱独立音量控制面板 (深度复刻截图 3)
public struct GroupManagerView: View {
    @Bindable var controller: SonosController
    var onDismiss: () -> Void

    @State private var selectedDeviceIds: Set<String> = []

    private var track: TrackInfo {
        controller.currentGroup?.currentTrack ?? TrackInfo()
    }

    private var isPlaying: Bool {
        controller.currentGroup?.playbackState.isPlaying ?? false
    }

    public var body: some View {
        VStack(spacing: 14) {
            // 1. 顶部 Mini Now-Playing 卡片 (还原截图 3)
            HStack(spacing: 12) {
                // 小专辑封面
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.35, green: 0.22, blue: 0.18))
                        .frame(width: 44, height: 44)

                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.11, green: 0.73, blue: 0.33))
                            .frame(width: 8, height: 8)
                        Text("\(track.artist) • \(track.album.isEmpty ? track.title : track.album)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 音箱数量徽标与播放/暂停小钮
                HStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "hifispeaker")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text("\(selectedDeviceIds.count)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.white)
                            .offset(x: 4, y: -4)
                    }

                    Button {
                        controller.togglePlayPause()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // 2. 标签与快捷操作
            HStack {
                Text(L(.allSpeakers))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.18)))

                Spacer()

                Button {
                    let allIds = Set(controller.allDevices.map { $0.id })
                    if selectedDeviceIds == allIds {
                        if let firstId = controller.allDevices.first?.id {
                            selectedDeviceIds = [firstId]
                        }
                    } else {
                        selectedDeviceIds = allIds
                    }
                } label: {
                    Text(selectedDeviceIds.count == controller.allDevices.count ? L(.deselectAll) : L(.selectAll))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            // 3. 各音箱设备卡片 (包含各自独立的音量调节滑块，还原截图 3)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(controller.allDevices) { device in
                        let isSelected = selectedDeviceIds.contains(device.id)

                        HStack(spacing: 12) {
                            // 音箱图标 (根据设备类型区分音响条/圆柱/便携)
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 42, height: 42)

                                Image(systemName: device.iconName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.white.opacity(isSelected ? 0.95 : 0.4))
                            }

                            // 音箱名称、型号与【独立音量控制滑块】
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(device.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                    if let model = device.modelName {
                                        Text(model)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.white.opacity(0.4))
                                    }
                                }

                                // 独立音量控制条 (喇叭图标 + 微调滑块 + 音量数字，还原截图 3)
                                HStack(spacing: 8) {
                                    Image(systemName: "speaker.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.white.opacity(0.5))

                                    GeometryReader { geo in
                                        let pct = min(1.0, max(0.0, Double(device.volume) / 100.0))
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.white.opacity(0.15))
                                                .frame(height: 3)

                                            Capsule()
                                                .fill(Color.white.opacity(0.85))
                                                .frame(width: geo.size.width * pct, height: 3)

                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 10, height: 10)
                                                .offset(x: max(0, min(geo.size.width - 10, geo.size.width * pct - 5)))
                                        }
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    let fraction = max(0, min(1, value.location.x / geo.size.width))
                                                    controller.setPlayerVolume(playerId: device.id, volume: Int(fraction * 100))
                                                }
                                        )
                                    }
                                    .frame(height: 10)

                                    Text("\(device.volume)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.6))
                                        .frame(width: 16, alignment: .trailing)
                                }
                                .frame(height: 14)
                            }

                            Spacer()

                            // 右侧勾选圆圈 (选中为实心对勾圆圈，未选为空心圆，还原截图 3)
                            Button {
                                if isSelected {
                                    if selectedDeviceIds.count > 1 {
                                        selectedDeviceIds.remove(device.id)
                                    }
                                } else {
                                    selectedDeviceIds.insert(device.id)
                                }
                            } label: {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 250)

            Spacer()

            // 4. 底部全宽白色圆角按钮：应用 (还原截图 3)
            Button {
                controller.applyGroupSelection(selectedDeviceIds: selectedDeviceIds)
                onDismiss()
            } label: {
                Text(L(.apply))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 8)
        .frame(width: 320, height: 460)
        .onAppear {
            if let group = controller.currentGroup {
                self.selectedDeviceIds = Set(group.deviceIds)
            }
        }
    }
}
