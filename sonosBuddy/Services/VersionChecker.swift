import Foundation
import Observation

/// GitHub Release 版本检测器
/// 启动时异步查询最新 Release，与本地版本号对比判断是否有更新
@MainActor
@Observable
final class VersionChecker {
    // MARK: - 配置
    private let repoOwner = "holystool"
    private let repoName = "sonosBuddy"
    private let currentVersion: String

    // MARK: - 状态
    private(set) var isChecking = false
    private(set) var hasUpdate = false
    private(set) var latestVersion = ""
    private(set) var releaseNotes = ""
    private(set) var releaseURL = ""
    private(set) var checkError: String?

    private var hasChecked = false

    init() {
        // 优先从 Info.plist 读取版本号，fallback 到硬编码
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.currentVersion = v
        } else {
            self.currentVersion = "1.0.0"
        }
    }

    var currentVersionDisplay: String { currentVersion }

    // MARK: - 公开方法

    /// 检查更新（仅首次调用时真正发起网络请求）
    func checkForUpdate() async {
        guard !hasChecked else { return }
        hasChecked = true
        isChecking = true
        checkError = nil

        let urlStr = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlStr) else {
            finishCheck(error: "无法构建请求 URL")
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpRes = response as? HTTPURLResponse else {
                finishCheck(error: "GitHub API 请求失败")
                return
            }

            // 404 = 尚未发布任何 Release，不算错误
            if httpRes.statusCode == 404 {
                isChecking = false
                return
            }

            guard httpRes.statusCode == 200 else {
                finishCheck(error: "GitHub API 请求失败")
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                finishCheck(error: "响应解析失败")
                return
            }

            let tagName = (json["tag_name"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let name = json["name"] as? String ?? ""
            let body = json["body"] as? String ?? ""
            let htmlURL = json["html_url"] as? String ?? ""

            latestVersion = tagName.isEmpty ? (name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))) : tagName
            releaseNotes = cleanReleaseNotes(body)
            releaseURL = htmlURL
            hasUpdate = compareVersions(latestVersion, currentVersion) > 0

            isChecking = false
        } catch {
            finishCheck(error: error.localizedDescription)
        }
    }

    // MARK: - 私有方法

    private func finishCheck(error: String) {
        checkError = error
        isChecking = false
    }

    /// 清理 Markdown 格式的 Release Notes，转为纯文本
    private func cleanReleaseNotes(_ raw: String) -> String {
        var text = raw
        // 移除 Markdown 标题标记
        text = text.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        // 移除粗体/斜体标记
        text = text.replacingOccurrences(of: #"[*_]{1,3}(.*?)[*_]{1,3}"#, with: "$1", options: .regularExpression)
        // 移除 Markdown 链接，保留文字
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        // 移除列表标记
        text = text.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "• ", options: .regularExpression)
        // 移除多余空行
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 语义化版本号比较：返回 1 表示 a > b，-1 表示 a < b，0 表示相等
    private func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        let count = max(pa.count, pb.count)
        for i in 0..<count {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va > vb { return 1 }
            if va < vb { return -1 }
        }
        return 0
    }
}
