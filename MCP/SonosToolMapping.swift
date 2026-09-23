import Foundation

// MARK: - 控制意图定义
public enum SonosControlIntent: Sendable {
    case play(groupId: String?)
    case pause(groupId: String?)
    case togglePlayPause(groupId: String?)
    case next(groupId: String?)
    case previous(groupId: String?)
    case setVolume(groupId: String?, level: Int)
    case setMute(groupId: String?, isMuted: Bool)
    case setPlayerVolume(playerId: String, level: Int)
    case setPlayerMute(playerId: String, isMuted: Bool)
    case setShuffle(groupId: String?, enabled: Bool)
    case setRepeat(groupId: String?, mode: RepeatMode)
    case playArtist(artist: String, musicService: String?, groupId: String?)
    case playTrack(title: String, artist: String?, musicService: String?, groupId: String?)
    case playAlbum(album: String, artist: String?, musicService: String?, groupId: String?)
    case playPlaylist(name: String, musicService: String?, groupId: String?)
    case playFavorite(id: String, name: String, groupId: String?)
    case getFavorites(householdId: String)
    case getHouseholds                          // 获取家庭列表
    case getGroups(householdId: String)         // 获取指定家庭的分组与音箋
    case getHouseholdStatus                     // 兼容旧写法（内部会自动转为两步调用）
    case getNowPlaying(groupId: String?)
    case getGroupVolume(groupId: String)
    case addPlayersToGroup(playerIds: [String], targetGroupId: String)
    case removePlayersFromGroup(playerIds: [String], sourceGroupId: String)
    case moveAudio(fromGroupId: String, toPlayerIds: [String])
    case naturalLanguage(query: String)
}

// MARK: - 工具自适应解析映射器
public struct SonosToolMapping: Sendable {
    public let availableTools: [MCPTool]

    public init(tools: [MCPTool] = []) {
        self.availableTools = tools
    }

    /// 模糊匹配：先全匹配，再按顺序试个个匹配子串
    public func findTool(matching patterns: [String]) -> MCPTool? {
        for pattern in patterns {
            let lower = pattern.lowercased()
            if let exact = availableTools.first(where: { $0.name.lowercased() == lower }) {
                return exact
            }
        }
        // 如果没有全匹配，再试模糊匹配
        for pattern in patterns {
            let lower = pattern.lowercased()
            if let partial = availableTools.first(where: { $0.name.lowercased().contains(lower) }) {
                return partial
            }
        }
        return nil
    }

