import SwiftUI

// MARK: - 房间与音响设备选择器 (包含分组与收藏夹入口)
public struct ZonePickerView: View {
    @Bindable var controller: SonosController
    var onOpenFavorites: () -> Void

    public var body: some View {
        HStack(spacing: 8) {
            // 音箱分组选择下拉
            Menu {
                ForEach(controller.groups) { group in
                    Button {
                        controller.selectGroup(id: group.id)
                    } label: {
                        HStack {
                            Text(group.name)
                            if group.id == controller.currentGroupId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hifispeaker.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(controller.currentGroup?.name ?? L(.selectSpeaker))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)

            // 收藏夹快捷入口
            Button {
                onOpenFavorites()
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
            .help(L(.sonosFavorites))

            Spacer()

            // 在线/演示状态标签
            HStack(spacing: 4) {
                Circle()
                    .fill(controller.isConnected ? Color.green : Color.brand)
                    .frame(width: 6, height: 6)
                Text(controller.config.isDemoMode ? "演示" : (controller.isConnected ? "在线" : "离线"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
