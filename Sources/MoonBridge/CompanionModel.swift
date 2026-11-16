import SwiftUI
import MoonBridgeCore

/// Owns optional companion data. It never writes a Game, a Wine prefix or the game index.
@MainActor final class CompanionModel: ObservableObject {
    let paths: ProjectPaths
    private let store: CompanionStore
    private let memoryStore: LocalMemoryStore
    @Published var settings = CompanionSettings()
    @Published var metadata: [UUID: GameMetadata] = [:]
    @Published var candidates: [GameMetadata] = []
    @Published var lookupQuery = ""
    @Published var lookupBusy = false
    @Published var lookupError: String?
    @Published var lookupGameID: UUID?
    @Published var showLookup = false
    @Published var messages: [ChatMessage] = []
    @Published var memoryNotes: [MemoryNote] = []
    @Published var memorySearchResults: [ChatMessage] = []
    @Published var memoryStatus: String?
    @Published var isAnswering = false
    private var memoryReady = false
    @Published var savingMetadata: Set<UUID> = []
    @Published var aiNotice: String?
    @Published var keyReady = false
    @Published var connectionStatus = "尚未测试连接"
    @Published var availableModels: [String] = []
    @Published var modelsBusy = false
    @Published var modelsStatus: String?
    private var lookupTask: Task<Void, Never>?
    private var lookupGeneration = UUID()
    private var chatTask: Task<Void, Never>?
    private var chatGeneration = UUID()
    private var metadataTasks: [UUID: Task<Void, Never>] = [:]
    private var connectionTask: Task<Void, Never>?
    private var modelsTask: Task<Void, Never>?
    private var modelsGeneration = UUID()

    init(paths: ProjectPaths) {
        self.paths = paths
        store = CompanionStore(paths: paths)
        memoryStore = LocalMemoryStore(paths: paths)
        do { settings = try store.loadSettings() }
        catch { aiNotice = "AI 设置读取失败，原文件已保留：" + error.localizedDescription }
        refreshCredentialStatus()
    }

