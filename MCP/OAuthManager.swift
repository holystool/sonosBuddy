import Foundation
import Network
import CryptoKit
import AppKit

// MARK: - Sonos 27mcp 官方 OAuth 2.1 + PKCE 授权管理器
public actor OAuthManager {
    public static let shared = OAuthManager()

    private var listener: NWListener?
    private var codeVerifier: String = ""
    private let redirectPort: UInt16 = 8989
    private var redirectUri: String { "http://localhost:\(redirectPort)/callback" }

    // Sonos 27mcp 官方 OAuth 端点 (由 /.well-known/oauth-authorization-server 验证)
    private let authServerUrl = "https://mcp.ws.sonos.com"
    private let authEndpoint = "https://mcp.ws.sonos.com/mcp-oauth/authorize"
    private let tokenEndpoint = "https://mcp.ws.sonos.com/mcp-oauth/token"
    private let registerEndpoint = "https://mcp.ws.sonos.com/mcp-oauth/register"

    private init() {}

    // MARK: - RFC 7591 动态客户端注册 (Dynamic Client Registration)
    private func getOrRegisterClientId() async throws -> String {
        let key = "SonosBuddy_OAuth_ClientId"
        if let savedId = UserDefaults.standard.string(forKey: key), !savedId.isEmpty {
            return savedId
        }

        let url = URL(string: registerEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_name": "sonosBuddy",
            "redirect_uris": [redirectUri],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let errStr = String(data: data, encoding: .utf8) ?? "未知错误"
            throw NSError(domain: "OAuthRegisterError", code: 400, userInfo: [NSLocalizedDescriptionKey: "动态注册客户端失败: \(errStr)"])
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let clientId = json["client_id"] as? String {
            UserDefaults.standard.set(clientId, forKey: key)
            return clientId
        }

        throw NSError(domain: "OAuthRegisterError", code: 400, userInfo: [NSLocalizedDescriptionKey: "注册响应中未返回 client_id"])
    }

    // MARK: - PKCE 随机验证串与哈希挑战生成
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 启动 OAuth 2.1 浏览器授权
    public func startAuthorization() async throws -> String {
        stopListener()

        // 1. 获取或动态注册 client_id
        let clientId = try await getOrRegisterClientId()

        // 2. 生成 PKCE 与 state
        self.codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = UUID().uuidString

        // 3. 构造 Sonos 官方 mcp-oauth/authorize 授权请求 URL
        var components = URLComponents(string: authEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authUrl = components.url else {
            throw URLError(.badURL)
        }

        // 4. 启动本地监听器等待浏览器重定向回调
        let authCode = try await withCheckedThrowingContinuation { continuation in
            do {
                let params = NWParameters.tcp
                let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: self.redirectPort)!)
                self.listener = listener

                listener.newConnectionHandler = { connection in
                    connection.start(queue: .global())
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, _ in
                        guard let data = data, let reqStr = String(data: data, encoding: .utf8) else { return }

                        // 提取 code 参数
                        if let range = reqStr.range(of: "code="),
                           let endRange = reqStr[range.upperBound...].range(of: "&") ?? reqStr[range.upperBound...].range(of: " ") {
                            let code = String(reqStr[range.upperBound..<endRange.lowerBound])

                            let successHtml = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><head><meta charset=\"utf-8\"><title>sonosBuddy 授权成功</title></head><body style=\"font-family: -apple-system, sans-serif; text-align: center; padding: 60px; background: #0A0A0A; color: #FFFFFF;\"><div style=\"max-width: 480px; margin: 0 auto; padding: 40px; border-radius: 16px; background: #171717; border: 1px solid #262626;\"><h2 style=\"color: #10B981; font-size: 24px; margin-bottom: 12px;\">🎉 Sonos 授权成功！</h2><p style=\"color: #A3A3A3; font-size: 14px; line-height: 1.6;\">sonosBuddy 已自动接收授权凭据并连接至您的 Sonos 系统。<br/>您可以关闭此浏览器窗口，返回菜单栏开始享受音乐。</p></div></body></html>"
                            connection.send(content: successHtml.data(using: .utf8), completion: .contentProcessed { _ in
                                connection.cancel()
                            })

                            continuation.resume(returning: code)
                            listener.cancel()
                        }
                    }
                }

                listener.start(queue: .global())

                // 调起默认浏览器访问 Sonos 官方授权页
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(authUrl)
                }

            } catch {
                continuation.resume(throwing: error)
            }
        }

        // 5. 用 Code 换取 Access Token
        return try await exchangeCodeForToken(code: authCode, clientId: clientId)
    }

    // MARK: - Code 换取 Token
    private func exchangeCodeForToken(code: String, clientId: String) async throws -> String {
        let url = URL(string: tokenEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type=authorization_code",
            "client_id=\(clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
            "redirect_uri=\(redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
            "code_verifier=\(codeVerifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        ].joined(separator: "&")

        request.httpBody = bodyParams.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? "未知错误"
            throw NSError(domain: "OAuthTokenError", code: 400, userInfo: [NSLocalizedDescriptionKey: "换取 Token 失败: \(err)"])
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accessToken = json["access_token"] as? String {
            if let refreshToken = json["refresh_token"] as? String {
                UserDefaults.standard.set(refreshToken, forKey: "SonosBuddy_OAuth_RefreshToken")
            }
            return accessToken
        }

        throw NSError(domain: "OAuthTokenError", code: 400, userInfo: [NSLocalizedDescriptionKey: "响应中未找到 access_token"])
    }

    // MARK: - 使用 refresh_token 换取新的 access_token
    public func refreshAccessToken() async throws -> String {
        guard let refreshToken = UserDefaults.standard.string(forKey: "SonosBuddy_OAuth_RefreshToken"), !refreshToken.isEmpty else {
            throw NSError(domain: "OAuthRefreshError", code: 401, userInfo: [NSLocalizedDescriptionKey: "无可用的 refresh token，请重新授权"])
        }

        let clientId = try await getOrRegisterClientId()

        let url = URL(string: tokenEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type=refresh_token",
            "client_id=\(clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        ].joined(separator: "&")

        request.httpBody = bodyParams.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? "未知错误"
            throw NSError(domain: "OAuthRefreshError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Token 刷新失败: \(err)"])
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accessToken = json["access_token"] as? String {
            // 若服务端返回了新的 refresh_token，更新本地存储
            if let newRefreshToken = json["refresh_token"] as? String {
                UserDefaults.standard.set(newRefreshToken, forKey: "SonosBuddy_OAuth_RefreshToken")
            }
            return accessToken
        }

        throw NSError(domain: "OAuthRefreshError", code: 400, userInfo: [NSLocalizedDescriptionKey: "刷新响应中未找到 access_token"])
    }

    public func stopListener() {
        listener?.cancel()
        listener = nil
    }
}
