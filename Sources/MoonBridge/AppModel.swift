import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MoonBridgeCore

@MainActor final class AppModel: ObservableObject {
    enum Section: String, CaseIterable { case library = "游戏收藏室", runtime = "运行环境", activity = "运行记录", guide = "使用指南" }
    let paths: ProjectPaths
    @Published var document = LibraryDocument()
    @Published var section: Section = .library
    @Published var query = ""
    @Published var status = "准备好迎接下一段故事"
    @Published var runtime = RuntimeReport()
    @Published var operation = false
    @Published var running: Set<UUID> = []
    @Published var stopping: Set<UUID> = []
    @Published var detailID: UUID?
    @Published var importSources: [URL] = []
    @Published var showImport = false
    @Published var patchSource: URL?
    @Published var patchGameID: UUID?
    @Published var showPatch = false
    @Published var logGameID: UUID?
    @Published var showLog = false
    @Published var error: String?
    @Published var notice: String?
    @Published var dragActive = false
    @Published var events: [String] = []
    var engine: WineEngine { WineEngine(paths: paths) }
    var importer: GameImporter { GameImporter(paths: paths) }
    var games: [Game] { document.games.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.engine.localizedCaseInsensitiveContains(query) }.sorted { $0.importedAt > $1.importedAt } }
    var selectedGame: Game? { document.games.first { $0.id == detailID } }
    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--root"), args.count > i + 1 { paths = ProjectPaths(root: URL(fileURLWithPath: args[i + 1])) }
        else if let root = ProcessInfo.processInfo.environment["MOONBRIDGE_ROOT"] { paths = ProjectPaths(root: URL(fileURLWithPath: root)) }
        else { paths = ProjectPaths(root: Bundle.main.bundleURL.deletingLastPathComponent()) }
        do { try paths.makeDirectories(); document = try LibraryDocument.load(from: paths) }
        catch { self.error = "游戏库读取失败，原始记录已保留：\n" + error.localizedDescription }
    }
    func save() { do { try document.save(to: paths) } catch { self.error = "无法保存游戏库：" + error.localizedDescription } }
    func update(_ game: Game) { if let index = document.games.firstIndex(where: { $0.id == game.id }) { document.games[index] = game; save() } }
    func game(_ id: UUID) -> Game? { document.games.first { $0.id == id } }
    func record(_ text: String) { status = text; events.insert(Date().formatted(date: .omitted, time: .standard) + "  " + text, at: 0) }
    func checkRuntime() {
        let engine = engine
        Task {
            let report = await Task.detached(priority: .utility) { engine.check() }.value
            runtime = report
        }
    }
    func chooseGame() {
        guard !operation else { return }
        let panel = NSOpenPanel(); panel.title = "把一个故事带到 MoonBridge"
        panel.message = "选择完整游戏文件夹、ZIP / 7Z / RAR 或 EXE。选择 EXE 时会同时导入其所在文件夹。"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.acceptImport(panel.urls) }
        }
    }
    func acceptImport(_ urls: [URL]) {
        guard !operation, !urls.isEmpty else { return }
        importSources = urls; showImport = true
    }
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !operation else { return false }
        for provider in providers.prefix(1) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? URL { url = value }
                else if let value = item as? String { url = URL(string: value) }
                else { url = nil }
                if let url { Task { @MainActor in self.acceptImport([url]) } }
            }
        }
        return true
    }
    func beginImport(options: ImportOptions) {
        guard !operation else { return }
        let sources = importSources; let service = importer
        showImport = false; operation = true; section = .library
        Task {
            for source in sources {
                record("正在导入：" + source.lastPathComponent)
                do {
                    let value = try await Task.detached(priority: .userInitiated) { [self] in
                        try service.importGame(from: source, options: options) { message in Task { @MainActor in self.status = message } }
                    }.value
                    document.games.append(value); save(); detailID = value.id
                    record("已导入「" + value.title + "」")
                } catch { self.error = error.localizedDescription; record("导入未完成：" + source.lastPathComponent) }
            }
            operation = false
        }
    }
    func launch(_ game: Game) {
        guard !operation, !running.contains(game.id) else { return }
        guard runtime.wineReady && runtime.rosettaReady else { error = "运行环境未就绪，请先查看“运行环境”。"; return }
        running.insert(game.id)
        var value = game; value.lastPlayedAt = Date(); value.lastResult = "准备运行"; update(value)
        let service = engine; record("正在准备「" + game.title + "」")
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [self] in
                    try service.launchAndWait(game) { message in Task { @MainActor in self.status = message } }
                }.value
                if var latest = self.game(game.id) {
                    latest.lastResult = stopping.contains(game.id) ? "已停止" : result.code == 0 ? "会话已结束 · 待游玩验证" : "已退出 · 代码 \(result.code)"
                    if game.selected?.isInstaller == true, let rescanned = try? importer.rescan(latest) { latest = rescanned }
                    update(latest)
                }
                record(result.code == 0 ? "「\(game.title)」会话已结束" : "「\(game.title)」已退出，可查看日志")
                if result.code != 0 && !stopping.contains(game.id) { notice = "游戏已退出（代码 \(result.code)）。可尝试日文 / 中文区域、虚拟桌面，或查看运行日志。" }
            } catch {
                if !stopping.contains(game.id) { self.error = error.localizedDescription; record("启动未完成：" + game.title) }
                if var latest = self.game(game.id) { latest.lastResult = stopping.contains(game.id) ? "已停止" : "启动未完成 · 查看日志"; update(latest) }
                _ = try? await Task.detached { try service.stop(game) }.value
            }
            running.remove(game.id); stopping.remove(game.id)
        }
    }
    func stop(_ game: Game) {
        stopping.insert(game.id)
        let service = engine
        Task {
            do { try await Task.detached { try service.stop(game) }.value; record("已停止「" + game.title + "」的运行环境") }
            catch { self.error = error.localizedDescription }
        }
    }
    func rescan(_ game: Game) {
        guard !operation, !running.contains(game.id) else { return }
        let service = importer; operation = true; record("正在重新扫描主程序…")
        Task {
            do { let value = try await Task.detached { try service.rescan(game) }.value; update(value); record("重新扫描完成，共 \(value.candidates.count) 个候选程序") }
            catch { self.error = error.localizedDescription }
            operation = false
        }
    }
    func choosePatch(for game: Game) {
        let panel = NSOpenPanel(); panel.title = "选择汉化补丁"; panel.message = "补丁会应用到当前主程序所在目录，覆盖前自动备份原文件。"
        panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.presentPatch(url, game: game) }
        }
    }
    func presentPatch(_ url: URL, game: Game) { patchSource = url; patchGameID = game.id; showPatch = true }
    func applyPatch(options: ImportOptions) {
        guard !operation, let source = patchSource, let id = patchGameID, let game = game(id), !running.contains(id) else { return }
        let service = importer; showPatch = false; operation = true; record("正在备份并应用汉化补丁…")
        Task {
            do {
                let (value, backup, count) = try await Task.detached { try service.applyPatch(source, to: game, options: options) }.value
                update(value); record("汉化补丁已应用，\(count) 个文件")
                notice = "补丁已应用（\(count) 个文件）。原文件备份位于：\n" + backup.path + "\n\n如补丁提供了新启动器，请在主程序列表中选择它。"
            } catch { self.error = error.localizedDescription }
            operation = false
        }
    }
    func chooseCover(for game: Game) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.title = "选择游戏封面"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    guard NSImage(contentsOf: url) != nil else { throw BridgeError("无法读取这张图片。") }
                    let relative = "Library/Games/" + game.id.uuidString + "/cover-" + UUID().uuidString + "." + url.pathExtension
                    try FileManager.default.copyItem(at: url, to: self.paths.url(relative))
                    var latest = self.game(game.id) ?? game; latest.coverPath = relative; self.update(latest)
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func showLog(for game: Game) { logGameID = game.id; showLog = true }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func revealContent(_ game: Game) { reveal(paths.content(game.id)) }
    func revealSaves(_ game: Game) {
        let url = paths.prefix(game.id).appendingPathComponent("drive_c/users")
        if FileManager.default.fileExists(atPath: url.path) { reveal(url) } else { notice = "首次启动后会建立独立 Windows 用户目录；存档也可能保存在游戏文件夹内。" }
    }
    func wineConfiguration(_ game: Game) {
        guard !operation, !running.contains(game.id) else { return }
        let service = engine; operation = true; running.insert(game.id); status = "正在打开 Windows 运行配置…"
        Task {
            do { try await Task.detached { try service.openConfiguration(game) }.value; record("运行配置窗口已关闭") }
            catch { self.error = error.localizedDescription }
            operation = false; running.remove(game.id)
        }
    }
    func hide(_ game: Game) {
        guard !running.contains(game.id), !operation else { return }
        try? FileManager.default.copyItem(at: paths.libraryFile, to: paths.root.appendingPathComponent("Library/Manifests/library-before-hide-" + UUID().uuidString + ".json"))
        document.games.removeAll { $0.id == game.id }; save(); record("已从游戏库隐藏「" + game.title + "」，文件仍保留")
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MoonBridge-诊断.txt"; panel.allowedContentTypes = [.plainText]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let body = "MoonBridge 0.1.1\n\n" + self.runtime.detail + "\n\n游戏库：\n" + self.document.games.map { "\($0.title) | \($0.engine) | \($0.lastResult)" }.joined(separator: "\n") + "\n\n最近操作：\n" + self.events.joined(separator: "\n")
                do { try body.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
            }
        }
    }
}