    func loadGames(_ games: [Game]) {
        for game in games {
            do {
                if let info = try store.loadMetadata(gameID: game.id) { metadata[game.id] = info }
            } catch { aiNotice = "「\(game.title)」的资料读取失败，原文件已保留：" + error.localizedDescription }
        }
        do {
            try memoryStore.migrateLegacyChats(gameTitles: Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.title) }))
            try reloadMemory()
            memoryReady = true
        } catch { memoryReady = false; memoryStatus = "共享记忆读取失败，原记录已保留：" + error.localizedDescription }
    }

    private func reloadMemory() throws {
        messages = try memoryStore.loadMessages(limit: 200)
        memoryNotes = try memoryStore.notes()
    }

    func refreshCredentialStatus() {
        keyReady = ((try? KeychainCredential().load(baseURL: settings.baseURL)) ?? nil)?.isEmpty == false
    }

    func presentLookup(for game: Game) {
        lookupGameID = game.id
        lookupQuery = metadata[game.id]?.originalTitle.isEmpty == false ? metadata[game.id]!.originalTitle : game.title
        candidates = []
        lookupError = nil
        showLookup = true
        search(lookupQuery)
    }

    func search(_ query: String) {
        lookupTask?.cancel()
        let generation = UUID()
        lookupGeneration = generation
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.enabled else { lookupError = "资料联网功能已关闭，可在 AI 设置中开启。"; lookupBusy = false; return }
        guard !value.isEmpty, value.count <= 200 else { lookupError = "请输入 1–200 个字符的游戏名称。"; lookupBusy = false; return }
        let config = settings
        lookupBusy = true
        lookupError = nil
        candidates = []
        lookupTask = Task {
            defer { if lookupGeneration == generation { lookupBusy = false } }
            do {
                let values = try await GameCatalog.search(query: value, settings: config)
                try Task.checkCancellation()
                guard lookupGeneration == generation else { return }
                candidates = values
                if values.isEmpty { lookupError = "没有找到匹配作品。可以尝试日文原名、英文名，或手动编辑游戏资料。" }
            } catch is CancellationError { }
            catch { if !Task.isCancelled && lookupGeneration == generation { lookupError = error.localizedDescription } }
        }
    }

    func apply(_ candidate: GameMetadata, to game: Game) {
        guard !savingMetadata.contains(game.id), settings.enabled else { return }
        let config = settings
        savingMetadata.insert(game.id)
        lookupError = nil
        metadataTasks[game.id] = Task {
            defer { savingMetadata.remove(game.id); metadataTasks[game.id] = nil }
            var value = candidate
            var warning: String?
            do { value = try await GameCatalog.enrichedMetadata(value, settings: config) }
            catch { warning = "来源详情暂时无法获取，已保留检索结果。" }
            guard !Task.isCancelled, settings.enabled else { return }
            do {
                value = try await GameCatalog.cacheCover(value, gameID: game.id, paths: paths, settings: config)
            } catch { warning = "封面未能下载，文字资料已保留。" }
            guard !Task.isCancelled, settings.enabled else { return }
            do {
                try store.saveMetadata(value, gameID: game.id)
                metadata[game.id] = value
                if lookupGameID == game.id { showLookup = false }
                if let warning { aiNotice = warning }
            } catch { lookupError = "无法保存游戏资料：" + error.localizedDescription; return }
            // Translation is optional and is based solely on the chosen source, not on game files.
            guard let key = try? KeychainCredential().load(baseURL: config.baseURL), !key.isEmpty else { return }
            keyReady = true
            do {
                let translated = try await AIClient(settings: config, key: key).summarize(metadata: value)
                // A user may edit the record while the request is in progress.
                guard !Task.isCancelled, settings.enabled, metadata[game.id] == value else { return }
                try store.saveMetadata(translated, gameID: game.id)
                metadata[game.id] = translated
            } catch { if !Task.isCancelled { aiNotice = "资料已保存；中文整理未完成，暂时显示来源原文。" } }
        }
    }

    func saveManualMetadata(_ value: GameMetadata, gameID: UUID) {
        guard !savingMetadata.contains(gameID) else { aiNotice = "资料正在保存，请稍后编辑。"; return }
        var value = value
        if value.summary != metadata[gameID]?.summary { value.summaryOrigin = "manual" }
        do { try store.saveMetadata(value, gameID: gameID); metadata[gameID] = value; aiNotice = "本地游戏资料已保存。" }
        catch { aiNotice = "保存失败，原资料已保留：" + error.localizedDescription }
    }

    func send(_ text: String, for game: Game, allowSpoilers: Bool) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 4000 else { aiNotice = "问题最多 4,000 个字符。"; return }
        guard settings.enabled else { aiNotice = "联网功能已关闭，请在连接设置中开启。"; return }
        guard memoryReady else { aiNotice = "共享记忆暂时不可用，为保护原记录，本次不会写入或发送问题。"; return }
        guard !isAnswering else { aiNotice = "千咲正在回答上一条问题，可以先停止回答。"; return }
        let userMessage = ChatMessage(role: "user", text: question, gameID: game.id, gameTitle: game.title)
        let history = Array(messages.suffix(12))
        do {
            if let answer = try localAnswer(question, game: game) {
                try memoryStore.append(userMessage)
                try memoryStore.append(ChatMessage(role: "assistant", text: answer, gameID: game.id, gameTitle: game.title))
                try reloadMemory()
                return
            }
        } catch { aiNotice = "本地记忆操作未完成：" + error.localizedDescription; return }
        let key: String
        do {
            guard let saved = try KeychainCredential().load(baseURL: settings.baseURL), !saved.isEmpty else { keyReady = false; aiNotice = "请先在连接设置中保存 API Key。"; return }
            key = saved; keyReady = true
        } catch { aiNotice = "无法读取月渡的钥匙串凭据：" + error.localizedDescription; return }
        let recall: [ChatMessage]
        do {
            recall = try memoryStore.search(query: question, limit: 6, excludingIDs: Set(history.map(\.id)))
            let preferencePrefixes = ["以后叫我", "以后称呼我", "我的名字是", "我叫", "我喜欢", "我不喜欢", "我偏好", "我希望你以后"]
            if question.count <= 600, preferencePrefixes.contains(where: { question.hasPrefix($0) }),
               !memoryNotes.contains(where: { $0.text == question }) {
                try memoryStore.saveNote(MemoryNote(text: question))
            }
            try memoryStore.append(userMessage)
            try reloadMemory()
        } catch { aiNotice = "问题未能保存到本地记忆库，未发送请求：" + error.localizedDescription; return }
        let config = settings
        let info = metadata[game.id]
        let notes = memoryNotes
        let generation = UUID()
        chatGeneration = generation
        isAnswering = true
        aiNotice = nil
        let persona = ChisaPersona.load(paths: paths)
        chatTask = Task {
            defer { if chatGeneration == generation { isAnswering = false; chatTask = nil } }
            do {
                var answer = try await AIClient(settings: config, key: key, persona: persona).reply(question: question, gameTitle: game.title, metadata: info, history: history, allowSpoilers: allowSpoilers, memories: recall, notes: notes)
                try Task.checkCancellation()
                guard chatGeneration == generation else { return }
                answer.gameID = game.id; answer.gameTitle = game.title
                try memoryStore.append(answer)
                try reloadMemory()
            } catch is CancellationError { }
            catch { if !Task.isCancelled { aiNotice = "回答未完成：" + error.localizedDescription } }
        }
    }

    private func localAnswer(_ question: String, game: Game) throws -> String? {
        let identity = ["你是什么模型", "你是什么模型？", "你是什么模型?", "你用的什么模型", "你现在是什么模型", "当前模型是什么", "你用的是哪个模型", "你的模型名称是什么", "你的推理强度是什么"]
        if identity.contains(question) {
            return "我叫千咲，负责你的游戏库。当前连接的模型是 \(settings.model)，推理强度是 \(settings.reasoningEffort)。这两项都可以在‘AI 与资料设置’中调整。"
        }
        for prefix in ["/记住 ", "记住：", "记住:", "请记住：", "请记住:", "请记住", "记住"] where question.hasPrefix(prefix) {
            let text = String(question.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 2000 else { return "想让我记住什么？写得具体一点，最多两千字。" }
            if !memoryNotes.contains(where: { $0.text == text }) { try memoryStore.saveNote(MemoryNote(text: text)) }
            return "嗯，记下了。‘\(text)’会留在共享长期记忆里，换一款游戏也能用。需要改动时，打开‘长期记忆’就好。"
        }
        return nil
    }

    func cancelChat(gameID: UUID) {
        chatTask?.cancel(); chatTask = nil; chatGeneration = UUID(); isAnswering = false
    }

    func clearHistory() {
        chatTask?.cancel(); chatTask = nil; chatGeneration = UUID(); isAnswering = false
        do { try memoryStore.clearMessages(); try reloadMemory(); memorySearchResults = []; memoryStatus = "共享聊天记录已清空，长期记忆条目保留。" }
        catch { memoryStatus = "清空聊天失败：" + error.localizedDescription }
    }

    func addMemory(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { memoryStatus = "请输入 1–2,000 个字符的记忆内容。"; return }
        do { try memoryStore.saveNote(MemoryNote(text: text)); try reloadMemory(); memoryStatus = "长期记忆已保存。" }
        catch { memoryStatus = "保存记忆失败：" + error.localizedDescription }
    }

    func deleteMemory(id: UUID) {
        do { try memoryStore.deleteNote(id: id); try reloadMemory(); memoryStatus = "已删除这条长期记忆。" }
        catch { memoryStatus = "删除记忆失败：" + error.localizedDescription }
    }

    func searchMemory(_ query: String) {
        do { memorySearchResults = try memoryStore.search(query: query, limit: 20, excludingIDs: []); memoryStatus = "找到 \(memorySearchResults.count) 条相关记录。" }
        catch { memoryStatus = "检索记忆失败：" + error.localizedDescription }
    }

    func regenerateOverview(gameID: UUID) {
        guard settings.enabled, let original = metadata[gameID], !savingMetadata.contains(gameID) else { return }
        do {
            guard let key = try KeychainCredential().load(baseURL: settings.baseURL), !key.isEmpty else { aiNotice = "请先保存 API Key，再整理中文概况。"; return }
            let config = settings
            savingMetadata.insert(gameID)
            metadataTasks[gameID] = Task {
                defer { savingMetadata.remove(gameID); metadataTasks[gameID] = nil }
                do {
                    let value = try await AIClient(settings: config, key: key).summarize(metadata: original)
                    guard !Task.isCancelled, metadata[gameID] == original else { return }
                    try store.saveMetadata(value, gameID: gameID); metadata[gameID] = value
                    aiNotice = "中文概况已整理，来源原文仍保留在折叠区。"
                } catch { if !Task.isCancelled { aiNotice = "中文概况尚未整理完成：" + error.localizedDescription } }
            }
        } catch { aiNotice = error.localizedDescription }
    }

    @discardableResult func updateSettings(_ value: CompanionSettings, key: String? = nil) -> Bool {
        do {
            try CompanionConfiguration.save(value, key: key, paths: paths)
            if value != settings {
                lookupTask?.cancel(); lookupGeneration = UUID(); lookupBusy = false
                chatTask?.cancel(); chatTask = nil; chatGeneration = UUID(); isAnswering = false
                for task in metadataTasks.values { task.cancel() }
                connectionTask?.cancel()
                modelsTask?.cancel(); modelsGeneration = UUID(); modelsBusy = false
                availableModels = []; modelsStatus = nil
            }
            settings = value
            refreshCredentialStatus()
            connectionStatus = "设置已保存，尚未测试新连接"
            aiNotice = "设置已保存。"
            return true
        } catch { aiNotice = error.localizedDescription; return false }
    }

    func testConnection() {
        guard settings.enabled else { connectionStatus = "请先开启 AI 功能。"; return }
        guard connectionStatus != "正在测试连接…" else { return }
        do {
            guard let key = try KeychainCredential().load(baseURL: settings.baseURL), !key.isEmpty else { keyReady = false; connectionStatus = "请先保存 API Key。"; return }
            keyReady = true
            let config = settings
            connectionStatus = "正在测试连接…"
            connectionTask = Task {
                do {
                    let result = try await AIClient(settings: config, key: key).checkConnection()
                    if !Task.isCancelled { connectionStatus = result }
                }
                catch { if !Task.isCancelled { connectionStatus = error.localizedDescription } }
            }
        } catch { connectionStatus = error.localizedDescription }
    }

    func fetchModels() {
        guard settings.enabled else { modelsStatus = "请先开启 AI 功能。"; return }
        guard !modelsBusy else { return }
        do {
            guard let key = try KeychainCredential().load(baseURL: settings.baseURL), !key.isEmpty else { modelsStatus = "请先保存 API Key。"; keyReady = false; return }
            keyReady = true
            let config = settings
            let generation = UUID()
            modelsGeneration = generation
            modelsBusy = true
            modelsStatus = "正在获取当前接口的模型列表…"
            modelsTask = Task {
                defer { if modelsGeneration == generation { modelsBusy = false } }
                do {
                    let values = try await AIClient(settings: config, key: key).listModels()
                    guard !Task.isCancelled, modelsGeneration == generation else { return }
                    availableModels = values
                    modelsStatus = "当前接口返回 \(values.count) 个模型。"
                } catch { if !Task.isCancelled && modelsGeneration == generation { modelsStatus = error.localizedDescription } }
            }
        } catch { modelsStatus = error.localizedDescription }
    }
}