    /// 根据用户意图解析出具体的 MCP 工具调用参数
    public func resolve(intent: SonosControlIntent) -> (toolName: String, args: [String: AnyCodable])? {
        switch intent {
        case .play(let groupId):
            if let tool = findTool(matching: ["play", "resume", "playback_play"]) {
                var args: [String: AnyCodable] = [:]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .pause(let groupId):
            if let tool = findTool(matching: ["pause", "playback_pause"]) {
                var args: [String: AnyCodable] = [:]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .togglePlayPause(let groupId):
            if let tool = findTool(matching: ["togglePlayPause", "toggle", "play", "pause"]) {
                var args: [String: AnyCodable] = [:]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .next(let groupId):
            if let tool = findTool(matching: ["skipToNextTrack", "skip_to_next", "next"]) {
                var args: [String: AnyCodable] = [:]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .previous(let groupId):
            if let tool = findTool(matching: ["skipToPreviousTrack", "skip_to_previous", "previous"]) {
                var args: [String: AnyCodable] = [:]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .setVolume(let groupId, let level):
            if let tool = findTool(matching: ["setVolume", "set_volume", "set_group_volume"]) {
                var args: [String: AnyCodable] = ["volume": .int(level)]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .setMute(let groupId, let isMuted):
            if let tool = findTool(matching: ["setMute", "set_mute", "set_group_mute"]) {
                var args: [String: AnyCodable] = ["muted": .bool(isMuted)]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .setPlayerVolume(let playerId, let level):
            if let tool = findTool(matching: ["setVolume", "set_player_volume", "playerVolume"]) {
                return (tool.name, [
                    "playerId": .string(playerId),
                    "player_id": .string(playerId),
                    "volume": .int(level)
                ])
            }

        case .setPlayerMute(let playerId, let isMuted):
            if let tool = findTool(matching: ["setMute", "set_player_mute", "playerMute"]) {
                return (tool.name, [
                    "playerId": .string(playerId),
                    "player_id": .string(playerId),
                    "muted": .bool(isMuted)
                ])
            }

        case .setShuffle(let groupId, let enabled):
            if let tool = findTool(matching: ["setPlayModes", "set_play_modes", "setShuffle"]) {
                var args: [String: AnyCodable] = ["playModes": .dictionary(["shuffle": .bool(enabled)])]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .setRepeat(let groupId, let mode):
            if let tool = findTool(matching: ["setPlayModes", "set_play_modes", "setRepeatMode"]) {
                let repeatOne = mode == .one
                let repeatAll = mode == .all
                var args: [String: AnyCodable] = ["playModes": .dictionary([
                    "repeat": .bool(repeatAll),
                    "repeatOne": .bool(repeatOne)
                ])]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .playArtist(let artist, let musicService, let groupId):
            if let tool = findTool(matching: ["play_artist", "playArtist"]) {
                var args: [String: AnyCodable] = [
                    "artist": .string(artist),
                    "shuffle": .bool(false)
                ]
                if let service = musicService, !service.isEmpty {
                    args["music_service"] = .string(service)
                }
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .playTrack(let title, let artist, let musicService, let groupId):
            if let tool = findTool(matching: ["play_track", "playTrack"]) {
                var args: [String: AnyCodable] = ["track": .string(title)]
                if let a = artist { args["artist"] = .string(a) }
                if let service = musicService, !service.isEmpty {
                    args["music_service"] = .string(service)
                }
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .playAlbum(let album, let artist, let musicService, let groupId):
            if let tool = findTool(matching: ["play_album", "playAlbum"]) {
                var args: [String: AnyCodable] = [
                    "album": .string(album),
                    "shuffle": .bool(false)
                ]
                if let a = artist { args["artist"] = .string(a) }
                if let service = musicService, !service.isEmpty {
                    args["music_service"] = .string(service)
                }
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .playPlaylist(let name, let musicService, let groupId):
            if let tool = findTool(matching: ["play_playlist", "loadPlaylist", "play_sonos_playlist", "playPlaylist"]) {
                var args: [String: AnyCodable] = [
                    "playlist": .string(name),
                    "playlistName": .string(name),
                    "shuffle": .bool(false)
                ]
                if let service = musicService, !service.isEmpty {
                    args["music_service"] = .string(service)
                    args["service"] = .string(service)
                }
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .playFavorite(let id, _, let groupId):
            if let tool = findTool(matching: ["loadFavorite", "play_sonos_favorite", "playFavorite"]) {
                var args: [String: AnyCodable] = [
                    "favoriteId": .string(id),
                    "favorite_id": .string(id),
                    "shuffle": .bool(false)
                ]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .getFavorites(let householdId):
            if let tool = findTool(matching: ["getFavorites", "get_favorites", "get_sonos_favorites"]) {
                return (tool.name, [
                    "householdId": .string(householdId),
                    "household_id": .string(householdId)
                ])
            }

        case .getHouseholds:
            if let tool = findTool(matching: ["getHouseholds", "get_households", "households"]) {
                return (tool.name, [:])
            }

        case .getGroups(let householdId):
            if let tool = findTool(matching: ["getGroups", "get_groups", "groups"]) {
                return (tool.name, [
                    "householdId": .string(householdId),
                    "household_id": .string(householdId)
                ])
            }

        case .getNowPlaying(let groupId):
            if let tool = findTool(matching: ["getMetadataStatus", "get_metadata_status", "getNowPlaying", "get_now_playing", "getPlaybackStatus"]) {
                var args: [String: AnyCodable] = [:]
                if let gid = groupId { args["groupId"] = .string(gid); args["group_id"] = .string(gid) }
                return (tool.name, args)
            }

        case .getGroupVolume(let groupId):
            if let tool = findTool(matching: ["get_group_volume", "getGroupVolume"]) {
                var args: [String: AnyCodable] = [:]
                args["groupId"] = .string(groupId)
                args["group_id"] = .string(groupId)
                return (tool.name, args)
            }

        case .addPlayersToGroup(let playerIds, let targetGroupId):
            if let tool = findTool(matching: ["modifyGroupMembers", "addPlayersToGroup", "add_players_to_group"]) {
                let codableIds = playerIds.map { AnyCodable.string($0) }
                return (tool.name, [
                    "groupId": .string(targetGroupId),
                    "group_id": .string(targetGroupId),
                    "playerIdsToAdd": .array(codableIds),
                    "player_ids": .array(codableIds)
                ])
            }

        case .removePlayersFromGroup(let playerIds, let sourceGroupId):
            if let tool = findTool(matching: ["modifyGroupMembers", "removePlayersFromGroup", "remove_players_from_group"]) {
                let codableIds = playerIds.map { AnyCodable.string($0) }
                return (tool.name, [
                    "groupId": .string(sourceGroupId),
                    "group_id": .string(sourceGroupId),
                    "playerIdsToRemove": .array(codableIds),
                    "player_ids": .array(codableIds)
                ])
            }

        case .moveAudio(let fromGroupId, let toPlayerIds):
            if let tool = findTool(matching: ["move_audio_to_players", "moveAudioToPlayers"]) {
                let codableIds = toPlayerIds.map { AnyCodable.string($0) }
                return (tool.name, [
                    "from_group_id": .string(fromGroupId),
                    "to_player_ids": .array(codableIds)
                ])
            }

        case .getHouseholdStatus:
            // 先尝试全包含工具，再尝试 getHouseholds
            if let tool = findTool(matching: [
                "get_households_and_groups_and_players",
                "get_households_groups_players",
                "getHouseholdsGroupsPlayers",
                "getHouseholds",
                "get_households"
            ]) {
                return (tool.name, [:])
            }

        case .naturalLanguage(let query):
            if let tool = findTool(matching: ["natural_language", "prompt", "command"]) {
                return (tool.name, ["query": .string(query)])
            }
        }

        return nil
    }

    /// 将大模型（LLM）返回的抽象工具调用智能对齐到当前 Sonos MCP 真实存在的工具，并补齐兼容参数
    /// 如果在当前 MCP 服务端未找到匹配的工具，返回 nil（用于防空拦截，绝不浪费配额）
    public func resolveLLMCall(toolName: String, args: [String: AnyCodable]) -> (toolName: String, args: [String: AnyCodable])? {
        let lowerName = toolName.lowercased()
        var normalizedArgs = args

        // 1. 歌单播放类工具对齐
        if lowerName.contains("playlist") {
            guard let realTool = findTool(matching: ["play_playlist", "load_playlist", "loadPlaylist", "play_sonos_playlist", "playPlaylist"]) else {
                return nil
            }
            let rawName = args["playlist"]?.stringValue ?? args["playlistName"]?.stringValue ?? args["name"]?.stringValue ?? ""
            let pName = sanitizePlaylistQuery(rawName)
            normalizedArgs["playlist"] = .string(pName)
            normalizedArgs["playlistName"] = .string(pName)
            normalizedArgs["shuffle"] = .bool(extractBool(from: args["shuffle"], default: false))
            injectGroupIdAndService(into: &normalizedArgs)
            return (realTool.name, normalizedArgs)
        }

        // 2. 歌手电台/连续混播类工具对齐
        if lowerName.contains("artist") {
            guard let realTool = findTool(matching: ["play_artist", "playArtist"]) else {
                return nil
            }
            let artist = args["artist"]?.stringValue ?? args["name"]?.stringValue ?? ""
            normalizedArgs["artist"] = .string(artist)
            normalizedArgs["shuffle"] = .bool(extractBool(from: args["shuffle"], default: false))
            injectGroupIdAndService(into: &normalizedArgs)
            return (realTool.name, normalizedArgs)
        }

        // 3. 单曲播放类工具对齐
        if lowerName.contains("track") || lowerName.contains("song") {
            guard let realTool = findTool(matching: ["play_track", "playTrack"]) else {
                return nil
            }
            let track = args["track"]?.stringValue ?? args["title"]?.stringValue ?? args["name"]?.stringValue ?? ""
            normalizedArgs["track"] = .string(track)
            // 如果存在 shuffle 参数，确保其为严格布尔值
            if args["shuffle"] != nil {
                normalizedArgs["shuffle"] = .bool(extractBool(from: args["shuffle"], default: false))
            }
            injectGroupIdAndService(into: &normalizedArgs)
            return (realTool.name, normalizedArgs)
        }

        // 4. 专辑播放类工具对齐
        if lowerName.contains("album") {
            guard let realTool = findTool(matching: ["play_album", "playAlbum"]) else {
                return nil
            }
            let album = args["album"]?.stringValue ?? args["name"]?.stringValue ?? ""
            normalizedArgs["album"] = .string(album)
            normalizedArgs["shuffle"] = .bool(extractBool(from: args["shuffle"], default: false))
            injectGroupIdAndService(into: &normalizedArgs)
            return (realTool.name, normalizedArgs)
        }

        // 5. 恢复播放 / 暂停播放
        if lowerName == "resume" || lowerName == "play" {
            guard let realTool = findTool(matching: ["play", "resume", "playback_play"]) else {
                return nil
            }
            injectGroupIdAndService(into: &normalizedArgs)
            return (realTool.name, normalizedArgs)
        }

        if lowerName == "pause" {
            guard let realTool = findTool(matching: ["pause", "playback_pause"]) else {
                return nil
            }
            injectGroupIdAndService(into: &normalizedArgs)
            return (realTool.name, normalizedArgs)
        }

        // 6. 音量调节
        if lowerName.contains("volume") {
            guard let realTool = findTool(matching: ["setVolume", "set_volume", "set_group_volume"]) else {
                return nil
            }
            injectGroupIdAndService(into: &normalizedArgs)
            return (realTool.name, normalizedArgs)
        }

        // 7. 通用匹配：若大模型直接命中了已有的工具名
        if let directTool = findTool(matching: [toolName]) {
            injectGroupIdAndService(into: &normalizedArgs)
            return (directTool.name, normalizedArgs)
        }

        // 8. 若当前服务端完全未提供该工具，返回 nil 触发本地防空拦截
        return nil
    }

    private func injectGroupIdAndService(into args: inout [String: AnyCodable]) {
        if let gid = args["group_id"]?.stringValue ?? args["groupId"]?.stringValue {
            args["groupId"] = .string(gid)
            args["group_id"] = .string(gid)
        }
        if let srv = args["music_service"]?.stringValue ?? args["service"]?.stringValue {
            args["music_service"] = .string(srv)
            args["service"] = .string(srv)
        }
    }

    private func extractBool(from any: AnyCodable?, default defaultValue: Bool = false) -> Bool {
        guard let any = any else { return defaultValue }
        switch any {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .string(let s): return s.lowercased() == "true" || s == "1"
        default: return defaultValue
        }
    }

    /// 将用户的复杂口语修饰句提炼为真实流媒体（Apple Music / Spotify）高命中的经典歌单名称
    public func sanitizePlaylistQuery(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’《》【】"))
        guard clean.count > 6 else { return clean }

        // 移除多余的口语填充词、修饰词及介词
        let stopWords = [
            "适合在", "适合", "一个人在", "一个人", "在", "于", "里的", "中的",
            "听的", "播放", "我想听", "想听", "来点", "来首", "来一首",
            "背景音乐", "音乐歌单", "歌单", "歌曲", "听听", "放放",
            "那种有", "感觉的", "氛围的", "相关的", "类型的", "风格的"
        ]
        for w in stopWords {
            clean = clean.replacingOccurrences(of: w, with: " ")
        }

        let parts = clean.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if parts.isEmpty {
            return String(raw.prefix(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 特别处理：若是中文多实体（如“雨天”与“咖啡馆”），既保留空格拼接也提供候选支持
        let concise = parts.prefix(2).joined(separator: " ")
        return concise.isEmpty ? raw : concise
    }

    /// 根据原始输入生成有序的备选歌单池（用于多级保底）
    public func generatePlaylistCandidates(rawQuery: String) -> [String] {
        return SceneFallbackCatalog.candidates(for: rawQuery)
    }
}

// MARK: - 场景精选与保底曲库目录（Scene Fallback Catalog）
public struct SceneFallbackCatalog: Sendable {
    /// 针对用户输入的场景、氛围、心境，智能推荐流媒体（Apple Music / Spotify）必定收录的官方权威经典歌单
    public static func candidates(for query: String) -> [String] {
        let lower = query.lowercased()
        var results: [String] = []

        // 1. 咖啡馆 / 雨天 / 读书 / 慵懒慢生活
        if lower.contains("咖啡") || lower.contains("cafe") || lower.contains("coffee") || lower.contains("下午茶") {
            results.append(contentsOf: ["咖啡馆爵士", "雨天咖啡馆", "慢调爵士", "咖啡馆音乐", "惬意慢调"])
        } else if lower.contains("雨") || lower.contains("rain") {
            results.append(contentsOf: ["雨天咖啡馆", "雨天慢调", "下雨天", "自然雨声"])
        }

        // 1b. 下雪天 / 冬天 / 寒冷
        if lower.contains("雪") || lower.contains("snow") || lower.contains("冬") || lower.contains("winter") || lower.contains("cold") {
            results.append(contentsOf: ["雪夜爵士", "冬日暖阳", "冬日爵士", "温暖民谣", "Winter Jazz"])
        }

        // 2. 工作 / 学习 / 专注 / 效率 / 编程
        if lower.contains("工作") || lower.contains("学习") || lower.contains("专注") || lower.contains("效率") || lower.contains("代码") || lower.contains("focus") || lower.contains("study") {
            results.append(contentsOf: ["专注工作", "学习纯音乐", "深度专注", "轻音乐精选"])
        }

        // 3. 睡眠 / 助眠 / 白噪音 / 晚安
        if lower.contains("睡") || lower.contains("助眠") || lower.contains("失眠") || lower.contains("晚安") || lower.contains("白噪音") || lower.contains("sleep") {
            results.append(contentsOf: ["深度睡眠", "助眠纯音乐", "晚安轻音乐", "自然白噪音"])
        }

        // 4. 放松 / 解压 / 治愈 / 冥想 / 安静
        if lower.contains("放松") || lower.contains("解压") || lower.contains("治愈") || lower.contains("冥想") || lower.contains("安静") || lower.contains("relax") {
            results.append(contentsOf: ["身心放松", "治愈系纯音乐", "轻松轻音乐", "惬意轻音乐"])
        }

        // 5. 运动 / 健身 / 跑步 / 燃脂
        if lower.contains("运动") || lower.contains("健身") || lower.contains("跑步") || lower.contains("燃脂") || lower.contains("workout") {
            results.append(contentsOf: ["跑步运动", "健身燃脂", "活力流行"])
        }

        // 5b. 爵士 / Bossa Nova / 摇摆
        if lower.contains("爵士") || lower.contains("jazz") || lower.contains("bossa") || lower.contains("bossa nova") || lower.contains("摇摆") || lower.contains("swing") {
            results.append(contentsOf: ["爵士女声", "咖啡馆爵士", "A-List 爵士", "Bossa Nova", "Smooth Jazz", "Cool Jazz", "深夜爵士"])
        }

        // 5c. 古典 / 钢琴 / 交响
        if lower.contains("古典") || lower.contains("classical") || lower.contains("交响") || lower.contains("钢琴曲") || lower.contains("协奏") {
            results.append(contentsOf: ["古典钢琴", "古典精选", "钢琴古典", "Classical Essentials", "唯美钢琴"])
        }

        // 5d. 电子 / Lo-Fi / Ambient / Chillhop
        if lower.contains("电子") || lower.contains("electronic") || lower.contains("lo-fi") || lower.contains("lofi") || lower.contains("ambient") || lower.contains("chillhop") || lower.contains("techno") || lower.contains("house") {
            results.append(contentsOf: ["Lo-Fi Beats", "电子氛围", "Chillhop", "Ambient", "Deep Focus"])
        }

        // 5e. 蓝调 / Blues / 灵魂 / Soul / R&B
        if lower.contains("蓝调") || lower.contains("blues") || lower.contains("灵魂") || lower.contains("soul") || lower.contains("r&b") || lower.contains("rnb") {
            results.append(contentsOf: ["蓝调精选", "灵魂乐精选", "Neo Soul", "Blues Essentials"])
        }

        // 5f. 民谣 / Folk / 乡村 / Country
        if lower.contains("民谣") || lower.contains("folk") || lower.contains("乡村") || lower.contains("country") {
            results.append(contentsOf: ["民谣精选", "城市民谣", "独立民谣", "乡村经典"])
        }

        // 5g. 摇滚 / Rock
        if lower.contains("摇滚") || lower.contains("rock") || lower.contains("朋克") || lower.contains("punk") {
            results.append(contentsOf: ["摇滚经典", "Rock Essentials", "另类摇滚"])
        }

        // 5h. 流行 / Pop
        if lower.contains("流行") || lower.contains("pop") || lower.contains("热歌") || lower.contains("hits") {
            results.append(contentsOf: ["轻松流行", "Today's Hits", "Pop Rising"])
        }

        // 5i. 夜晚 / 深夜 / 微醺 / 放松氛围
        if lower.contains("夜晚") || lower.contains("深夜") || lower.contains("微醺") || lower.contains("night") || lower.contains("lounge") {
            results.append(contentsOf: ["深夜爵士", "微醺之夜", "Night Jazz", "Lounge"])
        }

        // 5j. 中文/华语 + 人声维度
        if lower.contains("女声") || lower.contains("女歌手") {
            results.append(contentsOf: ["爵士女声", "华语女声", "女声爵士", "Female Vocals"])
        }
        if lower.contains("男声") || lower.contains("男歌手") {
            results.append(contentsOf: ["爵士男声", "华语男声", "Male Vocals"])
        }

        // 6. 纯音乐 / 轻音乐 / 乐器
        if lower.contains("纯音乐") || lower.contains("轻音乐") || lower.contains("钢琴") || lower.contains("吉他") || lower.contains("instrumental") {
            results.append(contentsOf: ["惬意轻音乐", "唯美钢琴曲", "轻音乐精选", "专注工作"])
        }

        // 7. 草原 / 辽阔 / 民歌
        if lower.contains("辽阔") || lower.contains("草原") || lower.contains("青藏高原") {
            results.append(contentsOf: ["青藏高原", "草原民歌", "民族音乐精选"])
        }

        // 8. 兜底通用经典歌单（确保永不为空）
        results.append(contentsOf: ["流行精选", "轻松流行", "惬意轻音乐"])

        // 去重并保持原有推荐次序
        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }
    }
}
