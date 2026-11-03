import Foundation

public struct BridgeError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct ProjectPaths: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL }
    public var libraryFile: URL { root.appendingPathComponent("Library/library.json") }
    public var sevenZip: URL { root.appendingPathComponent("Runtime/Tools/7zz") }
    public func makeDirectories() throws {
        for folder in ["Library/Games", "Library/Prefixes", "Library/Logs", "Library/Backups", "Library/Cache", "Library/Manifests"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }
    public func url(_ relative: String) throws -> URL {
        guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw BridgeError("项目路径无效。") }
        let value = root.appendingPathComponent(relative).standardizedFileURL
        guard value.path.hasPrefix(root.path + "/") else { throw BridgeError("路径超出项目目录。") }
        return value
    }
    public func relative(_ url: URL) throws -> String {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root.path + "/") else { throw BridgeError("文件不在 MoonBridge 项目中。") }
        return String(path.dropFirst(root.path.count + 1))
    }
    public func prefix(_ id: UUID) -> URL { root.appendingPathComponent("Library/Prefixes/" + id.uuidString) }
    public func content(_ id: UUID) -> URL { root.appendingPathComponent("Library/Games/" + id.uuidString + "/content") }
    public func log(_ id: UUID) -> URL { root.appendingPathComponent("Library/Logs/" + id.uuidString + ".log") }
}

public enum GameLocale: String, Codable, CaseIterable, Identifiable, Sendable {
    case japanese, chinese, english
    public var id: String { rawValue }
    public var title: String { switch self { case .japanese: "日文 · 日本区域"; case .chinese: "简体中文 · 中国区域"; case .english: "英文 · 美国区域" } }
    public var unix: String { switch self { case .japanese: "ja_JP.UTF-8"; case .chinese: "zh_CN.UTF-8"; case .english: "en_US.UTF-8" } }
    public var windows: String { switch self { case .japanese: "ja-JP"; case .chinese: "zh-CN"; case .english: "en-US" } }
    public var codePage: String { switch self { case .japanese: "932"; case .chinese: "936"; case .english: "1252" } }
    public var localeID: String { switch self { case .japanese: "00000411"; case .chinese: "00000804"; case .english: "00000409" } }
}
public enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case game, desktop
    public var id: String { rawValue }
    public var title: String { self == .game ? "跟随游戏（支持游戏内全屏）" : "虚拟桌面（适合黑屏或窗口异常）" }
}
public struct GameProfile: Codable, Equatable, Sendable {
    public var locale: GameLocale = .japanese
    public var display: DisplayMode = .game
    public var width: Int = 1280
    public var height: Int = 720
    public var windowsVersion: String = "win10"
    public init() {}
}
public struct ExecutableCandidate: Codable, Identifiable, Equatable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let name: String
    public let architecture: String
    public let score: Int
    public let isInstaller: Bool
    public let reason: String
    public init(relativePath: String, name: String, architecture: String, score: Int, isInstaller: Bool, reason: String) {
        self.relativePath = relativePath; self.name = name; self.architecture = architecture
        self.score = score; self.isInstaller = isInstaller; self.reason = reason
    }
}
public struct Game: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let importedAt: Date
    public var lastPlayedAt: Date?
    public var engine: String
    public var candidates: [ExecutableCandidate]
    public var selectedExecutable: String
    public var bundledPatches: [String]
    public var profile: GameProfile
    public var sizeBytes: Int64
    public var lastResult: String
    public var coverPath: String? = nil
    public var validation: [String: Bool] = [:]
    public init(id: UUID, title: String, engine: String, candidates: [ExecutableCandidate], bundledPatches: [String], sizeBytes: Int64) {
        self.id = id; self.title = title; self.engine = engine; self.candidates = candidates
        self.selectedExecutable = candidates.first?.relativePath ?? ""; self.bundledPatches = bundledPatches
        self.sizeBytes = sizeBytes; self.profile = GameProfile(); self.importedAt = Date()
        self.lastResult = candidates.isEmpty ? "待选择主程序" : "待验证"
    }
    public var selected: ExecutableCandidate? { candidates.first { $0.relativePath == selectedExecutable } }
}
public struct LibraryDocument: Codable, Sendable {
    public var version = 1
    public var games: [Game] = []
    public init(games: [Game] = []) { self.games = games }
    public static func load(from paths: ProjectPaths) throws -> LibraryDocument {
        guard FileManager.default.fileExists(atPath: paths.libraryFile.path) else { return LibraryDocument() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryDocument.self, from: Data(contentsOf: paths.libraryFile))
    }
    public func save(to paths: ProjectPaths) throws {
        try paths.makeDirectories()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: paths.libraryFile, options: .atomic)
    }
}
public struct ImportOptions: Sendable {
    public var password = ""
    public var filenameCodePage = ""
    public init(password: String = "", filenameCodePage: String = "") { self.password = password; self.filenameCodePage = filenameCodePage }
}

