import Foundation

// MARK: - Sonos MCP 客户端
public actor MCPClient {
    private var endpoint: URL
    private var bearerToken: String
    private var nextRequestId: Int = 1
    private let session: URLSession

    public init(endpoint: URL = URL(string: "https://mcp.ws.sonos.com/mcp")!, bearerToken: String = "") {
        self.endpoint = endpoint
        self.bearerToken = bearerToken

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: config)
    }

    public func updateConfig(endpoint: URL, bearerToken: String) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
    }

    private func generateId() -> Int {
        let reqId = nextRequestId
        nextRequestId += 1
        return reqId
    }

    // MARK: - 初始化握手
    public func initialize() async throws -> [String: AnyCodable] {
        struct ClientInfo: Codable, Sendable {
            let name: String
            let version: String
        }
        struct InitParams: Codable, Sendable {
            let protocolVersion: String
            let capabilities: [String: AnyCodable]
            let clientInfo: ClientInfo
        }

        let params = InitParams(
            protocolVersion: "2024-11-05",
            capabilities: [:],
            clientInfo: ClientInfo(name: "sonosBuddy", version: "1.0.0")
        )

        let req = JSONRPCRequest(id: generateId(), method: "initialize", params: params)
        let response: JSONRPCResponse<[String: AnyCodable]> = try await sendRequest(req)

        if let error = response.error {
            throw error
        }
        return response.result ?? [:]
    }

    // MARK: - 获取可用工具列表
    public func listTools() async throws -> [MCPTool] {
        struct EmptyParams: Codable, Sendable {}
        let req = JSONRPCRequest<EmptyParams>(id: generateId(), method: "tools/list", params: nil)
        let response: JSONRPCResponse<MCPToolsListResult> = try await sendRequest(req)

        if let error = response.error {
            throw error
        }
        return response.result?.tools ?? []
    }

    // MARK: - 调用指定工具
    public func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolCallResult {
        let params = MCPToolCallParams(name: name, arguments: arguments)
        let req = JSONRPCRequest(id: generateId(), method: "tools/call", params: params)
        let response: JSONRPCResponse<MCPToolCallResult> = try await sendRequest(req)

        // 优先使用 result（Sonos MCP 可能同时填充 result 和 error 字段）
        if let result = response.result {
            return result
        }
        // result 为 nil 时才视为真正的错误
        if let error = response.error {
            throw error
        }
        throw JSONRPCError(code: -32603, message: "返回结果为空", data: nil)
    }

    // MARK: - 从 Server-Sent Events (SSE) 或普通响应中提取纯 JSON
    private func extractJSON(from rawData: Data) -> Data {
        guard let text = String(data: rawData, encoding: .utf8) else { return rawData }

        // 如果包含 SSE 格式标志
        if text.contains("data:") {
            var jsonBuffer = ""
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("data:") {
                    let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if !payload.isEmpty {
                        jsonBuffer.append(payload)
                    }
                }
            }
            if let extractedData = jsonBuffer.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: extractedData)) != nil {
                return extractedData
            }
        }

        return rawData
    }

    // MARK: - 底层 HTTP JSON-RPC 发送
    private func sendRequest<P: Codable, R: Codable>(_ jsonRpcReq: JSONRPCRequest<P>) async throws -> JSONRPCResponse<R> {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        if !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(jsonRpcReq)

        // 仅在本地派发通知以统计请求次数，完全不产生额外网络开销
        NotificationCenter.default.post(name: NSNotification.Name("SonosMCPRequestSent"), object: nil)

        let (rawData, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 401 {
            throw JSONRPCError(code: 401, message: "Token 已失效或未授权，请重新在设置中点击 OAuth 授权", data: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: rawData, encoding: .utf8) ?? "未知错误"
            throw JSONRPCError(code: httpResponse.statusCode, message: "HTTP 错误: \(httpResponse.statusCode)", data: errorText)
        }

        // 解析并解构 SSE event-stream
        let jsonData = extractJSON(from: rawData)

        let decoder = JSONDecoder()
        return try decoder.decode(JSONRPCResponse<R>.self, from: jsonData)
    }
}
