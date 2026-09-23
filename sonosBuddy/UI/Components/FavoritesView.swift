import SwiftUI

// MARK: - 播放队列与内容清单面板 (Queue & Playlists)
public struct QueueView: View {
    @Bindable var controller: SonosController
    var onDismiss: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Label(L(.favoritesTitle), systemImage: "star.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Spacer()

                Button(L(.done)) {
                    onDismiss()
                }
                .controlSize(.small)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 收藏清单列表
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L(.myFavorites))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: L(.favoritesCount), "\(controller.favorites.count)"))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        if controller.favorites.isEmpty {
                            VStack(spacing: 6) {
                                Text(L(.noFavorites))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(L(.noFavoritesHint))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 70)
                        } else {
                            LazyVStack(spacing: 5) {
                                ForEach(controller.favorites) { item in
                                    Button {
                                        controller.playFavorite(item)
                                        onDismiss()
                                    } label: {
                                        HStack(spacing: 8) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(LinearGradient(colors: [.orange.opacity(0.8), .pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    .frame(width: 30, height: 30)

                                                Image(systemName: "music.note")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.white)
                                            }

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(item.name)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                if let service = item.service {
                                                    Text(service)
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            Spacer()

                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color.accentColor.opacity(0.8))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.primary.opacity(0.03))
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Sonos 官方 MCP 协议说明
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(L(.mcpNote))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: 280)
        }
        .padding(14)
        .frame(width: 320)
    }
}

// 保持别名兼容
public typealias FavoritesView = QueueView
