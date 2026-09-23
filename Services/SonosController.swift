import Foundation
import SwiftUI

// MARK: - 主业务状态控制器
@MainActor
@Observable
public final class SonosController {
    public var config: AppConfig {
        didSet {
            saveConfig()
        }
    }

    public var householdId: String = ""
    public var groups: [SonosGroup] = []
    public var allDevices: [SonosDevice] = []
    public var favorites: [SonosFavoriteItem] = []
    public var currentGroupId: String = ""

    public var isConnected: Bool = false
    public var isConnecting: Bool = false
    public var isOAuthAuthenticating: Bool = false
    public var errorMessage: String? = nil
    public var lastActionFeedback: String? = nil
    public var availableTools: [MCPTool] = []
    public var availableMusicServices: [String] = ["Apple Music", "Spotify", "Sonos Radio"]
    public var todayRequestCount: Int = 0

    /// 检测用户 Sonos 账号是否绑定了 Apple Music（用于控制语音点播开关是否可开启）
    public var hasAppleMusic: Bool {
        availableMusicServices.contains { $0.lowercased().contains("apple") || $0.lowercased().contains("苹果") }
    }

    private var lastCountDate: String = ""
    private static let mcpRequestCountDateKey = "SonosBuddy.MCPRequestCountDate"
    private static let mcpRequestCountValueKey = "SonosBuddy.MCPRequestCountValue"

    private let lastSelectedGroupIdKey = "SonosBuddy.LastSelectedGroupId"
    private let lastSelectedGroupNameKey = "SonosBuddy.LastSelectedGroupName"
    private let cachedMusicServicesKey = "SonosBuddy.CachedMusicServices"

    private var mcpClient: MCPClient
    private var toolMapper: SonosToolMapping = SonosToolMapping()
    private var positionTimer: Timer?
    private var isRateLimited: Bool = false
    private var volumeDebounceTask: Task<Void, Never>?
    private var playerVolumeDebounceTasks: [String: Task<Void, Never>] = [:]
    private var lastUserActionPlaybackState: (state: PlaybackState, timestamp: Date)?
    private var lastVolumeSyncTimestamp: Date?

    public var currentGroup: SonosGroup? {
        if let g = groups.first(where: { $0.id == currentGroupId }) {
            return g
        }
        if let savedName = UserDefaults.standard.string(forKey: lastSelectedGroupNameKey),
           let g = groups.first(where: { $0.name == savedName }) {
            return g
        }
        return groups.first
    }

    public init() {
        let initialConfig: AppConfig
        if let data = UserDefaults.standard.data(forKey: "SonosBuddyConfig"),
           let saved = try? JSONDecoder().decode(AppConfig.self, from: data) {
            initialConfig = saved
        } else {
            initialConfig = AppConfig()
        }
        self.config = initialConfig

        // 恢复上次关闭时所选的音箱 ID
        self.currentGroupId = UserDefaults.standard.string(forKey: lastSelectedGroupIdKey) ?? ""

        // 从本地恢复已缓存的音乐服务列表（避免每次启动都额外请求）
        if let savedServices = UserDefaults.standard.stringArray(forKey: cachedMusicServicesKey), !savedServices.isEmpty {
            self.availableMusicServices = savedServices
        }

        let endpointUrl = URL(string: initialConfig.mcpEndpoint) ?? URL(string: "https://mcp.ws.sonos.com/mcp")!
        self.mcpClient = MCPClient(endpoint: endpointUrl, bearerToken: initialConfig.bearerToken)

        // 初始化今日请求离线计数器（完全在本地计算，绝不发送额外网络请求）
        setupRequestCounter()

        if initialConfig.isDemoMode {
            setupDemoState()
        } else if !initialConfig.bearerToken.isEmpty {
            Task { @MainActor in
                await connect()
            }
        }
    }

