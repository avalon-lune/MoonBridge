import Foundation
import ImageIO

public enum GameCatalog {
    public static func cleanedQuery(_ query: String) -> String {
        var value = URL(fileURLWithPath: query).lastPathComponent
        for ext in [".zip", ".7z", ".rar", ".exe"] where value.lowercased().hasSuffix(ext) { value.removeLast(ext.count) }
        value = value.replacingOccurrences(of: #"[\[【（(][^\]】）)]*[\]】）)]"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(免安装|硬盘版|汉化版|漢化版|中文整合版|完整汉化|简体中文|繁體中文|解压版|PC版|v\d+(\.\d+)+)"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(200))
    }
    public static func search(query: String, settings: CompanionSettings) async throws -> [GameMetadata] {
        guard settings.enabled else { throw BridgeError("资料与 AI 功能已关闭，可在设置中开启。") }
        let query = cleanedQuery(query)
        guard !query.isEmpty else { throw BridgeError("请填写游戏名称。") }
        async let first = attempt { try await searchVNDB(query, settings: settings) }
        async let second = attempt { try await searchBangumi(query, settings: settings) }
        let (vndb, bangumi) = await (first, second)
        try Task.checkCancellation()
        if case .failure = vndb, case .failure = bangumi {
            throw BridgeError("VNDB 和 Bangumi 暂时无法连接，请检查代理或稍后重试。游戏仍可离线启动。")
        }
        let values = ((try? vndb.get()) ?? []) + ((try? bangumi.get()) ?? [])
        var seen = Set<String>()
        let unique = values.filter { seen.insert($0.id).inserted }
        return unique.enumerated().sorted { a, b in
            func rank(_ item: GameMetadata) -> Int {
                let title = item.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let original = item.originalTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                return title == q || original == q ? 0 : title.contains(q) || original.contains(q) ? 1 : 2
            }
            let ra = rank(a.element), rb = rank(b.element)
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
    }
    private static func attempt<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    private static func searchVNDB(_ query: String, settings: CompanionSettings) async throws -> [GameMetadata] {
        let fields = "title,alttitle,titles.title,titles.lang,description,released,image.url,developers.name,tags.name,tags.spoiler,tags.lie,tags.rating"
        var request = try CompanionNetwork.request("https://api.vndb.org/kana/vn", body: ["filters": ["search", "=", query], "fields": fields, "sort": "searchrank", "results": 6])
        request.timeoutInterval = 35
        let (data, response) = try await CompanionNetwork.data(for: request, settings: settings, limit: 2 * 1024 * 1024)
        guard response.statusCode == 200 else { throw BridgeError("VNDB 暂时不可用（HTTP \(response.statusCode)）。") }
        return try parseVNDB(data)
    }
    public static func parseVNDB(_ data: Data) throws -> [GameMetadata] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let values = object["results"] as? [[String: Any]] else {
            throw BridgeError("VNDB 返回格式无效。")
        }
        return values.compactMap { item in
            guard let id = item["id"] as? String, id.range(of: #"^v[0-9]+$"#, options: .regularExpression) != nil else { return nil }
            let titles = item["titles"] as? [[String: Any]] ?? []
            let chinese = titles.first { ($0["lang"] as? String)?.hasPrefix("zh") == true }?["title"] as? String
            let title = chinese ?? (item["alttitle"] as? String) ?? (item["title"] as? String) ?? ""
            guard !title.isEmpty else { return nil }
            let developers = (item["developers"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / ")
            let tags = (item["tags"] as? [[String: Any]] ?? []).filter { ($0["spoiler"] as? Double ?? 0) == 0 && ($0["lie"] as? Bool ?? false) == false }
                .sorted { ($0["rating"] as? Double ?? 0) > ($1["rating"] as? Double ?? 0) }.compactMap { item -> String? in
                    guard let name = item["name"] as? String else { return nil }
                    // Show broad genre labels, leaving plot, route structure and adult-content tags off the overview.
                    let genres = ["Mystery": "悬疑", "Romance": "恋爱", "Comedy": "喜剧", "Drama": "剧情", "Fantasy": "奇幻",
                                  "Supernatural": "超自然", "School Life": "校园", "Slice of Life": "日常", "Science Fiction": "科幻",
                                  "Adventure": "冒险", "Action": "动作", "Horror": "恐怖", "Thriller": "惊悚"]
                    return genres[name]
                }
            let image = (item["image"] as? [String: Any])?["url"] as? String
            return GameMetadata(id: id, title: title, originalTitle: (item["alttitle"] as? String) ?? (item["title"] as? String) ?? title,
                                summary: cleanDescription(item["description"] as? String ?? ""), developer: developers,
                                releaseDate: item["released"] as? String ?? "", tags: tags.isEmpty ? ["视觉小说"] : Array(tags.prefix(8)),
                                sourceURL: "https://vndb.org/" + id, coverURL: image)
        }
    }
    private static func searchBangumi(_ query: String, settings: CompanionSettings) async throws -> [GameMetadata] {
        var request = try CompanionNetwork.request("https://api.bgm.tv/v0/search/subjects?limit=6", body: ["keyword": query, "sort": "match", "filter": ["type": [4]]])
        request.timeoutInterval = 35
        let (data, response) = try await CompanionNetwork.data(for: request, settings: settings, limit: 2 * 1024 * 1024)
        guard response.statusCode == 200 else { throw BridgeError("Bangumi 暂时不可用（HTTP \(response.statusCode)）。") }
        return try parseBangumi(data)
    }
    public static func parseBangumi(_ data: Data) throws -> [GameMetadata] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let values = object["data"] as? [[String: Any]] else { throw BridgeError("Bangumi 返回格式无效。") }
        return values.compactMap { item in
            guard let id = item["id"] as? Int, id > 0, (item["type"] as? Int ?? 4) == 4 else { return nil }
            let original = item["name"] as? String ?? ""
            let chinese = item["name_cn"] as? String ?? ""
            let title = chinese.isEmpty ? original : chinese
            guard !title.isEmpty else { return nil }
            let image = item["images"] as? [String: Any] ?? [:]
            let infobox = item["infobox"] as? [[String: Any]] ?? []
            let developer = infobox.first { ["开发", "开发商", "游戏开发商"].contains($0["key"] as? String ?? "") }?["value"] as? String ?? ""
            // Free-form Bangumi tags may reveal plot; keep only format/platform tags in the default page.
            let tags = (item["tags"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                .filter { ["galgame", "adv", "pc", "windows", "视觉小说", "文字冒险"].contains($0.lowercased()) }
            return GameMetadata(id: "bgm:\(id)", title: title, originalTitle: original,
                                summary: cleanDescription(item["summary"] as? String ?? ""), developer: developer,
                                releaseDate: item["date"] as? String ?? "", tags: Array(tags.prefix(8)),
                                sourceURL: "https://bgm.tv/subject/\(id)", coverURL: (image["large"] as? String) ?? (image["common"] as? String))
        }
    }
    public static func enrichedMetadata(_ metadata: GameMetadata, settings: CompanionSettings) async throws -> GameMetadata {
        guard settings.enabled else { throw BridgeError("资料与 AI 功能已关闭。") }
        guard metadata.id.hasPrefix("bgm:") else { return metadata }
        let identifier = String(metadata.id.dropFirst(4))
        guard identifier.range(of: #"^[0-9]{1,12}$"#, options: .regularExpression) != nil else { throw BridgeError("Bangumi 条目编号无效。") }
        var request = try CompanionNetwork.request("https://api.bgm.tv/v0/subjects/" + identifier)
        request.timeoutInterval = 35
        let (data, response) = try await CompanionNetwork.data(for: request, settings: settings, limit: 2 * 1024 * 1024)
        guard response.statusCode == 200 else { throw BridgeError("Bangumi 详情暂不可用（HTTP \(response.statusCode)），已保留检索资料。") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BridgeError("Bangumi 详情格式无效。") }
        let wrapped = try JSONSerialization.data(withJSONObject: ["data": [object]])
        guard var enriched = try parseBangumi(wrapped).first, enriched.id == metadata.id else { throw BridgeError("Bangumi 详情与选择的作品不一致。") }
        enriched.coverPath = metadata.coverPath
        return enriched
    }
    public static func cleanDescription(_ text: String) -> String {
        var text = text.replacingOccurrences(of: #"(?is)\[spoiler(?:=[^\]]*)?\].*?\[/spoiler\]"#, with: "（剧透内容已隐藏）", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[/?(?:url|b|i|u|s|raw|quote|code|list|item|align|color|size)(?:=[^\]]*)?\]"#, with: "", options: .regularExpression)
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6000))
    }
    public static func isAllowedCoverURL(_ string: String) -> Bool {
        guard CompanionEndpoint.isSafeLink(string), let url = URL(string: string), url.port == nil || url.port == 443 else { return false }
        // API-provided images only, never arbitrary URLs supplied by a model.
        return ["s.vndb.org", "t.vndb.org", "lain.bgm.tv"].contains(url.host?.lowercased() ?? "")
    }
    public static func cacheCover(_ metadata: GameMetadata, gameID: UUID, paths: ProjectPaths, settings: CompanionSettings) async throws -> GameMetadata {
        guard settings.enabled else { throw BridgeError("资料与 AI 功能已关闭。") }
        guard let cover = metadata.coverURL, !cover.isEmpty else { return metadata }
        guard isAllowedCoverURL(cover) else { throw BridgeError("封面地址不属于受支持的资料来源，已保留原有封面。") }
        var request = try CompanionNetwork.request(cover); request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await CompanionNetwork.data(for: request, settings: settings, limit: 8 * 1024 * 1024)
        guard response.statusCode == 200, response.mimeType?.hasPrefix("image/") == true else { throw BridgeError("封面未能下载，游戏资料仍可保存。") }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 40_000_000,
              let type = CGImageSourceGetType(source) as String?, ["public.jpeg", "public.png", "org.webmproject.webp", "com.compuserve.gif"].contains(type),
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else {
            throw BridgeError("下载的封面不是受支持的图片。")
        }
        try Task.checkCancellation()
        let ext = type == "public.jpeg" ? "jpg" : type == "public.png" ? "png" : type == "com.compuserve.gif" ? "gif" : "webp"
        var result = metadata
        result.coverPath = try CompanionStore(paths: paths).saveCover(data, gameID: gameID, fileExtension: ext)
        return result
    }
}
