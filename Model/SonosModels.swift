import Foundation

// MARK: - 播放状态枚举
public enum PlaybackState: String, Codable, Sendable {
    case playing = "PLAYING"
    case paused = "PAUSED"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case unknown = "UNKNOWN"

    public var isPlaying: Bool {
        return self == .playing
    }
}

// MARK: - 循环播放模式
public enum RepeatMode: String, Codable, Sendable {
    case off = "OFF"
    case all = "ALL"
    case one = "ONE"
}

// MARK: - 曲目信息 (包含音乐服务标识与封面)
public struct TrackInfo: Codable, Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtUrl: String?
    public var musicService: String?
    public var durationSeconds: Double
    public var positionSeconds: Double

    public init(
        title: String = "",
        artist: String = "",
        album: String = "",
        albumArtUrl: String? = nil,
        musicService: String? = nil,
        durationSeconds: Double = 0,
        positionSeconds: Double = 0
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtUrl = albumArtUrl
        self.musicService = musicService
        self.durationSeconds = durationSeconds
        self.positionSeconds = positionSeconds
    }
}

// MARK: - Sonos 收藏项 (Favorites & Playlists)
public struct SonosFavoriteItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var imageUrl: String?
    public var service: String?

    public init(id: String, name: String, imageUrl: String? = nil, service: String? = nil) {
        self.id = id
        self.name = name
        self.imageUrl = imageUrl
        self.service = service
    }
}

// MARK: - Sonos 单个音响设备 (Player，支持独立音量与型号识别)
public struct SonosDevice: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var roomName: String
    public var modelName: String?
    public var isMuted: Bool
    public var volume: Int

    public init(
        id: String,
        name: String,
        roomName: String,
        modelName: String? = nil,
        isMuted: Bool = false,
        volume: Int = 10
    ) {
        self.id = id
        self.name = name
        self.roomName = roomName
        self.modelName = modelName
        self.isMuted = isMuted
        self.volume = volume
    }

    /// 设备类型图标
    public var iconName: String {
        let lower = (name + (modelName ?? "")).lowercased()
        if lower.contains("beam") || lower.contains("arc") || lower.contains("bar") {
            return "tv.and.soundbar.fill"
        } else if lower.contains("roam") {
            return "capsule.portrait.fill"
        } else if lower.contains("move") {
            return "speaker.wave.2.fill"
        } else {
            return "hifispeaker.fill"
        }
    }
}

// MARK: - Sonos 音响分组 (Group / Zone)
public struct SonosGroup: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var deviceIds: [String]
    public var playbackState: PlaybackState
    public var currentTrack: TrackInfo
    public var volume: Int
    public var isMuted: Bool
    public var isShuffle: Bool
    public var repeatMode: RepeatMode

    public init(
        id: String,
        name: String,
        deviceIds: [String] = [],
        playbackState: PlaybackState = .playing,
        currentTrack: TrackInfo = TrackInfo(),
        volume: Int = 7,
        isMuted: Bool = false,
        isShuffle: Bool = false,
        repeatMode: RepeatMode = .off
    ) {
        self.id = id
        self.name = name
        self.deviceIds = deviceIds
        self.playbackState = playbackState
        self.currentTrack = currentTrack
        self.volume = volume
        self.isMuted = isMuted
        self.isShuffle = isShuffle
        self.repeatMode = repeatMode
    }
}

// MARK: - 应用配置
public struct AppConfig: Codable, Sendable {
    public var mcpEndpoint: String
    public var bearerToken: String
    public var isDemoMode: Bool
    public var pollIntervalSeconds: Double
    public var openAIKey: String
    public var openAIEndpoint: String
    public var openAIModel: String
    public var preferredMusicService: String
    public var isVoiceEnabled: Bool
    public var speechTimeoutSeconds: Int

    enum CodingKeys: String, CodingKey {
        case mcpEndpoint, bearerToken, isDemoMode, pollIntervalSeconds, openAIKey, openAIEndpoint, openAIModel, preferredMusicService, isVoiceEnabled, speechTimeoutSeconds
    }

    public init(
        mcpEndpoint: String = "https://mcp.ws.sonos.com/mcp",
        bearerToken: String = "",
        isDemoMode: Bool = false,
        pollIntervalSeconds: Double = 30.0,
        openAIKey: String = "",
        openAIEndpoint: String = "https://api.openai.com/v1",
        openAIModel: String = "",
        preferredMusicService: String = "Apple Music",
        isVoiceEnabled: Bool = false,
        speechTimeoutSeconds: Int = 3
    ) {
        self.mcpEndpoint = mcpEndpoint
        self.bearerToken = bearerToken
        self.isDemoMode = isDemoMode
        self.pollIntervalSeconds = pollIntervalSeconds
        self.openAIKey = openAIKey
        self.openAIEndpoint = openAIEndpoint
        self.openAIModel = openAIModel
        self.preferredMusicService = preferredMusicService
        self.isVoiceEnabled = isVoiceEnabled
        self.speechTimeoutSeconds = speechTimeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mcpEndpoint = try container.decodeIfPresent(String.self, forKey: .mcpEndpoint) ?? "https://mcp.ws.sonos.com/mcp"
        bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken) ?? ""
        isDemoMode = try container.decodeIfPresent(Bool.self, forKey: .isDemoMode) ?? false
        pollIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds) ?? 30.0
        openAIKey = try container.decodeIfPresent(String.self, forKey: .openAIKey) ?? ""
        openAIEndpoint = try container.decodeIfPresent(String.self, forKey: .openAIEndpoint) ?? "https://api.openai.com/v1"
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? ""
        preferredMusicService = try container.decodeIfPresent(String.self, forKey: .preferredMusicService) ?? "Apple Music"
        isVoiceEnabled = try container.decodeIfPresent(Bool.self, forKey: .isVoiceEnabled) ?? false
        speechTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .speechTimeoutSeconds) ?? 3
    }
}
