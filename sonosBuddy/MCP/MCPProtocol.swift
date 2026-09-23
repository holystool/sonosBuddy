import Foundation

// MARK: - JSON-RPC 2.0 数据结构
// nonisolated: 退出 SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 的默认隔离，
// 确保 Codable 合成一致性与 Sendable 泛型约束在 actor 上下文中兼容
public nonisolated struct JSONRPCRequest<T: Codable>: Codable {
    public var jsonrpc: String = "2.0"
    public let id: Int
    public let method: String
    public let params: T?

    public init(id: Int, method: String, params: T? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public nonisolated struct JSONRPCResponse<T: Codable>: Codable {
    public let jsonrpc: String
    public let id: Int?
    public let result: T?
    public let error: JSONRPCError?
}

public struct JSONRPCError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: String?
}

// MARK: - MCP 工具定义
public nonisolated struct MCPTool: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String?
    public let inputSchema: [String: AnyCodable]?
}

public nonisolated struct MCPToolsListResult: Codable, Sendable {
    public let tools: [MCPTool]
    public let nextCursor: String?
}

public nonisolated struct MCPToolCallParams: Codable, Sendable {
    public let name: String
    public let arguments: [String: AnyCodable]

    public init(name: String, arguments: [String: AnyCodable] = [:]) {
        self.name = name
        self.arguments = arguments
    }
}

public nonisolated struct MCPContentItem: Codable, Sendable {
    public let type: String
    public let text: String?
}

public nonisolated struct MCPToolCallResult: Codable, Sendable {
    public let content: [MCPContentItem]?
    public let isError: Bool?

    public var resultText: String {
        return content?.compactMap { $0.text }.joined(separator: "\n") ?? ""
    }
}

// MARK: - 任意 JSON 编码辅助
public enum AnyCodable: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodable])
    case dictionary([String: AnyCodable])
    case null

    public init(_ value: Any) {
        if let str = value as? String {
            self = .string(str)
        } else if (value as AnyObject) is NSNumber && CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
            self = .bool((value as? Bool) ?? false)
        } else if let b = value as? Bool {
            self = .bool(b)
        } else if let i = value as? Int {
            self = .int(i)
        } else if let d = value as? Double {
            self = .double(d)
        } else if let arr = value as? [Any] {
            self = .array(arr.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            self = .dictionary(dict.mapValues { AnyCodable($0) })
        } else {
            self = .null
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? container.decode(String.self) {
            self = .string(val)
        } else if let val = try? container.decode(Int.self) {
            self = .int(val)
        } else if let val = try? container.decode(Double.self) {
            self = .double(val)
        } else if let val = try? container.decode([AnyCodable].self) {
            self = .array(val)
        } else if let val = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(val)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        default: return nil
        }
    }
}
