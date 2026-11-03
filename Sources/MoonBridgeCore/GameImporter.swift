import Foundation

public enum ArchiveGuard {
    public static func validate(path: String) throws {
        let normal = path.replacingOccurrences(of: "\\", with: "/")
        guard !normal.isEmpty, !normal.hasPrefix("/"), !normal.contains("\0"),
              !normal.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !normal.contains(":") else { throw BridgeError("压缩包包含不安全的文件路径：\(path)") }
    }
    public static func validateListing(_ listing: String) throws -> Int {
        var count = 0; var bytes: Int64 = 0
        for line in listing.components(separatedBy: .newlines) {
            if line.hasPrefix("Path = ") { try validate(path: String(line.dropFirst(7))); count += 1 }
            if line.hasPrefix("Size = ") { bytes += Int64(line.dropFirst(7)) ?? 0 }
            if line.hasPrefix("Symbolic Link = ") || line.hasPrefix("Hard Link = ") {
                throw BridgeError("暂不导入含符号链接或硬链接的压缩包，请使用完整的普通游戏目录。")
            }
            if line.hasPrefix("Attributes = "), line.contains("lrwx") { throw BridgeError("压缩包包含符号链接。") }
        }
        guard count > 0 else { throw BridgeError("压缩包为空，或无法读取目录。若有密码，请填写解压密码。") }
        guard count <= 200_000, bytes <= 120 * 1024 * 1024 * 1024 else { throw BridgeError("压缩包超过单款游戏导入上限（20 万文件 / 120 GB）。") }
        return count
    }
}

