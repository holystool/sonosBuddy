import Foundation
import Observation

// MARK: - 轻量级中英双语本地化系统
/// 通过 UserDefaults 持久化语言偏好，支持运行时切换
@MainActor
@Observable
final class Localizer {
    static let shared = Localizer()

    enum Language: String, CaseIterable {
        case zh = "zh"
        case en = "en"

        var displayName: String {
            switch self {
            case .zh: return "中文"
            case .en: return "English"
            }
        }
    }

    private let langKey = "SonosBuddy.Language"
    private(set) var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: langKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: langKey) ?? ""
        self.language = Language(rawValue: raw) ?? .en
    }

    var isEnglish: Bool { language == .en }

    // MARK: - 切换语言
    func setLanguage(_ lang: Language) {
        language = lang
    }

    func toggle() {
        language = language == .zh ? .en : .zh
    }

    // MARK: - 翻译表
    // 使用 key-value 方式，zh 为默认值，en 为英文翻译
    // 调用方式: L.t(.someKey)

    func t(_ key: Key) -> String {
        isEnglish ? (enMap[key] ?? zhMap[key] ?? key.rawValue) : (zhMap[key] ?? key.rawValue)
    }

    enum Key: String, CaseIterable {
        // MenuBarView
        case selectSpeaker
        case sonosFavorites
        case voiceControlHint
        case voiceControlHintEn
        case enableVoiceFirst
        case stopRecording
        case previousTrack
        case nextTrack
        case pause
        case play
        case connected
        case disconnected
        case todayMCP
        case todayMCPHint
        case listening
        case listeningPrompt

        // SettingsView
        case settingsTitle
        case done
        case oauthTitle
        case oauthDesc
        case loginWithSonos
        case reAuthorize
        case browserAuthenticating
        case enableVoice
        case voiceAppleMusicOnly
        case noAppleMusic
        case speechTimeoutLabel
        case speechTimeoutDesc
        case apikeyFirst
        case endpointInvalid
        case llmSuccess
        case llmFailStatus
        case llmNetworkFail
        case mcpDiagnosis
        case manualRefresh
        case toolsFound
        case versionInfo
        case versionInfoEn

        // AboutUpdateView
        case aboutTitle
        case currentVersion
        case checkingUpdate
        case newVersionFound
        case checkFailed
        case noRelease
        case alreadyLatest
        case goToDownload
        case recheck
        case supportAuthor
        case wechatScan
        case kofiSponsor
        case close

        // FavoritesView
        case favoritesTitle
        case myFavorites
        case favoritesCount
        case noFavorites
        case noFavoritesHint
        case mcpNote

        // GroupManagerView
        case allSpeakers
        case selectAll
        case deselectAll
        case apply

        // SonosController
        case tokenRefreshing

        // Context Menu
        case preferences
        case aboutAndSupport
        case quitApp

        // NLInputBarView
        case tapToStopRecord
        case tapToStartVoice
        case listeningPlaceholder
        case inputPlaceholder
        case inputPlaceholderEn

        // PlaybackControlsView
        case viewQueueHint
        case manageSpeakersHint
        case tapVoiceControl
        case tapVoiceControlEn
        case listeningFeedback

        // Experimental feature
        case experimentalBadge
        case experimentalBadgeEn
        case voiceExperimentalNote
        case voiceExperimentalNoteEn

        // AboutUpdateView additional
        case kofiSponsorEn
        case kofiSponsorZh
    }

    private let zhMap: [Key: String] = [
        // MenuBarView
        .selectSpeaker: "选择音箱",
        .sonosFavorites: "Sonos 收藏",
        .voiceControlHint: "语音控制 (如: 播放周杰伦的歌 / 暂停 / 音量35)",
        .voiceControlHintEn: "Voice control (e.g. play Taylor Swift / pause / volume 35)",
        .enableVoiceFirst: "请先在设置中开启语音点播",
        .stopRecording: "点击停止录音并执行",
        .previousTrack: "上一曲",
        .nextTrack: "下一曲",
        .pause: "暂停",
        .play: "播放",
        .connected: "Sonos MCP 已连接",
        .disconnected: "未连接",
        .todayMCP: "今日 MCP: %@ 次",
        .todayMCPHint: "今日向 Sonos MCP 实际发起的网络请求总数（每天北京时间 08:00 自动重置，纯本地离线计算，0 额度消耗）",
        .listening: "正在倾听，请说话...",
        .listeningPrompt: "正在倾听，请说话...",

        // SettingsView
        .settingsTitle: "sonosBuddy 设置",
        .done: "完成",
        .oauthTitle: "Sonos 官方授权 (OAuth 2.1)",
        .oauthDesc: "Sonos 27mcp 原生基于 OAuth 2.1 + PKCE 授权，无需手动申请复杂的开发者 Key。",
        .loginWithSonos: "通过 Sonos 账号登录授权",
        .reAuthorize: "重新进行 OAuth 2.1 授权",
        .browserAuthenticating: "浏览器授权中...",
        .enableVoice: "开启语音点播",
        .voiceAppleMusicOnly: "语音点播功能仅限 Apple Music 使用。开启后可通过麦克风语音指令点播 Apple Music 曲库中的歌手、歌单和歌曲。",
        .noAppleMusic: "未检测到 Apple Music 曲库。请在 Sonos 官方 App 中添加 Apple Music 账号后，再开启此功能。",
        .speechTimeoutLabel: "语音输入倾听时长",
        .speechTimeoutDesc: "按下麦克风后开始倾听，时长结束会自动退出录音并直接执行语音控制指令。",
        .apikeyFirst: "请先填写 API Key",
        .endpointInvalid: "端点 URL 格式无效",
        .llmSuccess: "连通成功！模型: %@ (%@ms)",
        .llmFailStatus: "状态码 %@ [%@]: %@",
        .llmNetworkFail: "网络请求失败: %@",
        .mcpDiagnosis: "MCP 连接诊断",
        .manualRefresh: "手动刷新",
        .toolsFound: "已发现 %@ 个 MCP 工具",
        .versionInfo: "sonosBuddy v1.0.0",
        .versionInfoEn: "sonosBuddy v1.0.0",

        // AboutUpdateView
        .aboutTitle: "关于与赞助",
        .currentVersion: "当前版本",
        .checkingUpdate: "正在检查更新…",
        .newVersionFound: "发现新版本 v%@",
        .checkFailed: "检查失败: %@",
        .noRelease: "暂无 Release，当前已是最新版本",
        .alreadyLatest: "已是最新版本",
        .goToDownload: "前往下载",
        .recheck: "重新检查",
        .supportAuthor: "支持作者",
        .wechatScan: "微信扫码赞赏",
        .kofiSponsor: "在 Ko-fi 上赞助",
        .close: "关闭",

        // FavoritesView
        .favoritesTitle: "收藏清单",
        .myFavorites: "我的收藏",
        .favoritesCount: "%@ 个",
        .noFavorites: "暂未加载到 Sonos 收藏",
        .noFavoritesHint: "可在 Sonos 官方 App 中收藏电台或保存歌单",
        .mcpNote: "注: Sonos 官方 MCP 工具链目前开放了歌单与收藏载入控制，硬件底层待播队列读取接口暂未向 MCP 开放。",

        // GroupManagerView
        .allSpeakers: "全部音响",
        .selectAll: "全选 (Party)",
        .deselectAll: "取消全选",
        .apply: "应用",

        // SonosController
        .tokenRefreshing: "Token 已自动刷新，重新连接中...",

        // Context Menu
        .preferences: "偏好设置...",
        .aboutAndSupport: "更新与打赏",
        .quitApp: "退出 sonosBuddy",

        // NLInputBarView
        .tapToStopRecord: "点击停止录音并执行",
        .tapToStartVoice: "点击开始语音指令输入",
        .listeningPlaceholder: "正在倾听中...",
        .inputPlaceholder: "输入或语音指令 (如: 播放林忆莲 / 音量35)...",
        .inputPlaceholderEn: "Type or speak (e.g. play Taylor Swift / volume 35)...",

        // PlaybackControlsView
        .viewQueueHint: "查看播放队列与歌单列表",
        .manageSpeakersHint: "点击管理家庭音箱分组与各音箱独立音量",
        .tapVoiceControl: "点击语音控制 (如: 播放林忆莲 / 暂停 / 音量35)",
        .tapVoiceControlEn: "Tap for voice control (e.g. play Taylor Swift / pause / volume 35)",
        .listeningFeedback: "正在倾听: %@",

        // Experimental feature
        .experimentalBadge: "实验性",
        .experimentalBadgeEn: "Experimental",
        .voiceExperimentalNote: "语音点播为实验性功能，识别准确率可能不稳定。",
        .voiceExperimentalNoteEn: "Voice control is an experimental feature. Recognition accuracy may vary.",

        // AboutUpdateView additional
        .kofiSponsorEn: "Sponsor on Ko-fi ☕",
        .kofiSponsorZh: "在 Ko-fi 上赞助 ☕",
    ]

    private let enMap: [Key: String] = [
        // MenuBarView
        .selectSpeaker: "Select Speaker",
        .sonosFavorites: "Sonos Favorites",
        .voiceControlHint: "Voice control (e.g. play Taylor Swift / pause / volume 35)",
        .voiceControlHintEn: "Voice control (e.g. play Taylor Swift / pause / volume 35)",
        .enableVoiceFirst: "Please enable voice control in Settings first",
        .stopRecording: "Tap to stop & execute",
        .previousTrack: "Previous",
        .nextTrack: "Next",
        .pause: "Pause",
        .play: "Play",
        .connected: "Sonos MCP Connected",
        .disconnected: "Disconnected",
        .todayMCP: "Today MCP: %@ requests",
        .todayMCPHint: "Total MCP requests today (auto-resets at 08:00 Beijing time, offline calculation, zero quota cost)",
        .listening: "Listening, please speak...",
        .listeningPrompt: "Listening, please speak...",

        // SettingsView
        .settingsTitle: "sonosBuddy Settings",
        .done: "Done",
        .oauthTitle: "Sonos Official Auth (OAuth 2.1)",
        .oauthDesc: "Sonos 27mcp uses native OAuth 2.1 + PKCE authorization, no need to manually apply for complex developer keys.",
        .loginWithSonos: "Sign in with Sonos Account",
        .reAuthorize: "Re-authorize with OAuth 2.1",
        .browserAuthenticating: "Authorizing in browser...",
        .enableVoice: "Enable Voice Control",
        .voiceAppleMusicOnly: "Voice control is available for Apple Music only. Once enabled, you can use voice commands to play artists, playlists, and songs from Apple Music.",
        .noAppleMusic: "Apple Music library not detected. Please add your Apple Music account in the official Sonos app before enabling this feature.",
        .speechTimeoutLabel: "Voice Input Duration",
        .speechTimeoutDesc: "After pressing the mic, listening starts. When time expires, recording stops and the command executes automatically.",
        .apikeyFirst: "Please enter your API Key first",
        .endpointInvalid: "Invalid endpoint URL format",
        .llmSuccess: "Connected! Model: %@ (%@ms)",
        .llmFailStatus: "Status %@ [%@]: %@",
        .llmNetworkFail: "Network error: %@",
        .mcpDiagnosis: "MCP Connection Diagnosis",
        .manualRefresh: "Refresh",
        .toolsFound: "%@ MCP tools discovered",
        .versionInfo: "sonosBuddy v1.0.0",
        .versionInfoEn: "sonosBuddy v1.0.0",

        // AboutUpdateView
        .aboutTitle: "About & Support",
        .currentVersion: "Current Version",
        .checkingUpdate: "Checking for updates…",
        .newVersionFound: "New version v%@ available",
        .checkFailed: "Check failed: %@",
        .noRelease: "No releases yet, you're up to date",
        .alreadyLatest: "Already up to date",
        .goToDownload: "Download",
        .recheck: "Recheck",
        .supportAuthor: "Support the Author",
        .wechatScan: "Scan with WeChat to tip",
        .kofiSponsor: "Sponsor on Ko-fi",
        .close: "Close",

        // FavoritesView
        .favoritesTitle: "Favorites",
        .myFavorites: "My Favorites",
        .favoritesCount: "%@ items",
        .noFavorites: "No Sonos favorites loaded yet",
        .noFavoritesHint: "You can save radio stations or playlists in the official Sonos app",
        .mcpNote: "Note: Sonos official MCP tools currently support playlist & favorites loading. Hardware-level queue reading is not yet available via MCP.",

        // GroupManagerView
        .allSpeakers: "All Speakers",
        .selectAll: "Select All (Party)",
        .deselectAll: "Deselect All",
        .apply: "Apply",

        // SonosController
        .tokenRefreshing: "Token auto-refreshed, reconnecting...",

        // Context Menu
        .preferences: "Preferences...",
        .aboutAndSupport: "Update & Support",
        .quitApp: "Quit sonosBuddy",

        // NLInputBarView
        .tapToStopRecord: "Tap to stop & execute",
        .tapToStartVoice: "Tap to start voice input",
        .listeningPlaceholder: "Listening...",
        .inputPlaceholder: "Type or speak (e.g. play Taylor Swift / volume 35)...",
        .inputPlaceholderEn: "Type or speak (e.g. play Taylor Swift / volume 35)...",

        // PlaybackControlsView
        .viewQueueHint: "View queue & playlists",
        .manageSpeakersHint: "Manage speaker groups & individual volumes",
        .tapVoiceControl: "Tap for voice control (e.g. play Taylor Swift / pause / volume 35)",
        .tapVoiceControlEn: "Tap for voice control (e.g. play Taylor Swift / pause / volume 35)",
        .listeningFeedback: "Listening: %@",

        // Experimental feature
        .experimentalBadge: "实验性",
        .experimentalBadgeEn: "Experimental",
        .voiceExperimentalNote: "语音点播为实验性功能，识别准确率可能不稳定。",
        .voiceExperimentalNoteEn: "Voice control is an experimental feature. Recognition accuracy may vary.",

        // AboutUpdateView additional
        .kofiSponsorEn: "Sponsor on Ko-fi ☕",
        .kofiSponsorZh: "在 Ko-fi 上赞助 ☕",
    ]
}

// MARK: - 便捷全局函数
@MainActor
func L(_ key: Localizer.Key) -> String {
    Localizer.shared.t(key)
}
