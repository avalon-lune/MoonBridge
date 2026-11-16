import Foundation
import Security
import ImageIO

public struct CompanionSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var autoLookup = true
    public var webSearch = true
    public var baseURL = "https://api.openai.com/v1"
    public var model = "gpt-6.1-terra"
    public var reasoningEffort = "medium"
    public var proxyURL = ""
    public init() {}
}

public struct GameMetadata: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var originalTitle: String
    public var summary: String
    public var developer: String
    public var releaseDate: String
    public var tags: [String]
    public var sourceURL: String
    public var coverURL: String?
    public var coverPath: String?
    public var fetchedAt: Date
    /// The source text is retained separately when the displayed summary is rewritten by AI.
    public var originalSummary: String?
    public var summaryOrigin: String?
    public init(id: String = "", title: String = "", originalTitle: String = "", summary: String = "", developer: String = "", releaseDate: String = "", tags: [String] = [], sourceURL: String = "", coverURL: String? = nil, coverPath: String? = nil, fetchedAt: Date = Date(), originalSummary: String? = nil, summaryOrigin: String? = nil) {
        self.id = id; self.title = title; self.originalTitle = originalTitle; self.summary = summary
        self.developer = developer; self.releaseDate = releaseDate; self.tags = tags
        self.sourceURL = sourceURL; self.coverURL = coverURL; self.coverPath = coverPath; self.fetchedAt = fetchedAt
        self.originalSummary = originalSummary; self.summaryOrigin = summaryOrigin
    }
}

public struct SourceLink: Codable, Identifiable, Equatable, Sendable {
    public var id: String { url }
    public var title: String
    public var url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}

public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var role: String
    public var text: String
    public var sources: [SourceLink]
    public var createdAt: Date
    public var gameID: UUID?
    public var gameTitle: String?
    public init(id: UUID = UUID(), role: String, text: String, sources: [SourceLink] = [], createdAt: Date = Date(), gameID: UUID? = nil, gameTitle: String? = nil) {
        self.id = id; self.role = role; self.text = text; self.sources = sources; self.createdAt = createdAt
        self.gameID = gameID; self.gameTitle = gameTitle
    }
}