public struct GameImporter: Sendable {
    public let paths: ProjectPaths
    public init(paths: ProjectPaths) { self.paths = paths }
    public func extract(_ archive: URL, to destination: URL, options: ImportOptions) throws {
        guard FileManager.default.isExecutableFile(atPath: paths.sevenZip.path) else { throw BridgeError("解压工具未就绪，请在运行环境页面检查 7-Zip。") }
        var flags = ["-sccUTF-8", "-bd", "-p" + options.password]
        if !options.filenameCodePage.isEmpty { flags.append("-mcp=" + options.filenameCodePage) }
        let listing = try ProcessRunner.run(paths.sevenZip, ["l", "-slt", "-ba"] + flags + [archive.path], timeout: 180)
        guard listing.code == 0 || listing.code == 1 else { throw BridgeError("无法读取压缩包。请检查密码、分卷是否齐全或文件是否损坏。\n" + String(listing.output.suffix(1500))) }
        _ = try ArchiveGuard.validateListing(listing.output)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let result = try ProcessRunner.run(paths.sevenZip, ["x", "-y", "-aoa", "-bso0", "-bsp0", "-o" + destination.path] + flags + [archive.path], timeout: 3600)
        guard result.code == 0 else { throw BridgeError("解压未完成，请检查密码、磁盘空间或分卷文件。\n" + String(result.output.suffix(1800))) }
        try rejectLinks(in: destination)
    }
    public func importGame(from source: URL, options: ImportOptions = ImportOptions(), progress: @Sendable (String) -> Void = { _ in }) throws -> Game {
        try paths.makeDirectories()
        let source = source.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw BridgeError("找不到导入文件。") }
        let id = UUID(); let gameFolder = paths.content(id).deletingLastPathComponent()
        let staging = gameFolder.appendingPathComponent("importing")
        let final = paths.content(id)
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: gameFolder) } }
        var title = source.deletingPathExtension().lastPathComponent
        if isDirectory.boolValue {
            guard !source.path.hasPrefix(paths.root.path + "/") else { throw BridgeError("请导入原始游戏包，避免再次导入 MoonBridge 自己的目录。") }
            progress("正在复制游戏文件，保留原始目录…")
            try FileManager.default.copyItem(at: source, to: staging)
            title = source.lastPathComponent
        } else if ["zip", "7z", "rar"].contains(source.pathExtension.lowercased()) {
            progress("正在检查并解压游戏包…")
            try extract(source, to: staging, options: options)
        } else if source.pathExtension.lowercased() == "exe" {
            let parent = source.deletingLastPathComponent()
            guard !["Downloads", "Desktop", "Documents", "Applications"].contains(parent.lastPathComponent), parent.path != NSHomeDirectory() else {
                throw BridgeError("EXE 需要同目录的游戏资源。请把单款游戏放进独立文件夹后导入，或直接选择游戏压缩包。")
            }
            progress("正在导入 EXE 所在的完整游戏目录…")
            try FileManager.default.copyItem(at: parent, to: staging)
            title = parent.lastPathComponent
        } else { throw BridgeError("请选择 ZIP / 7Z / RAR、完整游戏文件夹或 Windows EXE。") }
        try rejectLinks(in: staging)
        try FileManager.default.moveItem(at: staging, to: final)
        progress("正在识别主程序、引擎与附带补丁…")
        let scan = try GameScanner.scan(directory: final, paths: paths)
        let game = Game(id: id, title: title, engine: scan.engine, candidates: scan.candidates, bundledPatches: scan.patches, sizeBytes: scan.bytes)
        let manifest: [String: Any] = ["id": id.uuidString, "importedAt": ISO8601DateFormatter().string(from: Date()), "sourceName": source.lastPathComponent, "fileCount": scan.fileCount, "bytes": scan.bytes, "engine": scan.engine, "executables": scan.candidates.map(\.relativePath), "note": "原始文件未修改。密码不保存。"]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: paths.root.appendingPathComponent("Library/Manifests/" + id.uuidString + ".json"), options: .atomic)
        committed = true
        progress("导入完成")
        return game
    }
    public func rescan(_ game: Game) throws -> Game {
        var value = game
        var scan = try GameScanner.scan(directory: paths.content(game.id), paths: paths)
        for folder in ["drive_c/Program Files", "drive_c/Program Files (x86)", "drive_c/Games"] {
            let installed = try GameScanner.scan(directory: paths.prefix(game.id).appendingPathComponent(folder), paths: paths)
            scan.candidates += installed.candidates.filter { !$0.name.lowercased().contains("wine") }
        }
        scan.candidates.sort { $0.score == $1.score ? $0.relativePath < $1.relativePath : $0.score > $1.score }
        value.candidates = scan.candidates; value.bundledPatches = scan.patches; value.sizeBytes = scan.bytes
        if !scan.candidates.contains(where: { $0.relativePath == value.selectedExecutable }) { value.selectedExecutable = scan.candidates.first?.relativePath ?? "" }
        if value.engine == "Windows 通用引擎" { value.engine = scan.engine }
        return value
    }
    public func applyPatch(_ patch: URL, to game: Game, options: ImportOptions) throws -> (Game, URL, Int) {
        guard !game.selectedExecutable.isEmpty else { throw BridgeError("请先选择游戏主程序，补丁会复制到它所在的目录。") }
        let target = try paths.url(game.selectedExecutable).deletingLastPathComponent()
        let content = paths.content(game.id).resolvingSymlinksInPath().path
        let prefix = paths.prefix(game.id).appendingPathComponent("drive_c").resolvingSymlinksInPath().path
        let resolved = target.resolvingSymlinksInPath().path
        guard resolved == content || resolved.hasPrefix(content + "/") || resolved.hasPrefix(prefix + "/") else { throw BridgeError("补丁目标不在当前游戏的独立目录内。") }
        let staging = paths.root.appendingPathComponent("Library/Cache/patch-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: patch.path, isDirectory: &isDir)
        if isDir.boolValue { try FileManager.default.copyItem(at: patch, to: staging) }
        else { try extract(patch, to: staging, options: options) }
        try rejectLinks(in: staging)
        var payload = staging
        for _ in 0..<4 {
            let items = try FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).filter { $0.lastPathComponent != "__MACOSX" }
            if items.count == 1, (try items[0].resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { payload = items[0] } else { break }
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = paths.root.appendingPathComponent("Library/Backups/" + game.id.uuidString + "/patch-" + stamp + "-" + UUID().uuidString.prefix(6))
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        guard let enumerator = FileManager.default.enumerator(at: payload, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { throw BridgeError("无法读取补丁目录。") }
        var fileCount = 0
        for case let item as URL in enumerator {
            let relative = String(item.path.dropFirst(payload.path.count + 1)); try ArchiveGuard.validate(path: relative)
            let destination = target.appendingPathComponent(relative)
            let parentResolved = destination.deletingLastPathComponent().resolvingSymlinksInPath().path
            guard parentResolved == resolved || parentResolved.hasPrefix(resolved + "/") else { throw BridgeError("补丁包含超出游戏目录的目标。") }
            let isFolder = (try item.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            if isFolder { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true); continue }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                let old = backup.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: destination, to: old)
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: item, to: destination); fileCount += 1
        }
        let record: [String: Any] = ["patch": patch.lastPathComponent, "target": try paths.relative(target), "files": fileCount, "createdAt": stamp]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted]).write(to: backup.appendingPathComponent("patch-record.json"))
        return (try rescan(game), backup, fileCount)
    }
    private func rejectLinks(in directory: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { return }
        for case let url as URL in enumerator {
            if (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true { throw BridgeError("游戏目录包含符号链接，请导入普通文件组成的游戏包。") }
        }
    }
}
