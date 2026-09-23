import Foundation

// MARK: - LLM 多候选搜索结果
public struct LLMSearchResult: Sendable {
    /// "playlist" / "artist" / "track" / "album"
    public var intent: String
    /// 歌单搜索候选词列表（intent 为 "playlist" 时有多个，其余为 0-1 个）
    public var candidates: [String]
    /// 音乐服务
    public var musicService: String?
    /// 非歌单意图时的完整工具调用（如 play_artist / play_track / play_album）
    public var primaryToolCall: (toolName: String, args: [String: AnyCodable])?

    public init(intent: String, candidates: [String], musicService: String?,
                primaryToolCall: (toolName: String, args: [String: AnyCodable])? = nil) {
        self.intent = intent
        self.candidates = candidates
        self.musicService = musicService
        self.primaryToolCall = primaryToolCall
    }
}

// MARK: - 自然语言命令解析器
public struct NLCommandParser: Sendable {

    /// 本地极速意图识别（0ms 响应，零 Token 消耗）
    public static func parseLocalIntent(
        text: String,
        currentGroupId: String?,
        preferredMusicService: String? = "Apple Music"
    ) -> SonosControlIntent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 0. 动态检测指令中是否显式指定了某个音乐服务（如“用 Spotify 播放...”、“从 Apple Music 播放...”）
        var targetService = preferredMusicService
        let lowerText = trimmed.lowercased()
        if lowerText.contains("spotify") {
            targetService = "Spotify"
        } else if lowerText.contains("apple music") || lowerText.contains("苹果音乐") || lowerText.contains("apple") {
            targetService = "Apple Music"
        } else if lowerText.contains("sonos radio") {
            targetService = "Sonos Radio"
        }

        // 清理指令中声明服务的前导/修饰词（如“用 Spotify 播放”、“在 Apple Music 上放”）
        var commandText = trimmed
        let servicePattern = "(?:从|用|在|通过|使用|on|from|using|with)?\\s*(?:Spotify|Apple\\s*Music|苹果音乐|Sonos\\s*Radio)\\s*(?:上|里|中|播放器)?"
        if let reg = try? NSRegularExpression(pattern: servicePattern, options: .caseInsensitive) {
            commandText = reg.stringByReplacingMatches(in: commandText, range: NSRange(commandText.startIndex..., in: commandText), withTemplate: "")
        }
        commandText = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        if commandText.isEmpty { commandText = trimmed }
        let cleanLower = commandText.lowercased()

        // 1. 暂停
        if cleanLower == "暂停" || cleanLower == "暂停播放" || cleanLower == "pause" || cleanLower == "stop" || cleanLower.contains("别放了") {
            return .pause(groupId: currentGroupId)
        }

        // 2. 恢复播放
        if cleanLower == "播放" || cleanLower == "继续播放" || cleanLower == "play" || cleanLower == "resume" || cleanLower == "开始" {
            return .play(groupId: currentGroupId)
        }

        // 3. 上下一首
        if cleanLower.contains("下一首") || cleanLower.contains("下一曲") || cleanLower.contains("切歌") || cleanLower == "next" || cleanLower == "skip" {
            return .next(groupId: currentGroupId)
        }
        if cleanLower.contains("上一首") || cleanLower.contains("上一曲") || cleanLower == "prev" || cleanLower == "previous" {
            return .previous(groupId: currentGroupId)
        }

        // 4. 静音控制
        if cleanLower == "静音" || cleanLower == "开启静音" || cleanLower == "mute" {
            return .setMute(groupId: currentGroupId, isMuted: true)
        }
        if cleanLower == "取消静音" || cleanLower == "恢复声音" || cleanLower == "unmute" {
            return .setMute(groupId: currentGroupId, isMuted: false)
        }

        // 5. 音量控制（如“音量50”、“音量调到30%”、“volume 40”）
        let volumeRegex = try? NSRegularExpression(pattern: "(?:音量|声音|volume)\\s*(?:调到|为|设为)?\\s*(\\d+)", options: .caseInsensitive)
        if let match = volumeRegex?.firstMatch(in: cleanLower, range: NSRange(cleanLower.startIndex..., in: cleanLower)),
           let range = Range(match.range(at: 1), in: cleanLower),
           let vol = Int(cleanLower[range]) {
            let clamped = max(0, min(100, vol))
            return .setVolume(groupId: currentGroupId, level: clamped)
        }

