import SwiftUI

// MARK: - 正在播放卡片组件 (深度还原 Sonos 官方播放器视觉)
public struct NowPlayingView: View {
    @Bindable var controller: SonosController

    private var track: TrackInfo {
        controller.currentGroup?.currentTrack ?? TrackInfo()
    }

    private var isPlaying: Bool {
        controller.currentGroup?.playbackState.isPlaying ?? false
    }

    public var body: some View {
        VStack(spacing: 14) {
            // 1. 大尺寸正方形专辑封面 (还原截图 2)
            ZStack {
                if let urlStr = track.albumArtUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            fallbackCover
                        }
                    }
                } else {
                    fallbackCover
                }
            }
            .frame(width: 260, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 8)

            // 2. 歌曲元数据与服务标识 (还原截图 2)
            VStack(spacing: 5) {
                Text(track.title.isEmpty ? "暂无播放" : track.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                if !track.artist.isEmpty || !track.album.isEmpty {
                    let subtitle = [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " • ")
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }

                // 音乐服务标签 (如 Spotify 绿色小标)
                if let service = track.musicService, !service.isEmpty {
                    HStack(spacing: 5) {
                        serviceIcon(service)
                        Text(service)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)

            // 3. 极细进度条与时间显示 (左侧播放时间，右侧剩余时间 -X:XX)
            VStack(spacing: 5) {
                GeometryReader { geo in
                    let progress = min(1.0, max(0.0, track.durationSeconds > 0 ? (track.positionSeconds / track.durationSeconds) : 0))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 3)

                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(formatTime(track.positionSeconds))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Spacer()
                    let remaining = max(0, track.durationSeconds - track.positionSeconds)
                    Text("-\(formatTime(remaining))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 4)
    }

    // 默认高质感封面
    private var fallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.22, blue: 0.18), Color(red: 0.15, green: 0.12, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.white.opacity(0.85))

                Text("無名的人")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("毛不易")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func serviceIcon(_ name: String?) -> some View {
        let n = (name ?? "").lowercased()
        if n.contains("spotify") {
            Circle()
                .fill(Color(red: 0.11, green: 0.73, blue: 0.33))
                .frame(width: 13, height: 13)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.black)
                )
        } else if n.contains("apple") {
            Image(systemName: "applelogo")
                .font(.system(size: 12))
                .foregroundStyle(.pink)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let m = s / 60
        let remainder = s % 60
        return String(format: "%d:%02d", m, remainder)
    }
}
