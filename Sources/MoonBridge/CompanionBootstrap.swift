import Foundation
import MoonBridgeCore

/// Local administration commands use the signed app's Keychain identity.
/// Secrets are read in memory from the explicitly supplied file and never logged.
enum CompanionBootstrap {
    static func handleCommandLineIfNeeded() {
        let args = CommandLine.arguments
        guard args.contains("--configure-ai-from-env") || args.contains("--companion-smoke-check") || args.contains("--catalog-smoke-check") || args.contains("--models-smoke-check") || args.contains("--memory-smoke-check") else { return }
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.count > i + 1 else { return nil }
            return args[i + 1]
        }
        guard let root = value(after: "--root"), root.hasPrefix("/") else { fputs("An explicit --root is required.\n", stderr); exit(2) }
        let paths = ProjectPaths(root: URL(fileURLWithPath: root))
        if args.contains("--configure-ai-from-env") {
            do {
                guard let name = value(after: "--configure-ai-from-env"), name.hasPrefix("/") else { throw BridgeError("需要明确的本地凭据文件路径。") }
                let input = URL(fileURLWithPath: name)
                guard try input.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw BridgeError("凭据文件不能是符号链接。") }
                let lines = try String(contentsOf: input, encoding: .utf8).components(separatedBy: .newlines)
                var key: String?
                for line in lines {
                    let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "OPENAI_API_KEY" {
                        key = String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                }
                guard let key, !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw BridgeError("文件中未找到可用的 OPENAI_API_KEY。") }
                let store = CompanionStore(paths: paths)
                var settings = try store.loadSettings()
                if let proxy = value(after: "--proxy") { settings.proxyURL = proxy }
                try CompanionConfiguration.save(settings, key: key, paths: paths)
                print("MoonBridge credential configured in macOS Keychain. No key was written to project files.")
                exit(0)
            } catch { fputs(("Credential configuration failed: " + error.localizedDescription + "\n"), stderr); exit(1) }
        }
        // Async commands intentionally bypass the GUI and never load or save library.json.
        Task {
            do {
                let store = CompanionStore(paths: paths)
                let settings = try store.loadSettings()
                if args.contains("--catalog-smoke-check") {
                    for query in ["Amatsutsumi", "Kami no Ue no Mahoutsukai", "Haison Shoujo"] {
                        let values = try await GameCatalog.search(query: query, settings: settings)
                        print("Catalog \(query): \(values.count) candidates")
                        for value in values.prefix(3) { print("\(value.id) | \(value.title) | \(value.originalTitle) | \(value.sourceURL)") }
                    }
                } else {
                    guard let key = try KeychainCredential().load(baseURL: settings.baseURL), !key.isEmpty else { throw BridgeError("月渡尚未配置凭据。") }
                    let client = AIClient(settings: settings, key: key, persona: ChisaPersona.load(paths: paths))
                    if args.contains("--memory-smoke-check") {
                        guard !FileManager.default.fileExists(atPath: paths.libraryFile.path) else { throw BridgeError("记忆实测只允许在不含游戏索引的隔离目录中运行。") }
                        let archive = LocalMemoryStore(paths: paths)
                        let firstGame = UUID()
                        let sample = ChatMessage(role: "user", text: "我喜欢浅蓝色界面，请不要剧透。", gameID: firstGame, gameTitle: "隔离测试作品 A")
                        try archive.append(sample)
                        try archive.saveNote(MemoryNote(text: "本次功能测试偏好：浅蓝色界面，避免剧透。"))
                        let reopened = LocalMemoryStore(paths: paths)
                        let recall = try reopened.search(query: "浅蓝 剧透", limit: 6, excludingIDs: [])
                        guard recall.contains(where: { $0.id == sample.id }) else { throw BridgeError("本地记忆重新打开后未召回测试记录。") }
                        let answer = try await client.reply(question: "你记得我偏好的界面颜色和剧透要求吗？只用一句中文回答，不要联网。", gameTitle: "隔离测试作品 B", metadata: nil, history: [], allowSpoilers: false, memories: recall, notes: reopened.notes())
                        guard answer.text.contains("蓝"), answer.text.contains("剧透") else { throw BridgeError("模型未正确使用跨游戏记忆。") }
                        try archive.append(answer)
                        print("Shared-memory live check passed: reopen, Chinese recall, cross-game response and persistence; assistant=千咲.")
                        exit(0)
                    }
                    if args.contains("--models-smoke-check") {
                        let models = try await client.listModels()
                        print("Model list received; count=\(models.count), includes configured model=\(models.contains(settings.model))")
                        exit(0)
                    }
                    print(try await client.checkConnection())
                    let answer = try await client.reply(question: "请只用一句中文介绍视觉小说是什么，不涉及任何具体游戏剧情，并引用一个可以核实的公开来源。", gameTitle: "MoonBridge 功能自检", metadata: nil, history: [], allowSpoilers: false)
                    guard !answer.text.isEmpty else { throw BridgeError("模型回复为空。") }
                    print("Live answer received; characters=\(answer.text.count), sources=\(answer.sources.count)")
                }
                exit(0)
            } catch { fputs(("Companion check failed: " + error.localizedDescription + "\n"), stderr); exit(1) }
        }
        RunLoop.main.run()
    }
}