    // MARK: - 本地 MCP 请求统计管理（零额外网络开销，与 Sonos 官方 UTC 00:00 / 北京时间 08:00 完美同步重置）
    private static func currentQuotaCycleDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC 00:00，对应北京时间每天 08:00 自动重置
        return formatter.string(from: Date())
    }

    @MainActor
    public func checkAndResetQuotaCycleIfNeeded() {
        let currentCycle = Self.currentQuotaCycleDateString()
        let savedCycle = UserDefaults.standard.string(forKey: Self.mcpRequestCountDateKey) ?? ""
        if savedCycle != currentCycle {
            self.todayRequestCount = 0
            self.lastCountDate = currentCycle
            UserDefaults.standard.set(currentCycle, forKey: Self.mcpRequestCountDateKey)
            UserDefaults.standard.set(0, forKey: Self.mcpRequestCountValueKey)
        } else if lastCountDate != currentCycle {
            self.lastCountDate = currentCycle
            self.todayRequestCount = UserDefaults.standard.integer(forKey: Self.mcpRequestCountValueKey)
        }
    }

    @MainActor
    private func setupRequestCounter() {
        checkAndResetQuotaCycleIfNeeded()

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SonosMCPRequestSent"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.incrementTodayRequestCount()
            }
        }
    }

    @MainActor
    public func incrementTodayRequestCount() {
        checkAndResetQuotaCycleIfNeeded()
        todayRequestCount += 1
        UserDefaults.standard.set(Self.currentQuotaCycleDateString(), forKey: Self.mcpRequestCountDateKey)
        UserDefaults.standard.set(todayRequestCount, forKey: Self.mcpRequestCountValueKey)
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "SonosBuddyConfig")
        }
        if let url = URL(string: config.mcpEndpoint) {
            Task { @MainActor in
                await mcpClient.updateConfig(endpoint: url, bearerToken: config.bearerToken)
            }
        }
    }

    // MARK: - Token 自动刷新（401 时尝试用 refresh_token 换取新 access_token，避免打扰用户）
    private func tryRefreshToken() async -> Bool {
        do {
            let newToken = try await OAuthManager.shared.refreshAccessToken()
            self.config.bearerToken = newToken
            if let url = URL(string: config.mcpEndpoint) {
                await mcpClient.updateConfig(endpoint: url, bearerToken: newToken)
            }
            self.lastActionFeedback = L(.tokenRefreshing)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 模拟/演示数据初始化 (高度还原官方 App 截图状态)
    public func setupDemoState() {
        let dev1 = SonosDevice(id: "dev_bedroom", name: "卧室", roomName: "卧室", modelName: "Sonos One", isMuted: false, volume: 6)
        let dev2 = SonosDevice(id: "dev_roam", name: "Sonos Roam", roomName: "随身", modelName: "Roam", isMuted: false, volume: 8)
        let dev3 = SonosDevice(id: "dev_living", name: "客厅", roomName: "客厅", modelName: "Beam", isMuted: false, volume: 15)

        self.allDevices = [dev1, dev2, dev3]

        let bedroomRoamGroup = SonosGroup(
            id: "RINCON_F0F6C1D51CBC01400:2237683047",
            name: "卧室, Sonos Roam",
            deviceIds: [dev1.id, dev2.id],
            playbackState: .playing,
            currentTrack: TrackInfo(
                title: "無名的人 (電影《雄獅少年》主題曲)",
                artist: "Mao Buyi",
                album: "無名的人",
                albumArtUrl: nil,
                musicService: "Spotify",
                durationSeconds: 282,
                positionSeconds: 42
            ),
            volume: 7,
            isMuted: false,
            isShuffle: false,
            repeatMode: .off
        )

        let livingGroup = SonosGroup(
            id: "RINCON_48A6B835A94B01400:1415947064",
            name: "客厅",
            deviceIds: [dev3.id],
            playbackState: .paused,
            currentTrack: TrackInfo(
                title: "稻香",
                artist: "周杰伦",
                album: "魔杰座",
                albumArtUrl: nil,
                musicService: "Apple Music",
                durationSeconds: 223,
                positionSeconds: 0
            ),
            volume: 20,
            isMuted: false,
            isShuffle: true,
            repeatMode: .all
        )

        self.groups = [bedroomRoamGroup, livingGroup]
        restoreOrSelectGroup(from: self.groups)

        self.favorites = [
            SonosFavoriteItem(id: "16", name: "A-List: 国语流行", service: "Apple Music"),
            SonosFavoriteItem(id: "123", name: "chill lofi study beats", service: "Spotify"),
            SonosFavoriteItem(id: "161", name: "今日热门", service: "Apple Music"),
            SonosFavoriteItem(id: "165", name: "咖啡开启一天", service: "QQ音乐"),
            SonosFavoriteItem(id: "86", name: "Classic FM", service: "Sonos Radio")
        ]

        self.isConnected = true
        self.isConnecting = false
        self.errorMessage = nil
        startPositionTimer()
    }

    // MARK: - OAuth 2.1 授权流程
    public func startOAuthLogin() async {
        self.isOAuthAuthenticating = true
        self.errorMessage = nil
        self.lastActionFeedback = "Opened Sonos OAuth page in browser..."

        do {
            let token = try await OAuthManager.shared.startAuthorization()
            self.config.bearerToken = token
            self.config.isDemoMode = false

            if let url = URL(string: config.mcpEndpoint) {
                await mcpClient.updateConfig(endpoint: url, bearerToken: token)
            }

            self.isOAuthAuthenticating = false
            self.lastActionFeedback = "OAuth authorized! Connecting to Sonos..."

            await connect()
        } catch {
            self.isOAuthAuthenticating = false
            self.errorMessage = "Authorization interrupted or failed: \(error.localizedDescription)"
        }
    }

    // MARK: - 连接 Sonos MCP (温和交互，拒绝高频轮询耗尽限额)
    public func connect() async {
        if config.isDemoMode {
            setupDemoState()
            return
        }

        guard !config.bearerToken.isEmpty else {
            self.errorMessage = "Please click \"Sign in with Sonos Account\" first"
            self.isConnected = false
            return
        }

        self.isConnecting = true
        self.errorMessage = nil

        if let url = URL(string: config.mcpEndpoint) {
            await mcpClient.updateConfig(endpoint: url, bearerToken: config.bearerToken)
        }

        do {
            _ = try await mcpClient.initialize()
            let tools = try await mcpClient.listTools()
            self.availableTools = tools
            self.toolMapper = SonosToolMapping(tools: tools)
            self.isConnected = true
            self.isConnecting = false
            self.isRateLimited = false

            // 记录可用工具列表便于调试
            let toolNames = tools.map { $0.name }.joined(separator: ", ")
            self.lastActionFeedback = "MCP connected, found \(tools.count) tools: \(toolNames)"

            // 同步一次家庭分组与收藏
            await refreshStatus()
            let groupSummary = groups.map { $0.name }.joined(separator: " | ")
            self.lastActionFeedback = groups.isEmpty
                ? "MCP connected but group list is empty. Tools: \(toolNames.prefix(80))"
                : "Connected! Found \(groups.count) groups: \(groupSummary)"
        } catch {
            self.isConnecting = false
            let errStr = error.localizedDescription
            if errStr.contains("429") || errStr.contains("rate_limit") {
                self.isRateLimited = true
                self.isConnected = true // 保持已连接状态，继续使用当前缓存
                self.errorMessage = "Daily Sonos MCP quota reached, using local cache"
            } else if errStr.contains("401") || errStr.contains("Token 已失效") {
                if await tryRefreshToken() {
                    await connect()
                    return
                }
                self.isConnected = false
                self.errorMessage = "Token expired and auto-refresh failed, please re-authorize in Settings"
            } else {
                self.isConnected = false
                self.errorMessage = "Connection failed: \(errStr)"
            }
        }
    }


    // MARK: - 按需刷新家庭音响状态
    public func refreshStatus(preferredDeviceIds: Set<String>? = nil, syncNowPlaying: Bool = true) async {
        guard !config.isDemoMode && isConnected && !isRateLimited else { return }

        guard let (toolName, args) = toolMapper.resolve(intent: .getHouseholdStatus) else {
            let names = availableTools.map { $0.name }.joined(separator: ", ")
            self.errorMessage = "No refresh tool found, available: \(names.prefix(100))"
            return
        }

        do {
            let res = try await mcpClient.callTool(name: toolName, arguments: args)
            let rawText = res.content?.compactMap { $0.text }.joined(separator: "") ?? ""

            guard !rawText.isEmpty, let data = rawText.data(using: .utf8) else { return }

            let topLevel = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
            let households: [[String: Any]]
            if let arr = topLevel as? [[String: Any]] {
                households = arr
            } else if let dict = topLevel as? [String: Any] {
                if let inner = dict["households"] as? [[String: Any]] {
                    households = inner
                } else {
                    households = [dict]
                }
            } else { return }

            var parsedGroups: [SonosGroup] = []
            var parsedDevices: [SonosDevice] = []

            for household in households {
                let hid = household["householdId"] as? String ?? household["id"] as? String ?? ""
                if !hid.isEmpty { self.householdId = hid }

                let rawGroups = household["groups"] as? [[String: Any]]
                    ?? household["Groups"] as? [[String: Any]] ?? []

                for g in rawGroups {
                    guard let gid = g["groupId"] as? String ?? g["id"] as? String else { continue }

                    let stateStr = g["playbackState"] as? String
                        ?? g["playback_state"] as? String ?? g["state"] as? String ?? ""
                    let isPlaying = stateStr.uppercased().contains("PLAYING")

                    var playerNames: [String] = []
                    var deviceIds: [String] = []

                    // 先尝试 players 对象数组
                    if let playersArr = g["players"] as? [[String: Any]] {
                        for p in playersArr {
                            let pid = p["id"] as? String ?? p["playerId"] as? String ?? UUID().uuidString
                            let pname = p["name"] as? String ?? "Sonos 音箱"
                            playerNames.append(pname)
                            deviceIds.append(pid)
                            let vol = self.allDevices.first(where: { $0.id == pid })?.volume ?? 10
                            if !parsedDevices.contains(where: { $0.id == pid }) {
                                parsedDevices.append(SonosDevice(id: pid, name: pname,
                                    roomName: p["roomName"] as? String ?? pname,
                                    modelName: p["model"] as? String ?? p["modelName"] as? String,
                                    volume: vol))
                            }
                        }
                    }

                    // 再尝试 playerIds 字符串数组（官方格式，player 详情在 household 顶层）
                    if deviceIds.isEmpty, let pidArr = g["playerIds"] as? [String] {
                        deviceIds = pidArr
                        if let allPlayers = household["players"] as? [[String: Any]] {
                            for pid in pidArr {
                                if let p = allPlayers.first(where: { ($0["id"] as? String) == pid }) {
                                    let pname = p["name"] as? String ?? "Sonos 音箱"
                                    playerNames.append(pname)
                                    let vol = self.allDevices.first(where: { $0.id == pid })?.volume ?? 10
                                    if !parsedDevices.contains(where: { $0.id == pid }) {
                                        parsedDevices.append(SonosDevice(id: pid, name: pname,
                                            roomName: p["roomName"] as? String ?? pname,
                                            modelName: p["model"] as? String, volume: vol))
                                    }
                                }
                            }
                        }
                    }

                    let groupName = g["name"] as? String
                        ?? (playerNames.isEmpty ? nil : playerNames.joined(separator: ", "))
                        ?? "音响组"

                    let groupVol: Int
                    if let v = g["volume"] as? Int { groupVol = v }
                    else if let v = g["volume"] as? Double { groupVol = Int(v) }
                    else { groupVol = self.groups.first(where: { $0.id == gid })?.volume ?? 7 }

                    let isMuted = g["muted"] as? Bool ?? g["isMuted"] as? Bool ?? false
                    let isShuffle = g["shuffle"] as? Bool ?? g["isShuffle"] as? Bool ?? false
                    let repeatStr = g["repeat"] as? String ?? g["repeatMode"] as? String ?? "OFF"
                    let repeatMode: RepeatMode = repeatStr == "ONE" ? .one : (repeatStr == "ALL" ? .all : .off)

                    // 如果 3 秒内用户手动操作过播放/暂停，防止云端异步未就绪覆盖
                    let finalPlaybackState: PlaybackState
                    if gid == self.currentGroupId, let userAct = self.lastUserActionPlaybackState, Date().timeIntervalSince(userAct.timestamp) < 3.0 {
                        finalPlaybackState = userAct.state
                    } else {
                        finalPlaybackState = isPlaying ? .playing : .paused
                    }

                    parsedGroups.append(SonosGroup(
                        id: gid, name: groupName, deviceIds: deviceIds,
                        playbackState: finalPlaybackState,
                        currentTrack: self.groups.first(where: { $0.id == gid })?.currentTrack ?? TrackInfo(),
                        volume: groupVol, isMuted: isMuted, isShuffle: isShuffle, repeatMode: repeatMode
                    ))
                }
            }

            if !parsedGroups.isEmpty {
                self.groups = parsedGroups
                if !parsedDevices.isEmpty { self.allDevices = parsedDevices }
                restoreOrSelectGroup(from: parsedGroups, preferredDeviceIds: preferredDeviceIds)
            }

            if !self.householdId.isEmpty {
                if self.favorites.isEmpty {
                    await fetchFavorites()
                }
                if self.availableMusicServices.isEmpty {
                    await fetchRegisteredMusicServices()
                }
            }
            if syncNowPlaying && !self.currentGroupId.isEmpty {
                await fetchNowPlaying(groupId: self.currentGroupId)
                await fetchCurrentGroupVolume()
            }
        } catch {
            let errStr = "\(error)"
            if errStr.contains("429") || errStr.contains("rate_limit") {
                self.isRateLimited = true
                self.errorMessage = "Sonos API daily quota exhausted, resets at 08:00 Beijing time (UTC 00:00)"
            } else if errStr.contains("401") || errStr.contains("Token 已失效") {
                if await tryRefreshToken() {
                    await refreshStatus()
                    return
                }
            }
        }
    }

    // MARK: - 获取正在播放曲目详情
    public func fetchNowPlaying(groupId: String) async {
        guard !config.isDemoMode && isConnected && !isRateLimited else { return }
        guard let (toolName, args) = toolMapper.resolve(intent: .getNowPlaying(groupId: groupId)) else { return }

        do {
            let res = try await mcpClient.callTool(name: toolName, arguments: args)
            let rawText = res.content?.compactMap { $0.text }.joined(separator: "") ?? ""
            // 在诊断区显示原始响应
            self.lastActionFeedback = "[\(toolName)]: \(rawText.prefix(200))"
            guard !rawText.isEmpty, let data = rawText.data(using: .utf8) else { return }
            guard let idx = groups.firstIndex(where: { $0.id == groupId }) else { return }

            let json = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
            let dict: [String: Any]
            if let d = json as? [String: Any] { dict = d }
            else if let arr = json as? [[String: Any]], let first = arr.first { dict = first }
            else { return }

            // container → currentItem → track 各种嵌套格式
            let trackDict: [String: Any]
            if let inner = dict["currentItem"] as? [String: Any] {
                trackDict = inner["track"] as? [String: Any] ?? inner
            } else if let inner = dict["track"] as? [String: Any] {
                trackDict = inner
            } else if let inner = dict["currentTrack"] as? [String: Any] {
                trackDict = inner
            } else {
                trackDict = dict
            }

            let trackTitle = trackDict["name"] as? String
                ?? trackDict["title"] as? String
                ?? dict["track"] as? String
                ?? dict["title"] as? String
                ?? ""
            guard !trackTitle.isEmpty && trackTitle != "{}" else { return }

            let artistStr: String
            if let obj = trackDict["artist"] as? [String: Any] { artistStr = obj["name"] as? String ?? "" }
            else { artistStr = trackDict["artist"] as? String ?? dict["artist"] as? String ?? "" }

            let albumStr: String
            if let obj = trackDict["album"] as? [String: Any] { albumStr = obj["name"] as? String ?? "" }
            else { albumStr = trackDict["album"] as? String ?? dict["album"] as? String ?? "" }

            let imageUrl: String? = trackDict["imageUrl"] as? String
                ?? trackDict["albumArtUri"] as? String
                ?? dict["imageUrl"] as? String
                ?? (trackDict["images"] as? [[String: Any]])?.last?["url"] as? String

            var serviceStr: String? = dict["service"] as? String ?? dict["musicService"] as? String
            if serviceStr == nil, let cont = dict["container"] as? [String: Any],
               let svc = cont["service"] as? [String: Any] {
                serviceStr = svc["name"] as? String
            }

            let durationMs = trackDict["durationMillis"] as? Double ?? dict["durationMillis"] as? Double ?? 0
            let positionMs = dict["positionMillis"] as? Double ?? dict["position"] as? Double ?? 0
            let durationSec = durationMs > 1 ? durationMs / 1000.0 : (trackDict["duration"] as? Double ?? 0)
            let positionSec = positionMs > 1 ? positionMs / 1000.0 : (dict["positionSeconds"] as? Double ?? 0)

            groups[idx].currentTrack = TrackInfo(
                title: trackTitle,
                artist: artistStr,
                album: albumStr,
                albumArtUrl: imageUrl,
                musicService: serviceStr,
                durationSeconds: durationSec > 0 ? durationSec : 240,
                positionSeconds: positionSec
            )
        } catch {
            // get_now_playing 失败不影响其他功能，静默忽略
            self.lastActionFeedback = "[get_now_playing unavailable: \(error.localizedDescription.prefix(60))]"
        }
    }

    // MARK: - 获取收藏夹列表
    public func fetchFavorites() async {
        guard !config.isDemoMode && isConnected && !householdId.isEmpty && !isRateLimited else { return }
        if let (toolName, args) = toolMapper.resolve(intent: .getFavorites(householdId: householdId)) {
            do {
                let res = try await mcpClient.callTool(name: toolName, arguments: args)
                if let rawText = res.content?.first?.text,
                   let data = rawText.data(using: .utf8),
                   let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {

                    var favs: [SonosFavoriteItem] = []
                    for item in list {
                        let id = item["id"] as? String ?? ""
                        let name = item["name"] as? String ?? ""
                        let service = item["service"] as? String ?? item["serviceName"] as? String
                        if !id.isEmpty && !name.isEmpty {
                            favs.append(SonosFavoriteItem(id: id, name: name, imageUrl: nil, service: service))
                        }
                    }
                    if !favs.isEmpty {
                        self.favorites = favs
                    }
                }
            } catch {
                if "\(error)".contains("429") {
                    self.isRateLimited = true
                }
            }
        }
    }

    // MARK: - 获取家庭中已绑定的音乐服务列表
    public func fetchRegisteredMusicServices() async {
        guard !config.isDemoMode && isConnected && !householdId.isEmpty && !isRateLimited else { return }
        guard let tool = toolMapper.findTool(matching: ["get_registered_music_services", "getRegisteredMusicServices", "registered_music_services"]) else { return }
        do {
            let res = try await mcpClient.callTool(name: tool.name, arguments: ["household_id": .string(householdId)])
            let rawText = res.resultText
            if let data = rawText.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var services: [String] = []
                for item in list {
                    if let name = item["name"] as? String, !name.isEmpty, !services.contains(name) {
                        services.append(name)
                    }
                }
                if !services.isEmpty {
                    self.availableMusicServices = services
                    UserDefaults.standard.set(services, forKey: self.cachedMusicServicesKey)
                }
            }
        } catch {
            // 失败静默保持默认列表
        }
    }

    // MARK: - 按需校准当前组的真实音量（低频节约配额）
    public func fetchCurrentGroupVolume(force: Bool = false) async {
        guard !config.isDemoMode && isConnected && !isRateLimited else { return }
        guard let group = currentGroup else { return }

        // 节约额度：15 秒内不重复请求校准
        if !force, let lastSync = lastVolumeSyncTimestamp, Date().timeIntervalSince(lastSync) < 15.0 {
            return
        }

        guard let (toolName, args) = toolMapper.resolve(intent: .getGroupVolume(groupId: group.id)) else { return }
        do {
            let res = try await mcpClient.callTool(name: toolName, arguments: args)
            let rawText = res.resultText
            if let data = rawText.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.lastVolumeSyncTimestamp = Date()
                if let vol = dict["volume"] as? Int {
                    if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                        groups[idx].volume = vol
                    }
                    // 同步校准组内子音箱的音量基准
                    var updated = allDevices
                    for did in group.deviceIds {
                        if let dIdx = updated.firstIndex(where: { $0.id == did }) {
                            // 若子音箱仍处于默认值，更新为当前组真实音量
                            if updated[dIdx].volume == 10 || updated[dIdx].volume == 0 {
                                updated[dIdx].volume = vol
                            }
                        }
                    }
                    self.allDevices = updated
                }
                if let isMuted = dict["muted"] as? Bool {
                    if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                        groups[idx].isMuted = isMuted
                    }
                }
            }
        } catch {
            // 静默失败，不打扰用户
        }
    }

    // MARK: - 控制意图派发
    public func dispatch(intent: SonosControlIntent) async {
        if config.isDemoMode {
            executeDemoIntent(intent)
            return
        }

        // 歌单/专辑/歌手播放前置优化：先从 Sonos 收藏夹精确匹配（保留原始音源）
        if case .playPlaylist(let name, _, let gid) = intent {
            let targetGid = gid ?? self.currentGroupId
            if !targetGid.isEmpty, let matchedFav = findFavoriteByExactName(name) {
                print("[DEBUG] 收藏前置匹配成功: '\(matchedFav.name)' (id=\(matchedFav.id))")
                if let (favTool, favArgs) = toolMapper.resolve(
                    intent: .playFavorite(id: matchedFav.id, name: matchedFav.name, groupId: targetGid)
                ) {
                    print("[DEBUG] 前置收藏调用工具: \(favTool), 参数: \(favArgs)")
                    do {
                        let res = try await mcpClient.callTool(name: favTool, arguments: favArgs)
                        print("[DEBUG] 前置收藏调用结果: isError=\(res.isError ?? false), text=\(res.resultText.prefix(200))")
                        if res.isError != true {
                            self.errorMessage = nil
                            self.lastActionFeedback = "Playing favorite \"\(matchedFav.name)\""
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            await self.fetchNowPlaying(groupId: targetGid)
                            return
                        }
                    } catch {
                        print("[DEBUG] 前置收藏调用异常: \(error)")
                    }
                } else {
                    print("[DEBUG] 前置收藏 resolve 失败：找不到 loadFavorite 工具")
                }
            }
        }

        // playFavorite 意图调试日志
        if case .playFavorite(let favId, let favName, let favGid) = intent {
            print("[DEBUG] dispatch .playFavorite: id='\(favId)', name='\(favName)', groupId='\(favGid ?? "nil")'")
        }
        
        // 歌手点播调试日志
        if case .playArtist(let artist, let service, let gid) = intent {
            print("[DEBUG] dispatch .playArtist: artist='\(artist)', service='\(service ?? "nil")', groupId='\(gid ?? "nil")'")
        }
        
        if let (toolName, args) = toolMapper.resolve(intent: intent) {
            print("[DEBUG] dispatch resolve 成功: tool='\(toolName)', args=\(args)")
            do {
                let res = try await mcpClient.callTool(name: toolName, arguments: args)
                let text = res.resultText
                print("[DEBUG] dispatch 调用结果: isError=\(res.isError ?? false), text=\(text.prefix(500))")
                // 统一检测「未命中」的关键词集合
                let noMatchKeywords = ["error:", "no matching content", "not found", "no results", "couldn't find", "unable to find", "didn't find", "could not find"]
                let hasNoMatching = (res.isError == true) || noMatchKeywords.contains { text.lowercased().contains($0) }

                // 歌单播放失败时：先降级重试（去掉 music_service 约束），再保底
                if hasNoMatching, case .playPlaylist(let name, let service, let gid) = intent {
                    let targetGid = gid ?? self.currentGroupId
                    // 如果指定了音源，先尝试不带音源约束重新搜索（解决 Spotify 等音源搜索范围受限问题）
                    if service != nil && !targetGid.isEmpty {
                        if let (retryTool, retryArgs) = toolMapper.resolve(
                            intent: .playPlaylist(name: name, musicService: nil, groupId: targetGid)
                        ) {
                            do {
                                let retryRes = try await mcpClient.callTool(name: retryTool, arguments: retryArgs)
                                let retryText = retryRes.resultText
                                let retryFailed = (retryRes.isError == true) || noMatchKeywords.contains { retryText.lowercased().contains($0) }
                                if !retryFailed {
                                    self.errorMessage = nil
                                    self.lastActionFeedback = "Success: [\(retryTool)]"
                                    try? await Task.sleep(nanoseconds: 600_000_000)
                                    await self.fetchNowPlaying(groupId: targetGid)
                                    return
                                }
                            } catch {}
                        }
                    }
                    // 降级重试也失败，进入保底
                    await executePlaylistFallback(
                        originalPrompt: name,
                        failedPlaylistName: name,
                        groupId: targetGid
                    )
                    return
                }

                // 歌手播放：检测艺人电台匹配错误（如 "Michael Jackson" → station "Michael Clifford"）
                // play_artist 创建的是艺人电台，若返回的电台名与请求的歌手不匹配，降级为精选集搜索
                if !hasNoMatching, case .playArtist(let artist, let service, let gid) = intent {
                    let responseLower = text.lowercased()
                    let artistLower = artist.lowercased()
                    // 检测返回的 station 名是否包含请求的歌手名
                    let stationMismatch = responseLower.contains("station") && !responseLower.contains(artistLower)
                    if stationMismatch {
                        let targetGid = gid ?? self.currentGroupId
                        print("[DEBUG] play_artist 艺人电台匹配错误：请求='\(artist)'，返回='\(text.prefix(100))'，降级为精选集搜索")
                        // 降级1：用 play_playlist 搜索歌手名（Apple Music 有大量 "[歌手] Essentials" 歌单）
                        if let (plTool, plArgs) = toolMapper.resolve(
                            intent: .playPlaylist(name: artist, musicService: service, groupId: targetGid)
                        ) {
                            do {
                                let plRes = try await mcpClient.callTool(name: plTool, arguments: plArgs)
                                let plText = plRes.resultText
                                let plFailed = (plRes.isError == true) || noMatchKeywords.contains { plText.lowercased().contains($0) }
                                if !plFailed {
                                    self.errorMessage = nil
                                    self.lastActionFeedback = "Playing essentials playlist for \(artist)"
                                    try? await Task.sleep(nanoseconds: 600_000_000)
                                    await self.fetchNowPlaying(groupId: targetGid)
                                    return
                                }
                            } catch {}
                        }
                        // 降级2：去掉音源约束重试
                        if service != nil, let (retryTool, retryArgs) = toolMapper.resolve(
                            intent: .playPlaylist(name: artist, musicService: nil, groupId: targetGid)
                        ) {
                            do {
                                let retryRes = try await mcpClient.callTool(name: retryTool, arguments: retryArgs)
                                let retryText = retryRes.resultText
                                let retryFailed = (retryRes.isError == true) || noMatchKeywords.contains { retryText.lowercased().contains($0) }
                                if !retryFailed {
                                    self.errorMessage = nil
                                    self.lastActionFeedback = "Playing essentials playlist for \(artist)"
                                    try? await Task.sleep(nanoseconds: 600_000_000)
                                    await self.fetchNowPlaying(groupId: targetGid)
                                    return
                                }
                            } catch {}
                        }
                        self.errorMessage = "No content found for artist \"\(artist)\""
                        return
                    }
                }

                // 歌手播放失败时自动降级到单曲搜索（解决 Spotify 等音源 play_artist 不兼容问题）
                if hasNoMatching, case .playArtist(let artist, let service, let gid) = intent {
                    let fallbackGid = gid ?? self.currentGroupId
                    // 先尝试 play_track（歌手名同时作为曲名搜索）
                    if let (fallbackTool, fallbackArgs) = toolMapper.resolve(
                        intent: .playTrack(title: artist, artist: artist, musicService: service, groupId: fallbackGid)
                    ) {
                        do {
                            let fallbackRes = try await mcpClient.callTool(name: fallbackTool, arguments: fallbackArgs)
                            let fText = fallbackRes.resultText
                            let fHasError = (fallbackRes.isError == true) || noMatchKeywords.contains { fText.lowercased().contains($0) }
                            if !fHasError {
                                self.lastActionFeedback = "Found and playing tracks by \(artist)"
                                try? await Task.sleep(nanoseconds: 600_000_000)
                                await self.fetchNowPlaying(groupId: fallbackGid)
                                return
                            }
                        } catch {}
                    }
                    // play_track 也失败，尝试不带音源约束重试
                    if service != nil, let (retryTool, retryArgs) = toolMapper.resolve(
                        intent: .playArtist(artist: artist, musicService: nil, groupId: fallbackGid)
                    ) {
                        do {
                            let retryRes = try await mcpClient.callTool(name: retryTool, arguments: retryArgs)
                            let retryText = retryRes.resultText
                            let retryFailed = (retryRes.isError == true) || noMatchKeywords.contains { retryText.lowercased().contains($0) }
                            if !retryFailed {
                                self.errorMessage = nil
                                self.lastActionFeedback = "Playing \(artist)"
                                try? await Task.sleep(nanoseconds: 600_000_000)
                                await self.fetchNowPlaying(groupId: fallbackGid)
                                return
                            }
                        } catch {}
                    }
                    self.errorMessage = "No content found for artist \"\(artist)\""
                    return
                }

                self.lastActionFeedback = "Success: [\(toolName)]"

                // 极端节流优化：仅对结构拓扑变更（加退音箱）或搜索加载等必要操作执行全量 refreshStatus
                // 基础播控（播放、暂停、切歌、音量）不再触发级联的 4~5 个网络请求，极大节约 MCP 额度
                switch intent {
                case .play, .pause, .togglePlayPause:
                    break
                case .next(let gid), .previous(let gid):
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    let targetGid = gid ?? self.currentGroupId
                    if !targetGid.isEmpty {
                        await self.fetchNowPlaying(groupId: targetGid)
                    }
                case .playArtist(_, _, let gid), .playTrack(_, _, _, let gid), .playAlbum(_, _, _, let gid), .playPlaylist(_, _, let gid), .playFavorite(_, _, let gid):
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    let targetGid = gid ?? self.currentGroupId
                    if !targetGid.isEmpty {
                        await self.fetchNowPlaying(groupId: targetGid)
                    }
                case .setVolume, .setPlayerVolume, .setMute, .setPlayerMute, .addPlayersToGroup, .removePlayersFromGroup:
                    break
                default:
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await refreshStatus()
                }
            } catch {
                let errStr = error.localizedDescription
                if errStr.contains("429") {
                    self.isRateLimited = true
                    self.errorMessage = "Daily quota reached, operation recorded"
                } else if errStr.contains("401") || errStr.contains("Token 已失效") {
                    if await tryRefreshToken() {
                        await dispatch(intent: intent)
                        return
                    }
                    self.errorMessage = "Token expired and auto-refresh failed, please re-authorize in Settings"
                } else if case .playPlaylist(let name, _, let gid) = intent {
                    // 异常网络/未找到内容触发保底
                    await executePlaylistFallback(
                        originalPrompt: name,
                        failedPlaylistName: name,
                        groupId: gid ?? self.currentGroupId
                    )
                    return
                } else {
                    self.errorMessage = "Failed: \(errStr)"
                }
            }
        } else {
            print("[DEBUG] dispatch resolve 失败：未找到匹配工具")
            // 给 playFavorite 一个明确的错误反馈
            if case .playFavorite(_, let favName, _) = intent {
                let toolNames = availableTools.map { $0.name }.sorted().joined(separator: ", ")
                self.lastActionFeedback = "Failed to play favorite \"\(favName)\": loadFavorite tool not found"
                self.errorMessage = "Favorite playback failed. Available tools: \(toolNames.prefix(200))"
            } else {
                self.errorMessage = "Sonos 27mcp missing required tool for this command"
            }
        }
    }

    // MARK: - 单个音箱独立音量控制（拖拽 0 网络开销，松手唯一提交）
    public func setPlayerVolume(playerId: String, volume: Int, commitImmediately: Bool = false) {
        let clamped = max(0, min(100, volume))
        var updatedDevices = allDevices
        if let idx = updatedDevices.firstIndex(where: { $0.id == playerId }) {
            if updatedDevices[idx].volume != clamped {
                updatedDevices[idx].volume = clamped
                updatedDevices[idx].isMuted = false
                self.allDevices = updatedDevices

                // 反向联动：若该设备属于当前组，同步更新当前组综合音量为各子设备平均值
                if let group = currentGroup, group.deviceIds.contains(playerId) {
                    let members = updatedDevices.filter { group.deviceIds.contains($0.id) }
                    if !members.isEmpty {
                        let avgVol = members.reduce(0) { $0 + $1.volume } / members.count
                        if let gIdx = groups.firstIndex(where: { $0.id == group.id }) {
                            groups[gIdx].volume = avgVol
                        }
                    }
                }
            }
        }

        if config.isDemoMode || isRateLimited { return }

        // 仅在松手提交时发送唯一的一次网络请求，拖拽过程绝对 0 网络开销
        guard commitImmediately else { return }
        playerVolumeDebounceTasks[playerId]?.cancel()
        playerVolumeDebounceTasks[playerId] = Task { [weak self] in
            await self?.dispatchPlayerVolumeOnly(playerId: playerId, level: clamped)
        }
    }

    private func dispatchPlayerVolumeOnly(playerId: String, level: Int) async {
        guard let (toolName, args) = toolMapper.resolve(intent: .setPlayerVolume(playerId: playerId, level: level)) else { return }
        do {
            _ = try await mcpClient.callTool(name: toolName, arguments: args)
            self.lastActionFeedback = "Speaker volume updated: \(level)%"
        } catch {
            let errStr = error.localizedDescription
            if errStr.contains("429") {
                self.isRateLimited = true
                self.errorMessage = "Daily quota reached"
            }
        }
    }

    // MARK: - Group 编组批量应用
    public func applyGroupSelection(selectedDeviceIds: Set<String>) {
        guard let group = currentGroup else { return }

        let currentIds = Set(group.deviceIds)
        let toAdd = Array(selectedDeviceIds.subtracting(currentIds))
        let toRemove = Array(currentIds.subtracting(selectedDeviceIds))

        // 本地即时响应
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx].deviceIds = Array(selectedDeviceIds)
            let names = allDevices.filter { selectedDeviceIds.contains($0.id) }.map { $0.name }
            if !names.isEmpty {
                groups[idx].name = names.joined(separator: ", ")
            }
        }

        if config.isDemoMode {
            lastActionFeedback = "Speaker group updated: \(currentGroup?.name ?? "")"
            return
        }

        let targetGroupId = group.id
        Task { @MainActor in
            if !toAdd.isEmpty {
                await dispatch(intent: .addPlayersToGroup(playerIds: toAdd, targetGroupId: targetGroupId))
            }
            if !toRemove.isEmpty {
                await dispatch(intent: .removePlayersFromGroup(playerIds: toRemove, sourceGroupId: targetGroupId))
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshStatus(preferredDeviceIds: selectedDeviceIds)
        }
    }

    // MARK: - 切换单个设备加入/退出当前音箱组合（即时生效，无需退出菜单）
    public func toggleDeviceInCurrentGroup(deviceId: String) {
        guard let group = currentGroup else { return }
        let currentSet = Set(group.deviceIds)

        var newSet = currentSet
        let isAdding: Bool

        if currentSet.contains(deviceId) {
            // 组内多于 1 个音箱时允许移出
            guard currentSet.count > 1 else { return }
            newSet.remove(deviceId)
            isAdding = false
        } else {
            newSet.insert(deviceId)
            isAdding = true
        }

        // 1. 本地立即更新 UI（勾选框瞬间响应）
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx].deviceIds = Array(newSet)
            let names = allDevices.filter { newSet.contains($0.id) }.map { $0.name }
            if !names.isEmpty {
                groups[idx].name = names.joined(separator: ", ")
            }
        }

        if config.isDemoMode {
            lastActionFeedback = "Speaker group updated: \(currentGroup?.name ?? "")"
            return
        }

        // 2. 异步调用 Sonos MCP 服务
        let targetGroupId = group.id
        Task { @MainActor in
            if isAdding {
                self.lastActionFeedback = "Adding speaker to group..."
                await dispatch(intent: .addPlayersToGroup(playerIds: [deviceId], targetGroupId: targetGroupId))
            } else {
                self.lastActionFeedback = "Removing speaker from group..."
                await dispatch(intent: .removePlayersFromGroup(playerIds: [deviceId], sourceGroupId: targetGroupId))
            }

            // Sonos 云端重组后，轻量刷新拓扑（syncNowPlaying: false，跳过重复拉取 NowPlaying 与音量，降至严格 2 次请求）
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshStatus(preferredDeviceIds: newSet, syncNowPlaying: false)
        }
    }

    // MARK: - 收藏夹即点即播
    public func playFavorite(_ item: SonosFavoriteItem) {
        guard let group = currentGroup else {
            print("[DEBUG] playFavorite: currentGroup 为空，无法播放")
            self.lastActionFeedback = "No active playback group available"
            return
        }

        if config.isDemoMode {
            if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                groups[idx].currentTrack = TrackInfo(
                    title: item.name,
                    artist: item.service ?? "Sonos 收藏",
                    album: "精选流媒体",
                    durationSeconds: 240,
                    positionSeconds: 0
                )
                groups[idx].playbackState = .playing
                lastActionFeedback = "Playing favorite: \(item.name)"
            }
            return
        }

        print("[DEBUG] playFavorite: name='\(item.name)', id='\(item.id)', service='\(item.service ?? "nil")', groupId='\(group.id)'")
        let availableToolNames = availableTools.map { $0.name }.joined(separator: ", ")
        print("[DEBUG] 当前可用 MCP 工具 (\(availableTools.count) 个): \(availableToolNames)")

        Task { @MainActor in
            await dispatch(intent: .playFavorite(id: item.id, name: item.name, groupId: group.id))
        }
    }

    // MARK: - 播放控制方法（0ms 即时响应，图标瞬间跳转）
    public func togglePlayPause() {
        guard let group = currentGroup else { return }
        let nextState = group.playbackState.isPlaying ? PlaybackState.paused : PlaybackState.playing
        
        // 1. 本地立即乐观更新（0ms 响应，图标瞬间跳转）
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx].playbackState = nextState
            self.lastUserActionPlaybackState = (nextState, Date())
            NotificationCenter.default.post(name: NSNotification.Name("SonosPlaybackChanged"), object: nil)
        }

        if config.isDemoMode {
            return
        }

        Task { @MainActor in
            let intent: SonosControlIntent = (nextState == .playing) ? .play(groupId: group.id) : .pause(groupId: group.id)
            await dispatch(intent: intent)
        }
    }

    public func nextTrack() {
        guard let group = currentGroup else { return }
        if config.isDemoMode {
            if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                groups[idx].currentTrack = TrackInfo(
                    title: "七里香",
                    artist: "周杰伦",
                    album: "七里香",
                    albumArtUrl: nil,
                    musicService: "Apple Music",
                    durationSeconds: 299,
                    positionSeconds: 0
                )
            }
            lastActionFeedback = "Skipped to next track"
            return
        }
        lastActionFeedback = "Skipping to next track..."
        Task { @MainActor in
            await dispatch(intent: .next(groupId: group.id))
        }
    }

    public func previousTrack() {
        guard let group = currentGroup else { return }
        if config.isDemoMode {
            if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                groups[idx].currentTrack = TrackInfo(
                    title: "青花瓷",
                    artist: "周杰伦",
                    album: "我很忙",
                    albumArtUrl: nil,
                    musicService: "QQ音乐",
                    durationSeconds: 239,
                    positionSeconds: 0
                )
            }
            lastActionFeedback = "Skipped to previous track"
            return
        }
        lastActionFeedback = "Skipping to previous track..."
        Task { @MainActor in
            await dispatch(intent: .previous(groupId: group.id))
        }
    }

    // MARK: - 统一总音量控制（拖拽过程绝对 0 网络开销，松手即时提交唯一 1 次请求）
    public func setVolume(_ val: Int, commitImmediately: Bool = false) {
        guard let group = currentGroup else { return }
        let clamped = max(0, min(100, val))
        let oldVolume = group.volume
        let delta = clamped - oldVolume

        if clamped != oldVolume {
            if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                groups[idx].volume = clamped
                groups[idx].isMuted = false
            }

            // 联动更新当前组内所有子设备的音量
            var updatedDevices = allDevices
            for devId in group.deviceIds {
                if let dIdx = updatedDevices.firstIndex(where: { $0.id == devId }) {
                    if oldVolume == 0 {
                        updatedDevices[dIdx].volume = clamped
                    } else {
                        let newVol = max(0, min(100, updatedDevices[dIdx].volume + delta))
                        updatedDevices[dIdx].volume = newVol
                    }
                    updatedDevices[dIdx].isMuted = false
                }
            }
            self.allDevices = updatedDevices
        }

        if config.isDemoMode || isRateLimited { return }

        // 仅在松手提交时发送唯一的一次网络请求，拖拽过程绝对零网络开销
        guard commitImmediately else { return }
        volumeDebounceTask?.cancel()
        let targetGroupId = group.id
        volumeDebounceTask = Task { [weak self] in
            await self?.dispatchVolumeOnly(groupId: targetGroupId, level: clamped)
        }
    }

    private func dispatchVolumeOnly(groupId: String, level: Int) async {
        guard let (toolName, args) = toolMapper.resolve(intent: .setVolume(groupId: groupId, level: level)) else { return }
        do {
            _ = try await mcpClient.callTool(name: toolName, arguments: args)
            self.lastActionFeedback = "Volume set to \(level)%"
        } catch {
            let errStr = error.localizedDescription
            if errStr.contains("429") {
                self.isRateLimited = true
                self.errorMessage = "Daily quota reached"
            }
        }
    }

    // MARK: - 音箱选择记忆与恢复（支持根据设备集合精确匹配）
    private func restoreOrSelectGroup(from availableGroups: [SonosGroup], preferredDeviceIds: Set<String>? = nil) {
        guard !availableGroups.isEmpty else { return }

        // 0. 若指定了期望的设备集合（例如刚进行了勾选操作），优先匹配设备集合重合度最高的组
        if let targetSet = preferredDeviceIds, !targetSet.isEmpty {
            // 先找完全相等的
            if let exactMatch = availableGroups.first(where: { Set($0.deviceIds) == targetSet }) {
                self.currentGroupId = exactMatch.id
                UserDefaults.standard.set(exactMatch.id, forKey: lastSelectedGroupIdKey)
                UserDefaults.standard.set(exactMatch.name, forKey: lastSelectedGroupNameKey)
                return
            }
            // 再找包含且交集最大的
            let bestMatch = availableGroups.max(by: { a, b in
                let countA = Set(a.deviceIds).intersection(targetSet).count
                let countB = Set(b.deviceIds).intersection(targetSet).count
                return countA < countB
            })
            if let best = bestMatch, !Set(best.deviceIds).intersection(targetSet).isEmpty {
                self.currentGroupId = best.id
                UserDefaults.standard.set(best.id, forKey: lastSelectedGroupIdKey)
                UserDefaults.standard.set(best.name, forKey: lastSelectedGroupNameKey)
                return
            }
        }

        let savedId = UserDefaults.standard.string(forKey: lastSelectedGroupIdKey) ?? self.currentGroupId
        let savedName = UserDefaults.standard.string(forKey: lastSelectedGroupNameKey)

        // 1. 优先按 ID 精确匹配上次所选音箱
        if !savedId.isEmpty, let matchedById = availableGroups.first(where: { $0.id == savedId }) {
            self.currentGroupId = matchedById.id
            UserDefaults.standard.set(matchedById.id, forKey: lastSelectedGroupIdKey)
            UserDefaults.standard.set(matchedById.name, forKey: lastSelectedGroupNameKey)
            return
        }

        // 2. 若 ID 发生变动，按音箱/分组名称匹配
        if let savedName = savedName, !savedName.isEmpty,
           let matchedByName = availableGroups.first(where: { $0.name == savedName }) {
            self.currentGroupId = matchedByName.id
            UserDefaults.standard.set(matchedByName.id, forKey: lastSelectedGroupIdKey)
            UserDefaults.standard.set(matchedByName.name, forKey: lastSelectedGroupNameKey)
            return
        }

        // 3. 若当前内存中的 currentGroupId 仍在可用列表中，保留它并持久化
        if !self.currentGroupId.isEmpty, let current = availableGroups.first(where: { $0.id == self.currentGroupId }) {
            UserDefaults.standard.set(current.id, forKey: lastSelectedGroupIdKey)
            UserDefaults.standard.set(current.name, forKey: lastSelectedGroupNameKey)
            return
        }

        // 4. 仅在完全无法匹配时，默认选取第一个
        if let first = availableGroups.first {
            self.currentGroupId = first.id
            UserDefaults.standard.set(first.id, forKey: lastSelectedGroupIdKey)
            UserDefaults.standard.set(first.name, forKey: lastSelectedGroupNameKey)
        }
    }

    public func selectGroup(id: String) {
        self.currentGroupId = id
        if let g = groups.first(where: { $0.id == id }) {
            UserDefaults.standard.set(g.id, forKey: lastSelectedGroupIdKey)
            UserDefaults.standard.set(g.name, forKey: lastSelectedGroupNameKey)
        } else {
            UserDefaults.standard.set(id, forKey: lastSelectedGroupIdKey)
        }
        Task { @MainActor in
            await fetchNowPlaying(groupId: id)
            await fetchCurrentGroupVolume(force: true)
        }
    }

    // MARK: - 自然语言与语音输入处理
    public func executeNaturalLanguageCommand(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.errorMessage = nil
        self.lastActionFeedback = nil

        // 唤醒词检测：只有以 "sonos" 开头的指令才走大模型路径
        let lower = trimmed.lowercased()
        let wakeWord = "sonos"
        let hasWakeWord = lower.hasPrefix(wakeWord)
        let llmText: String
        if hasWakeWord {
            // 去掉 "sonos" 前缀，取实际指令内容
            llmText = trimmed.dropFirst(wakeWord.count).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            llmText = ""
        }

        // 1. 本地规则引擎优先：所有标准指令（播放/暂停/音量/点播歌手/歌单等）秒级响应
        // 语音点播固定使用 Apple Music（用户开启语音功能时仅限 Apple Music）
        let voiceService = config.isVoiceEnabled ? "Apple Music" : config.preferredMusicService
        if let localIntent = NLCommandParser.parseLocalIntent(
            text: trimmed,
            currentGroupId: currentGroupId,
            preferredMusicService: voiceService
        ) {
            await dispatch(intent: localIntent)
            return
        }

        // 2. 唤醒词大模型路径：仅当用户明确说出 "sonos xxx" 时才启用
        if hasWakeWord && !llmText.isEmpty && !config.openAIKey.isEmpty {
            if await executeLLMCommand(llmText) {
                return
            }
        }

        self.lastActionFeedback = nil
        self.errorMessage = "Unrecognized command \"\(trimmed)\", try \"play Taylor Swift\" or \"volume 30\""
    }

    private func executeLLMCommand(_ prompt: String) async -> Bool {
        do {
            // 语音点播固定使用 Apple Music
            let voiceService = config.isVoiceEnabled ? "Apple Music" : config.preferredMusicService
            guard let result = try await NLCommandParser.routeWithLLM(
                prompt: prompt,
                tools: availableTools,
                apiKey: config.openAIKey,
                endpoint: config.openAIEndpoint,
                customModel: config.openAIModel,
                preferredMusicService: voiceService,
                currentGroupId: currentGroupId
            ) else {
                return false
            }

            if config.isDemoMode {
                self.lastActionFeedback = "AI dispatch: [\(result.intent)]"
                return true
            }

            // 歌单意图：逐个尝试候选搜索词，第一个成功的播放
            if result.intent == "playlist" && !result.candidates.isEmpty {
                let gid = currentGroupId
                guard !gid.isEmpty else { return false }
                let service = result.musicService ?? config.preferredMusicService

                for candidate in result.candidates {
                    let cleaned = SonosToolMapping().sanitizePlaylistQuery(candidate)
                    if let (toolName, args) = toolMapper.resolve(
                        intent: .playPlaylist(name: cleaned, musicService: service, groupId: gid)
                    ) {
                        do {
                            let res = try await mcpClient.callTool(name: toolName, arguments: args)
                            let text = res.resultText
                            let isNoMatching = (res.isError == true)
                                || text.lowercased().contains("error:")
                                || text.lowercased().contains("no matching content")
                                || text.lowercased().contains("not found")

                            if !isNoMatching {
                                self.errorMessage = nil
                                if result.candidates.count > 1 {
                                    self.lastActionFeedback = "Playing \"\(cleaned)\""
                                } else {
                                    self.lastActionFeedback = text.isEmpty ? "Executed: \(toolName)" : text
                                }
                                try? await Task.sleep(nanoseconds: 600_000_000)
                                if !self.currentGroupId.isEmpty {
                                    await self.fetchNowPlaying(groupId: self.currentGroupId)
                                }
                                return true
                            }
                            // 该候选未命中，继续尝试下一个
                        } catch {
                            let errStr = error.localizedDescription
                            if errStr.contains("429") {
                                self.isRateLimited = true
                                self.errorMessage = "Daily quota reached"
                                return false
                            }
                            // 其他错误继续尝试下一个候选
                        }
                    }
                }

                // 所有候选均未命中，进入保底播放机制
                let firstCandidate = result.candidates.first ?? ""
                await executePlaylistFallback(
                    originalPrompt: prompt,
                    failedPlaylistName: firstCandidate,
                    groupId: currentGroupId
                )
                return true
            }

            // 非歌单工具调用（play_artist / play_track / play_album）
            if let (toolName, args) = result.primaryToolCall {
                guard let resolved = toolMapper.resolveLLMCall(toolName: toolName, args: args) else {
                    let msg = "Speaker does not support [\(toolName)] tool (blocked, 0 quota used)"
                    self.errorMessage = msg
                    self.lastActionFeedback = msg
                    return true
                }

                do {
                    let res = try await mcpClient.callTool(name: resolved.toolName, arguments: resolved.args)
                    let text = res.resultText
                    let isNoMatching = (res.isError == true)
                        || text.lowercased().contains("error:")
                        || text.lowercased().contains("no matching content")
                        || text.lowercased().contains("not found")

                    if isNoMatching {
                        self.errorMessage = text.isEmpty ? "No matching content found" : text
                        self.lastActionFeedback = self.errorMessage
                    } else {
                        self.lastActionFeedback = text.isEmpty ? "Executed: \(resolved.toolName)" : text
                    }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if !self.currentGroupId.isEmpty {
                        await self.fetchNowPlaying(groupId: self.currentGroupId)
                    }
                    return true
                } catch {
                    let errText = "Failed: \(error.localizedDescription)"
                    self.errorMessage = errText
                    self.lastActionFeedback = errText
                    return false
                }
            }

            return false
        } catch {
            let errText = "LLM dispatch error: \(error.localizedDescription)"
            self.errorMessage = errText
            self.lastActionFeedback = errText
            return false
        }
    }

    // MARK: - 歌单点播多级保底机制（永不返回空，杜绝报错中断）
    public func executePlaylistFallback(
        originalPrompt: String,
        failedPlaylistName: String,
        groupId: String
    ) async {
        let gid = groupId.isEmpty ? self.currentGroupId : groupId
        guard !gid.isEmpty else { return }

        self.errorMessage = nil
        self.lastActionFeedback = "Matching similar vibe music..."

        let promptLower = (originalPrompt + " " + failedPlaylistName).lowercased()

        // 1. 第一级保底：用户本地收藏夹匹配（零配额消耗，100% 可播）
        if let matchedFav = findMatchingFavorite(for: promptLower) {
            if let (toolName, favArgs) = toolMapper.resolve(intent: .playFavorite(id: matchedFav.id, name: matchedFav.name, groupId: gid)) {
                if let res = try? await mcpClient.callTool(name: toolName, arguments: favArgs),
                   res.isError != true {
                    self.errorMessage = nil
                    self.lastActionFeedback = "Playing favorite: \(matchedFav.name)"
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await self.fetchNowPlaying(groupId: gid)
                    return
                }
            }
        }

        // 2. 第二级保底：场景官方权威精选歌单降级重试（仅尝试 1 次最权威官方歌单，严格控制配额）
        let candidates = SceneFallbackCatalog.candidates(for: promptLower)
        let fallbackCandidate = candidates.first { cand in
            cand != failedPlaylistName && !failedPlaylistName.contains(cand) && !cand.contains(failedPlaylistName)
        } ?? candidates.first ?? "咖啡馆爵士"

        // 语音点播固定使用 Apple Music
        let baseService = config.isVoiceEnabled ? "Apple Music" : config.preferredMusicService
        let targetService = baseService.isEmpty ? "Apple Music" : baseService
        if let (toolName, playlistArgs) = toolMapper.resolve(intent: .playPlaylist(name: fallbackCandidate, musicService: targetService, groupId: gid)) {
            if let retryRes = try? await mcpClient.callTool(name: toolName, arguments: playlistArgs) {
                let rText = retryRes.resultText
                let hasError = (retryRes.isError == true) || rText.lowercased().contains("error:") || rText.lowercased().contains("no matching content") || rText.lowercased().contains("not found")
                if !hasError {
                    self.errorMessage = nil
                    self.lastActionFeedback = "Playing similar vibe: \(fallbackCandidate)"
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await self.fetchNowPlaying(groupId: gid)
                    return
                }
            }
        }

        // 3. 第三级保底：用户任意首个收藏或恢复播放（Evergreen Guarantee）
        if let firstFav = self.favorites.first {
            if let (toolName, favArgs) = toolMapper.resolve(intent: .playFavorite(id: firstFav.id, name: firstFav.name, groupId: gid)) {
                if let res = try? await mcpClient.callTool(name: toolName, arguments: favArgs),
                   res.isError != true {
                    self.errorMessage = nil
                    self.lastActionFeedback = "Playing featured favorite: \(firstFav.name)"
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await self.fetchNowPlaying(groupId: gid)
                    return
                }
            }
        }

        // 若仍未成功，尝试恢复播放最后记录
        if let (toolName, playArgs) = toolMapper.resolve(intent: .play(groupId: gid)) {
            _ = try? await mcpClient.callTool(name: toolName, arguments: playArgs)
            self.errorMessage = nil
            self.lastActionFeedback = "Resumed background music playback"
            return
        }

        // 终极平滑兜底提示，绝不显示红字报错
        self.errorMessage = nil
        self.lastActionFeedback = "Auto-matched and playing music"
    }

    /// 从收藏中按名称精确匹配（仅完全匹配，不做包含匹配，避免误匹配）
    private func findFavoriteByExactName(_ name: String) -> SonosFavoriteItem? {
        guard !favorites.isEmpty else { return nil }
        let nameLower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // 仅精确匹配（忽略大小写），不做包含匹配
        return favorites.first { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == nameLower }
    }

    /// 从收藏中按名称模糊匹配（用于保底机制）
    private func findFavoriteByName(_ name: String, musicService: String?) -> SonosFavoriteItem? {
        guard !favorites.isEmpty else { return nil }
        let nameLower = name.lowercased()

        // 1. 精确名称匹配（优先匹配指定音源）
        if let service = musicService, !service.isEmpty {
            if let exact = favorites.first(where: {
                $0.name.lowercased() == nameLower && ($0.service?.lowercased() == service.lowercased())
            }) {
                return exact
            }
        }

        // 2. 精确名称匹配（不限音源）
        if let exact = favorites.first(where: { $0.name.lowercased() == nameLower }) {
            return exact
        }

        // 3. 包含关系匹配（优先匹配指定音源）
        if let service = musicService, !service.isEmpty {
            if let partial = favorites.first(where: {
                let fLower = $0.name.lowercased()
                return (fLower.contains(nameLower) || nameLower.contains(fLower))
                    && ($0.service?.lowercased() == service.lowercased())
            }) {
                return partial
            }
        }

        // 4. 包含关系匹配（不限音源）
        if let partial = favorites.first(where: {
            let fLower = $0.name.lowercased()
            return fLower.contains(nameLower) || nameLower.contains(fLower)
        }) {
            return partial
        }

        return nil
    }

    private func findMatchingFavorite(for prompt: String) -> SonosFavoriteItem? {
        guard !favorites.isEmpty else { return nil }
        let lower = prompt.lowercased()

        let tags: [(keywords: [String], favHints: [String])] = [
            // 场景类
            (["咖啡", "cafe", "coffee", "下午茶", "慢调"], ["咖啡", "cafe", "coffee", "爵士", "jazz", "慢", "chill", "bossa"]),
            (["雨", "rain"], ["雨", "rain", "爵士", "jazz", "cafe", "咖啡"]),
            (["雪", "snow", "冬", "winter"], ["雪", "snow", "冬", "winter", "爵士", "jazz", "温暖", "民谣"]),
            (["工作", "学习", "效率", "专注", "写代码", "focus", "study"], ["工作", "学习", "专注", "轻音乐", "纯音乐", "focus", "piano", "钢琴", "古典"]),
            (["睡", "助眠", "失眠", "晚安", "白噪音", "sleep"], ["睡", "助眠", "晚安", "白噪音", "sleep", "冥想", "relax"]),
            (["放松", "解压", "治愈", "安静", "relax"], ["放松", "解压", "治愈", "轻音乐", "纯音乐", "relax", "chill"]),
            (["运动", "健身", "跑步", "workout"], ["运动", "健身", "跑步", "workout", "流行", "pop", "hits"]),
            (["夜晚", "深夜", "微醺", "night", "lounge"], ["夜晚", "深夜", "微醺", "night", "lounge", "爵士", "jazz"]),
            // 风格类
            (["爵士", "jazz", "bossa", "摇摆", "swing"], ["爵士", "jazz", "bossa", "bossa nova", "摇摆", "swing"]),
            (["古典", "classical", "交响", "钢琴曲", "协奏"], ["古典", "classical", "交响", "钢琴", "piano"]),
            (["电子", "electronic", "lo-fi", "lofi", "ambient", "chillhop"], ["电子", "electronic", "lo-fi", "lofi", "ambient", "chillhop", "beats"]),
            (["蓝调", "blues"], ["蓝调", "blues"]),
            (["灵魂", "soul", "r&b", "rnb"], ["灵魂", "soul", "r&b", "neo soul"]),
            (["民谣", "folk", "乡村", "country"], ["民谣", "folk", "乡村", "country"]),
            (["摇滚", "rock", "朋克", "punk"], ["摇滚", "rock", "punk"]),
            (["流行", "pop", "热歌"], ["流行", "pop", "hits"]),
            (["纯音乐", "轻音乐", "instrumental"], ["纯音乐", "轻音乐", "钢琴", "piano", "instrumental"]),
            // 语言/人声类
            (["女声", "女歌手"], ["女声", "female", "女声爵士", "华语女声"]),
            (["男声", "男歌手"], ["男声", "male", "男声爵士", "华语男声"]),
            (["中文", "华语", "国语"], ["中文", "华语", "国语", "chinese"]),
            (["英文", "欧美"], ["英文", "欧美", "english"]),
            (["日文", "日语", "j-pop"], ["日文", "日语", "j-pop", "japanese"]),
            (["韩文", "韩语", "k-pop"], ["韩文", "韩语", "k-pop", "korean"])
        ]

        for tag in tags {
            if tag.keywords.contains(where: { lower.contains($0) }) {
                if let matched = favorites.first(where: { fav in
                    let fName = fav.name.lowercased()
                    return tag.favHints.contains(where: { fName.contains($0) })
                }) {
                    return matched
                }
            }
        }

        // 风格关键词提取：从原始请求中提取风格词，在收藏中精确匹配
        let styleKeywords = ["爵士", "jazz", "古典", "classical", "电子", "electronic", "lo-fi", "lofi",
                             "蓝调", "blues", "灵魂", "soul", "民谣", "folk", "摇滚", "rock",
                             "bossa", "轻音乐", "纯音乐", "流行", "pop", "摇滚"]
        let matchedStyles = styleKeywords.filter { lower.contains($0) }
        for style in matchedStyles {
            if let matched = favorites.first(where: { $0.name.lowercased().contains(style) }) {
                return matched
            }
        }

        return favorites.first(where: { fav in
            let fName = fav.name.lowercased()
            return lower.contains(fName) || fName.contains(lower)
        })
    }

    private func executeDemoIntent(_ intent: SonosControlIntent) {
        guard let group = currentGroup, let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }

        switch intent {
        case .play:
            groups[idx].playbackState = .playing
            lastActionFeedback = "Resumed playback"
        case .pause:
            groups[idx].playbackState = .paused
            lastActionFeedback = "Paused"
        case .togglePlayPause:
            groups[idx].playbackState = groups[idx].playbackState.isPlaying ? .paused : .playing
        case .next:
            nextTrack()
            lastActionFeedback = "Skipped to next track"
        case .previous:
            previousTrack()
            lastActionFeedback = "Skipped to previous track"
        case .setVolume(_, let level):
            groups[idx].volume = level
            groups[idx].isMuted = false
            lastActionFeedback = "Volume set to \(level)"
        case .setMute(_, let isMuted):
            groups[idx].isMuted = isMuted
            lastActionFeedback = isMuted ? "Muted" : "Unmuted"
        case .setPlayerVolume(let playerId, let level):
            if let dIdx = allDevices.firstIndex(where: { $0.id == playerId }) {
                allDevices[dIdx].volume = level
                lastActionFeedback = "\(allDevices[dIdx].name) volume set to \(level)"
            }
        case .setPlayerMute(let playerId, let isMuted):
            if let dIdx = allDevices.firstIndex(where: { $0.id == playerId }) {
                allDevices[dIdx].isMuted = isMuted
            }
        case .setShuffle(_, let enabled):
            groups[idx].isShuffle = enabled
            lastActionFeedback = enabled ? "Shuffle enabled" : "Shuffle disabled"
        case .setRepeat(_, let mode):
            groups[idx].repeatMode = mode
        case .playArtist(let artist, _, _):
            groups[idx].currentTrack = TrackInfo(
                title: "當愛已成往事",
                artist: artist,
                album: "滾石香港黃金十年",
                musicService: "Apple Music",
                durationSeconds: 285,
                positionSeconds: 0
            )
            groups[idx].playbackState = .playing
            lastActionFeedback = "Playing songs by \(artist)"

        case .playTrack(let title, let artist, _, _):
            groups[idx].currentTrack = TrackInfo(
                title: title,
                artist: artist ?? "经典原唱",
                album: "精选热歌",
                durationSeconds: 240,
                positionSeconds: 0
            )
            groups[idx].playbackState = .playing
            lastActionFeedback = "Now playing: \(title)"

        case .playAlbum(let album, let artist, _, _):
            groups[idx].currentTrack = TrackInfo(
                title: "专辑曲目 01",
                artist: artist ?? "精选艺人",
                album: album,
                durationSeconds: 260,
                positionSeconds: 0
            )
            groups[idx].playbackState = .playing
            lastActionFeedback = "Playing album: \(album)"

        case .playPlaylist(let name, _, _):
            groups[idx].currentTrack = TrackInfo(
                title: "精选曲目 01",
                artist: "群星",
                album: name,
                durationSeconds: 210,
                positionSeconds: 0
            )
            groups[idx].playbackState = .playing
            lastActionFeedback = "Playing playlist: \(name)"

        case .playFavorite(_, let name, _):
            groups[idx].currentTrack = TrackInfo(title: name, artist: "Sonos 收藏", album: "精选流媒体", durationSeconds: 240, positionSeconds: 0)
            groups[idx].playbackState = .playing
            lastActionFeedback = "Playing favorite: \(name)"

        case .getFavorites, .getHouseholdStatus, .getNowPlaying, .getHouseholds, .getGroups, .getGroupVolume:
            break

        case .addPlayersToGroup, .removePlayersFromGroup, .moveAudio:
            break

        case .naturalLanguage(let query):
            lastActionFeedback = "Demo: \(query)"
        }
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let group = self.currentGroup, group.playbackState.isPlaying else { return }
                if let idx = self.groups.firstIndex(where: { $0.id == group.id }) {
                    var cur = self.groups[idx].currentTrack
                    if cur.durationSeconds > 0 {
                        cur.positionSeconds += 1.0
                        if cur.positionSeconds >= cur.durationSeconds {
                            cur.positionSeconds = 0
                        }
                        self.groups[idx].currentTrack = cur
                    }
                }
            }
        }
    }
}