/// Companion data lives outside game content and Wine prefixes. Library version 1 is never rewritten here.
public struct CompanionStore: Sendable {
    public let paths: ProjectPaths
    public init(paths: ProjectPaths) { self.paths = paths }
    private func location(_ relative: String) throws -> URL {
        let root = paths.root.resolvingSymlinksInPath()
        let folder = paths.root.appendingPathComponent("Library/Companion")
        let target = folder.appendingPathComponent(relative)
        // Reject an existing symlink at any level, including a companion directory pointing into a game.
        var item = target
        while item.path.count > paths.root.path.count {
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw BridgeError("资料目录含有符号链接，已停止写入以保护游戏文件。")
            }
            item.deleteLastPathComponent()
        }
        guard target.resolvingSymlinksInPath().path.hasPrefix(root.path + "/Library/Companion/") else {
            throw BridgeError("资料存储路径无效。")
        }
        return target
    }
    private func read<T: Decodable>(_ type: T.Type, _ relative: String) throws -> T? {
        let url = try location(relative)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, _ relative: String) throws {
        let url = try location(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try location(relative)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    public func loadSettings() throws -> CompanionSettings { try read(CompanionSettings.self, "settings.json") ?? CompanionSettings() }
    public static func validateSettings(_ settings: CompanionSettings) throws {
        _ = try CompanionEndpoint.normalized(settings.baseURL)
        _ = try CompanionNetwork.configuration(settings: settings)
        guard !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.model.count <= 200 else { throw BridgeError("请填写有效的模型名称（最多200个字符）。") }
        guard ["none", "low", "medium", "high", "xhigh", "max"].contains(settings.reasoningEffort) else { throw BridgeError("推理强度无效，请重新选择。") }
    }
    public func saveSettings(_ settings: CompanionSettings) throws {
        try Self.validateSettings(settings)
        try write(settings, "settings.json")
    }
    public func loadMetadata(gameID: UUID) throws -> GameMetadata? { try read(GameMetadata.self, "metadata/\(gameID.uuidString).json") }
    public func saveMetadata(_ metadata: GameMetadata, gameID: UUID) throws { try write(metadata, "metadata/\(gameID.uuidString).json") }
    public func loadChat(gameID: UUID) throws -> [ChatMessage] { try read([ChatMessage].self, "chat/\(gameID.uuidString).json") ?? [] }
    public func saveChat(_ messages: [ChatMessage], gameID: UUID) throws { try write(messages, "chat/\(gameID.uuidString).json") }
    public func clearChat(gameID: UUID) throws {
        let url = try location("chat/\(gameID.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func saveCover(_ data: Data, gameID: UUID, fileExtension: String) throws -> String {
        let relative = "covers/\(gameID.uuidString)-\(UUID().uuidString).\(fileExtension)"
        let url = try location(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try location(relative)
        try data.write(to: url, options: .atomic)
        return "Library/Companion/" + relative
    }
}

public enum CompanionEndpoint {
    /// Canonical URL is also the Keychain account, preventing a newly entered endpoint from reusing another server's key.
    public static func normalized(_ value: String) throws -> String {
        guard var url = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !url.path.split(separator: "/").contains("..") else {
            throw BridgeError("API 地址须使用 HTTPS，且不能包含账号、查询参数或片段。请填写基础地址，例如 https://api.openai.com/v1。")
        }
        url.scheme = "https"; url.host = host.lowercased()
        if url.port == 443 { url.port = nil }
        while url.path.hasSuffix("/") { url.path.removeLast() }
        guard let result = url.string else { throw BridgeError("API 地址无效。") }
        return result
    }
    public static func isSafeLink(_ string: String) -> Bool {
        guard let c = URLComponents(string: string), c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil else { return false }
        return true
    }
}

public struct KeychainCredential {
    public init() {}
    private let service = "local.moonbridge.companion.api"
    private func query(_ baseURL: String) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: try CompanionEndpoint.normalized(baseURL)]
    }
    public func load(baseURL: String) throws -> String? {
        var q = try query(baseURL); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, let key = String(data: data, encoding: .utf8) else {
            throw BridgeError("无法读取月渡的钥匙串凭证（\(status)）。如出现系统提示，请允许月渡访问。")
        }
        return key
    }
    public func save(_ value: String, baseURL: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw BridgeError("API Key 为空或格式无效。") }
        var q = try query(baseURL)
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw BridgeError("无法更新钥匙串凭证（\(update)）。") }
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        q[kSecAttrLabel as String] = "月渡 · AI API"
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw BridgeError("无法保存钥匙串凭证（\(status)）。") }
    }
    public func delete(baseURL: String) throws {
        let status = SecItemDelete(try query(baseURL) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeError("无法移除钥匙串凭证（\(status)）。") }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum CompanionNetwork {
    static func configuration(settings: CompanionSettings) throws -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120; config.timeoutIntervalForResource = 120
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let proxy = settings.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proxy.isEmpty {
            guard let c = URLComponents(string: proxy), let host = c.host, let port = c.port, (1...65535).contains(port),
                  ["http", "https", "socks5"].contains(c.scheme ?? ""), c.user == nil, c.password == nil,
                  c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/" else {
                throw BridgeError("代理地址无效。请使用 http://127.0.0.1:7897 等不含账号口令的地址。")
            }
            if c.scheme == "socks5" {
                config.connectionProxyDictionary = ["SOCKSEnable": 1, "SOCKSProxy": host, "SOCKSPort": port]
            } else {
                config.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
                                                       "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port]
            }
        }
        return config
    }
    static func data(for request: URLRequest, settings: CompanionSettings, limit: Int) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: try configuration(settings: settings), delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw BridgeError("服务器未返回有效的 HTTP 响应。") }
            guard response.expectedContentLength <= Int64(limit) else { throw BridgeError("服务器返回的内容过大，下载已停止。") }
            var data = Data(); data.reserveCapacity(min(max(Int(response.expectedContentLength), 0), limit))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw BridgeError("服务器返回的内容过大，下载已停止。") }
                data.append(byte)
            }
            return (data, http)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw BridgeError("请求超时，请稍后重试或检查代理。") }
            // Never forward a URLSession error containing URL credentials or request headers.
            throw BridgeError("网络连接失败（\(error.code.rawValue)），请检查网络或代理设置。")
        }
    }
    static func request(_ url: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: url), CompanionEndpoint.isSafeLink(url.absoluteString) else { throw BridgeError("请求地址无效。") }
        var request = URLRequest(url: url); request.timeoutInterval = 120
        request.setValue("MoonBridge/0.2 (https://github.com/avalon-lune/MoonBridge)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