        // 6. 随机与循环
        if cleanLower.contains("随机播放") || cleanLower == "shuffle" {
            return .setShuffle(groupId: currentGroupId, enabled: true)
        }
        if cleanLower.contains("单曲循环") {
            return .setRepeat(groupId: currentGroupId, mode: .one)
        }
        if cleanLower.contains("全部循环") || cleanLower.contains("列表循环") {
            return .setRepeat(groupId: currentGroupId, mode: .all)
        }

        // 7. 点播专辑（如：“播放专辑 范特西”、“播放周杰伦的专辑范特西”、“放专辑魔杰座”）
        if cleanLower.contains("专辑") || cleanLower.contains("album") {
            // 7.1 "播放 歌手 的专辑 专辑名"
            let artistAlbumPattern = "^(?:我想听|想听|播放|放|听|播)?\\s*([^的]+)的(?:专辑)?\\s*([^的]+)$"
            if let regex = try? NSRegularExpression(pattern: artistAlbumPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: commandText, range: NSRange(commandText.startIndex..., in: commandText)),
               let r1 = Range(match.range(at: 1), in: commandText),
               let r2 = Range(match.range(at: 2), in: commandText) {
                let artist = String(commandText[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
                var album = String(commandText[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
                album = album.replacingOccurrences(of: "专辑", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’"))
                if !album.isEmpty && !artist.isEmpty && album != "歌" && album != "歌曲" {
                    return .playAlbum(album: album, artist: artist, musicService: targetService, groupId: currentGroupId)
                }
            }

            // 7.2 "播放专辑 范特西" / "放专辑 魔杰座"
            let cleanAlbum = commandText
                .replacingOccurrences(of: "播放专辑", with: "")
                .replacingOccurrences(of: "放专辑", with: "")
                .replacingOccurrences(of: "听专辑", with: "")
                .replacingOccurrences(of: "播放", with: "")
                .replacingOccurrences(of: "专辑", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’"))
            if !cleanAlbum.isEmpty && cleanAlbum != "歌" {
                return .playAlbum(album: cleanAlbum, artist: nil, musicService: targetService, groupId: currentGroupId)
            }
        }

        // 场景、风格、纯音乐等通用关键词（绝不能被误判为单曲或歌手）
        let sceneKeywords = [
            "纯音乐", "轻音乐", "音乐", "工作", "学习", "效率", "适合", "助眠",
            "睡眠", "放松", "解压", "专注", "背景音乐", "bgm", "白噪音", "电台",
            "歌单", "歌曲", "安静", "治愈", "催眠", "爵士", "古典", "摇滚", "民谣",
            "节奏", "旋律", "钢琴", "吉他", "小提琴", "氛围",
            // English genre/scene keywords
            "jazz", "classical", "rock", "folk", "blues", "electronic", "lo-fi", "lofi",
            "chill", "ambient", "indie", "pop", "soul", "funk", "reggae", "country",
            "metal", "punk", "dance", "r&b", "instrumental", "acoustic", "lounge",
            "bossa nova", "swing", "hip hop", "relax", "sleep", "workout", "study",
            "focus", "party", "new age", "latin", "world music"
        ]

        // 8. 点播单曲（如："播放周杰伦的晴天"、"放晴天"、"play Shape of You by Ed Sheeran"）
        // 8.1 英文格式: "play [track] by [artist]" / "play [track]"
        let englishTrackPattern = "^(?:play|listen to)\\s+(.+?)(?:\\s+by\\s+(.+))?$"
        if let regex = try? NSRegularExpression(pattern: englishTrackPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: commandText, range: NSRange(commandText.startIndex..., in: commandText)),
           let r1 = Range(match.range(at: 1), in: commandText) {
            let track = String(commandText[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
            var artist: String?
            if match.numberOfRanges > 2, let r2 = Range(match.range(at: 2), in: commandText) {
                artist = String(commandText[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // 关键修复：无 "by" 子句且名称像歌手名（多词、无介词）时，让 section 11 歌手匹配优先处理
            // 避免 "play Michael Jackson" 被误判为单曲，但保留 "play Shape of You" 为单曲
            let hasByClause = artist != nil
            let titleIndicators = [" of ", " the ", " in ", " on ", " a ", " to ", " for ", " with ", " from ", " at ", " by ", " it "]
            let looksLikeTitle = titleIndicators.contains { track.lowercased().contains($0) }
            let looksLikeArtistName = !hasByClause && track.contains(" ") && !looksLikeTitle
            if !track.isEmpty && track.lowercased() != "music" && !looksLikeArtistName {
                return .playTrack(title: track, artist: artist, musicService: targetService, groupId: currentGroupId)
            }
        }
        // 8.2 中文格式: "播放[歌手]的[歌曲]"
        let trackWithArtistPattern = "^(?:我想听|想听|点播|播放|放|听|播|来首|来一首)?\\s*([^的]+)的([^的]+)$"
        if let regex = try? NSRegularExpression(pattern: trackWithArtistPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: commandText, range: NSRange(commandText.startIndex..., in: commandText)),
           let r1 = Range(match.range(at: 1), in: commandText),
           let r2 = Range(match.range(at: 2), in: commandText) {
            let a = String(commandText[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let s = String(commandText[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
            // 排除含有场景/纯音乐等词汇，防止把“适合提高工作效率”当歌手、“纯音乐”当单曲
            let containsScene = sceneKeywords.contains { a.contains($0) || s.contains($0) }
            if !containsScene && !a.isEmpty && !s.isEmpty && s != "歌" && s != "歌曲" && s != "音乐" {
                return .playTrack(title: s, artist: a, musicService: targetService, groupId: currentGroupId)
            }
        }

        // 9. 歌单播放（如："播放歌单 流行精选"、"播放 A-List 国际流行"、"放歌单..."、"播放轻松不插电歌单"）
        if cleanLower.contains("歌单") {
            var name = commandText
                .replacingOccurrences(of: "播放歌单", with: "")
                .replacingOccurrences(of: "放歌单", with: "")
                .replacingOccurrences(of: "听歌单", with: "")
                .replacingOccurrences(of: "歌单", with: "")
            // 关键：移除残留的动词前缀（当"歌单"位于名称后面时，如"播放XXX歌单"）
            for prefix in ["播放", "放", "听", "播", "来点", "来一首", "来首", "我想听", "想听"] {
                if name.hasPrefix(prefix) {
                    name = String(name.dropFirst(prefix.count))
                    break
                }
            }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return .playPlaylist(name: name, musicService: targetService, groupId: currentGroupId)
            }
        }

        // 识别常见英文榜单或流行歌单格式（如 a-list 国际流行、top 50、today's hits、best of 等）
        let englishPlaylistIndicators = ["a-list", "a list", "playlist", "top ", "榜单", "today's hits", "best of", "greatest hits", " essentials", "radio"]
        if englishPlaylistIndicators.contains(where: { cleanLower.contains($0) }) {
            var clean = commandText
                .replacingOccurrences(of: "播放", with: "")
                .replacingOccurrences(of: "我想听", with: "")
                .replacingOccurrences(of: "放", with: "")
                .replacingOccurrences(of: "听", with: "")
            // 清理英文动词前缀
            for prefix in ["play ", "listen to ", "Play ", "Listen to "] {
                if clean.hasPrefix(prefix) {
                    clean = String(clean.dropFirst(prefix.count))
                    break
                }
            }
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                return .playPlaylist(name: clean, musicService: targetService, groupId: currentGroupId)
            }
        }

        // 10. 场景/氛围/纯音乐点播（如：“播放适合提高工作效率的纯音乐”、“适合雨天在咖啡馆听的背景音乐”、“放工作纯音乐”、“听点放松的轻音乐”）
        // 此类需求必须识别为连续播放歌单，杜绝单曲停播
        let isSceneMusic = sceneKeywords.contains { cleanLower.contains($0) }
        let hasPlayAction = ["我想听", "想听", "播放", "放", "听", "播", "来首", "来一首", "来点", "play", "listen to"].contains { cleanLower.contains($0) }
        let isScenePlaylistRequest = isSceneMusic && (hasPlayAction || cleanLower.contains("适合") || cleanLower.contains("背景音乐") || cleanLower.contains("歌单") || cleanLower.contains("电台") || cleanLower.contains("轻音乐") || cleanLower.contains("纯音乐"))

        if isScenePlaylistRequest {
            var playlistName = commandText
                .replacingOccurrences(of: "我想听", with: "")
                .replacingOccurrences(of: "想听", with: "")
                .replacingOccurrences(of: "播放", with: "")
                .replacingOccurrences(of: "来首", with: "")
                .replacingOccurrences(of: "来一首", with: "")
                .replacingOccurrences(of: "来点", with: "")
                .replacingOccurrences(of: "放", with: "")
                .replacingOccurrences(of: "听", with: "")
                .replacingOccurrences(of: "播", with: "")
            // 清理英文动词前缀
            for prefix in ["play ", "listen to ", "Play ", "Listen to "] {
                if playlistName.hasPrefix(prefix) {
                    playlistName = String(playlistName.dropFirst(prefix.count))
                    break
                }
            }
            playlistName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
            // 关键防护：过长的描述不是歌单名，不能发给 Sonos MCP 搜索（否则必然失败并触发 fallback 误显 LLM 行为）
            // 只有简短精炼的名称才作为歌单搜索词
            if !playlistName.isEmpty && playlistName.count <= 10 {
                return .playPlaylist(name: playlistName, musicService: targetService, groupId: currentGroupId)
            }
            // 超长场景描述：提取核心风格词（排除泛化描述词）作为精简歌单名
            if !playlistName.isEmpty && playlistName.count > 10 {
                let genericDescriptors = ["适合", "音乐", "歌曲", "背景", "电台", "歌单", "安静", "放松", "解压", "治愈", "催眠", "节奏", "旋律", "效率", "工作", "学习", "专注"]
                let pureStyleKeywords = sceneKeywords.filter { !genericDescriptors.contains($0) }
                let styleWords = pureStyleKeywords.filter { playlistName.contains($0) }
                if !styleWords.isEmpty {
                    let conciseName = styleWords.prefix(2).joined(separator: "")
                    return .playPlaylist(name: conciseName, musicService: targetService, groupId: currentGroupId)
                }
                // 无风格关键词可提取，不生成歌单意图，返回 nil 让调用方走收藏保底
            }
        }

        // 11. 点播歌手（如："播放周杰伦的歌"、"我想听周杰伦"、"play Taylor Swift"、"listen to Adele"、"点播 Michael Jackson"）
        let artistPatterns = [
            "^(?:我想听|想听|来点|点播|播放|放|听|播|来首|来一首)\\s*(.+?)(?:的歌|的歌曲|的音乐)?$",
            "^(?:play|listen to)\\s+(.+?)(?:'s\\s+songs?|\\s+songs?)?$"
        ]
        for pattern in artistPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: commandText, range: NSRange(commandText.startIndex..., in: commandText)),
               let range = Range(match.range(at: 1), in: commandText) {
                let target = String(commandText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                let targetLower = target.lowercased()
                let containsSceneWord = sceneKeywords.contains { targetLower.contains($0) }
                // 英文名称允许更长字符（如 "Taylor Swift" = 12），中文保持 8 字符限制
                let isEnglishName = !target.isEmpty && target.allSatisfy { $0.isASCII || $0.isWhitespace || $0 == "'" || $0 == "." || $0 == "-" }
                let maxLen = isEnglishName ? 30 : 8
                if !target.isEmpty && targetLower != "音乐" && targetLower != "music" && target != "歌" && !target.contains("暂停") && !target.contains("下一首") && !containsSceneWord && target.count <= maxLen {
                    return .playArtist(artist: target, musicService: targetService, groupId: currentGroupId)
                }
            }
        }

        return nil
    }

    /// 若配置了 LLM，通过大模型提取多个搜索候选词，逐个尝试直到命中真实曲库
    public static func routeWithLLM(
        prompt: String,
        tools: [MCPTool],
        apiKey: String,
        endpoint: String,
        customModel: String = "",
        preferredMusicService: String = "Apple Music",
        currentGroupId: String? = nil
    ) async throws -> LLMSearchResult? {
        guard !apiKey.isEmpty else { return nil }

        var baseUrl = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseUrl.isEmpty { baseUrl = "https://api.openai.com/v1" }
        if baseUrl.hasSuffix("/") { baseUrl.removeLast() }
        let fullUrlStr = baseUrl.hasSuffix("/chat/completions") ? baseUrl : "\(baseUrl)/chat/completions"
        guard let url = URL(string: fullUrlStr) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // 自动解析或使用用户指定的模型名称
        let modelName: String
        let trimmedCustom = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            modelName = trimmedCustom
        } else {
            let lower = baseUrl.lowercased()
            if lower.contains("deepseek") {
                modelName = "deepseek-chat"
            } else if lower.contains("dashscope") || lower.contains("aliyun") {
                modelName = "qwen-plus"
            } else if lower.contains("siliconflow") {
                modelName = "deepseek-ai/DeepSeek-V3"
            } else if lower.contains("moonshot") {
                modelName = "moonshot-v1-8k"
            } else if lower.contains("glm") || lower.contains("bigmodel") || lower.contains("zhipu") {
                modelName = "glm-4-flash"
            } else if lower.contains("groq") {
                modelName = "llama-3.1-8b-instant"
            } else {
                modelName = "gpt-4o-mini"
            }
        }

        // 双语 prompt：同时支持中文和英文音乐搜索
        let gidText = currentGroupId ?? ""
        let systemPrompt = """
        You are a Sonos music search assistant. Convert the user's music request into JSON search candidates. Respond in the same language as the user's input.
        你是 Sonos 音乐搜索助手。将用户的音乐需求转为 JSON 格式的搜索候选词。用与用户输入相同的语言回复。

        Rules / 规则:
        1. User mentions a specific artist → {"intent":"artist","candidates":["artist name"]}
           用户提到具体歌手 → {"intent":"artist","candidates":["歌手名"]}
        2. User mentions a specific song → {"intent":"track","candidates":["song name"],"artist":"artist name (if any)"}
           用户提到具体歌曲 → {"intent":"track","candidates":["歌曲名"],"artist":"歌手名(如有)"}
        3. User mentions a specific album → {"intent":"album","candidates":["album name"],"artist":"artist name (if any)"}
           用户提到具体专辑 → {"intent":"album","candidates":["专辑名"],"artist":"歌手名(如有)"}
        4. User describes style/scene/mood/language/vibe → {"intent":"playlist","candidates":["candidate1","candidate2","candidate3","candidate4"]}
           用户描述风格/场景/心情/语言/人声/氛围 → {"intent":"playlist","candidates":["候选1","候选2","候选3","候选4"]}
           Must provide 3-5 refined search terms (2-6 chars/words each), covering the user's intent from different angles.
           必须提供 3-5 个不同的精炼搜索词（2-6字），从不同角度覆盖用户意图。

        Candidate references (Apple Music / Spotify real playlist names) / 候选词参考:
        - Jazz / 爵士 → Jazz Vocals, A-List Jazz, Café Jazz, Smooth Jazz, Cool Jazz, Bossa Nova, 爵士女声, 咖啡馆爵士
        - Classical / 古典 → Classical Piano, Classical Essentials, 古典钢琴, 唯美钢琴
        - Electronic/Lo-Fi / 电子 → Lo-Fi Beats, Chillhop, Ambient, Deep Focus, 电子氛围
        - Café/Rainy / 咖啡馆 → Café Jazz, Rainy Day Bossa, 咖啡馆爵士, 午后爵士
        - Winter/Snow / 冬日 → Winter Jazz, Warm Folk, 雪夜爵士, 冬日暖阳
        - Work/Focus / 专注 → Deep Focus, Study Music, 专注工作, 学习纯音乐
        - Sleep / 助眠 → Deep Sleep, White Noise, Sleep Piano, 深睡纯音乐, 助眠白噪音
        - Relax / 放松 → Relaxation, Healing Music, 身心放松, 治愈系纯音乐
        - Workout / 运动 → Workout Hits, Running Beats, 运动燃脂, 健身流行
        - Night/Lounge / 夜晚 → Night Jazz, Lounge, 深夜爵士, 微醺之夜
        - Folk / 民谣 → Folk Essentials, Indie Folk, 民谣精选, 独立民谣
        - Rock / 摇滚 → Rock Classics, Rock Essentials, 摇滚经典, 另类摇滚
        - Pop / 流行 → Today's Hits, Pop Rising, 轻松流行
        - Blues / 蓝调 → Blues Essentials, 蓝调精选
        - Soul/R&B / 灵魂 → Neo Soul, R&B Classics, 灵魂乐精选, R&B 经典

        Forbidden generic terms / 禁止的泛化词: 流行精选, 热播金曲, 国语流行, 经典老歌, 欧美流行

        Current Group ID / 当前群组ID: \(gidText)
        Preferred Service / 首选服务: \(preferredMusicService)

        Output ONLY JSON, no other text. / 只输出 JSON，不要其他文字。
        """

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)

        // 解析 LLM 响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            return nil
        }

        // 方式一：解析 JSON 文本输出（新方式，推荐）
        if let textContent = message["content"] as? String, !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleaned = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            // 去除可能的 markdown 代码块包裹
            let jsonStr = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let jsonData = jsonStr.data(using: .utf8),
               let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let intent = result["intent"] as? String {

                var candidates: [String] = []
                if let cands = result["candidates"] as? [String] {
                    candidates = cands
                }

                // 非歌单意图：构造 primaryToolCall
                if intent != "playlist", !candidates.isEmpty {
                    var args: [String: AnyCodable] = [:]
                    if let gid = currentGroupId {
                        args["group_id"] = .string(gid)
                        args["groupId"] = .string(gid)
                    }

                    let musicService: String?
                    if let svc = result["music_service"] as? String {
                        musicService = svc
                        args["music_service"] = .string(svc)
                    } else {
                        musicService = preferredMusicService
                        args["music_service"] = .string(preferredMusicService)
                    }

                    args["shuffle"] = .bool(false)

                    switch intent {
                    case "artist":
                        args["artist"] = .string(candidates[0])
                        return LLMSearchResult(intent: intent, candidates: [], musicService: musicService,
                            primaryToolCall: ("play_artist", args))
                    case "track":
                        args["track"] = .string(candidates[0])
                        if let artist = result["artist"] as? String {
                            args["artist"] = .string(artist)
                        }
                        return LLMSearchResult(intent: intent, candidates: [], musicService: musicService,
                            primaryToolCall: ("play_track", args))
                    case "album":
                        args["album"] = .string(candidates[0])
                        if let artist = result["artist"] as? String {
                            args["artist"] = .string(artist)
                        }
                        return LLMSearchResult(intent: intent, candidates: [], musicService: musicService,
                            primaryToolCall: ("play_album", args))
                    default:
                        break
                    }
                }

                // 歌单意图：返回多个候选
                if intent == "playlist" && !candidates.isEmpty {
                    let musicService: String?
                    if let svc = result["music_service"] as? String {
                        musicService = svc
                    } else {
                        let lowerPrompt = prompt.lowercased()
                        if lowerPrompt.contains("spotify") {
                            musicService = "Spotify"
                        } else if lowerPrompt.contains("apple") || lowerPrompt.contains("苹果") {
                            musicService = "Apple Music"
                        } else {
                            musicService = preferredMusicService
                        }
                    }
                    return LLMSearchResult(intent: intent, candidates: candidates, musicService: musicService)
                }
            }
        }

        // 方式二：降级到 tool_calls 格式（兼容旧行为）
        if let toolCalls = message["tool_calls"] as? [[String: Any]],
           let firstCall = toolCalls.first,
           let function = firstCall["function"] as? [String: Any],
           let toolName = function["name"] as? String {

            var parsedArgs: [String: AnyCodable] = [:]
            if let argStr = function["arguments"] as? String,
               let argData = argStr.data(using: .utf8),
               let rawDict = try? JSONSerialization.jsonObject(with: argData) as? [String: Any] {
                parsedArgs = rawDict.mapValues { AnyCodable($0) }
            }

            if parsedArgs["group_id"] == nil && parsedArgs["groupId"] == nil, let gid = currentGroupId {
                parsedArgs["group_id"] = .string(gid)
                parsedArgs["groupId"] = .string(gid)
            }
            if toolName.contains("play") {
                if let shuffleVal = parsedArgs["shuffle"] {
                    switch shuffleVal {
                    case .bool: break
                    case .int(let i): parsedArgs["shuffle"] = .bool(i != 0)
                    default: parsedArgs["shuffle"] = .bool(false)
                    }
                } else {
                    parsedArgs["shuffle"] = .bool(false)
                }
            }
            if toolName.contains("play") && parsedArgs["music_service"] == nil {
                let lowerPrompt = prompt.lowercased()
                if lowerPrompt.contains("spotify") {
                    parsedArgs["music_service"] = .string("Spotify")
                } else if lowerPrompt.contains("apple") || lowerPrompt.contains("苹果") {
                    parsedArgs["music_service"] = .string("Apple Music")
                } else {
                    parsedArgs["music_service"] = .string(preferredMusicService)
                }
            }

            // 将 tool_calls 结果转换为 LLMSearchResult
            if toolName.contains("playlist") {
                let playlistName = parsedArgs["playlist"]?.stringValue ?? parsedArgs["playlistName"]?.stringValue ?? ""
                let svc = parsedArgs["music_service"]?.stringValue ?? preferredMusicService
                return LLMSearchResult(intent: "playlist", candidates: [playlistName], musicService: svc)
            } else {
                return LLMSearchResult(intent: "tool", candidates: [], musicService: nil,
                    primaryToolCall: (toolName, parsedArgs))
            }
        }

        return nil
    }
}