public enum PEInspector {
    public static func architecture(of data: Data) -> String? {
        guard data.count >= 64, data[0] == 0x4d, data[1] == 0x5a else { return nil }
        let offset = (0..<4).reduce(0) { $0 | (Int(data[0x3c + $1]) << ($1 * 8)) }
        guard offset >= 64, offset <= data.count - 6,
              Array(data[offset..<(offset + 4)]) == [0x50, 0x45, 0, 0] else { return nil }
        switch Int(data[offset + 4]) | Int(data[offset + 5]) << 8 {
        case 0x014c: return "x86 · 32 位"
        case 0x8664: return "x64 · 64 位"
        case 0xaa64: return "ARM64 · 暂不支持"
        default: return nil
        }
    }
    public static func architecture(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024 * 1024) else { return nil }
        return architecture(of: data)
    }
}

public struct ScanResult: Sendable {
    public var candidates: [ExecutableCandidate] = []
    public var patches: [String] = []
    public var engine = "Windows 通用引擎"
    public var bytes: Int64 = 0
    public var fileCount = 0
}
public enum GameScanner {
    public static func scan(directory: URL, paths: ProjectPaths) throws -> ScanResult {
        var result = ScanResult()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return result }
        var names = Set<String>()
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            result.fileCount += 1
            guard result.fileCount <= 200_000 else { throw BridgeError("文件数量过多，请只导入单个游戏目录。") }
            let name = file.lastPathComponent.lowercased(); names.insert(name)
            guard values.isRegularFile == true else { continue }
            result.bytes += Int64(values.fileSize ?? 0)
            if ["zip", "7z", "rar"].contains(file.pathExtension.lowercased()) {
                result.patches.append(try paths.relative(file))
            }
            guard file.pathExtension.lowercased() == "exe", let arch = PEInspector.architecture(at: file), !arch.contains("ARM64") else { continue }
            let installer = ["setup", "install", "autorun"].contains { name.hasPrefix($0) }
            let utility = ["unins", "uninstall", "vcredist", "dxsetup", "crash", "report", "redist", "update", "config", "setting"].contains { name.contains($0) }
            let depth = file.path.dropFirst(directory.path.count).filter { $0 == "/" }.count
            var score = 100 - depth * 8 - (installer ? 70 : 0) - (utility ? 140 : 0)
            if ["game.exe", "start.exe", "play.exe"].contains(name) { score += 22 }
            if name.contains("chs") || name.contains("cn") || name.contains("汉化") || name.contains("中文") { score += 12 }
            let reason = utility ? "配置 / 依赖 / 辅助程序" : installer ? "安装程序：安装后请重新扫描" : "Windows 游戏候选程序"
            result.candidates.append(ExecutableCandidate(relativePath: try paths.relative(file), name: file.lastPathComponent, architecture: arch, score: score, isInstaller: installer, reason: reason))
        }
        if names.contains(where: { $0.hasSuffix(".xp3") }) { result.engine = "KiriKiri / 吉里吉里" }
        else if names.contains("renpy") { result.engine = "Ren’Py" }
        else if names.contains("nscript.dat") || names.contains("0.txt") || names.contains("nscr_sec.dat") { result.engine = "NScripter" }
        else if names.contains("siglusengine.exe") || names.contains("scene.pck") { result.engine = "SiglusEngine" }
        else if names.contains("unityplayer.dll") { result.engine = "Unity" }
        else if names.contains("rpg_rt.exe") || names.contains("game.rgss3a") || names.contains("package.json") { result.engine = "RPG Maker / NW.js" }
        else if names.contains("tyrano") { result.engine = "TyranoScript" }
        result.candidates.sort { $0.score == $1.score ? $0.relativePath < $1.relativePath : $0.score > $1.score }
        result.patches.sort()
        return result
    }
}
