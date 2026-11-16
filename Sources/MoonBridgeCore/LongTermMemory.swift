import Foundation
import CSQLite
import Darwin

public struct MemoryNote: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), text: String, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }
}

/// A shared, persistent local archive. Each operation owns a short SQLite connection and never accesses a game or Wine prefix.
public struct LocalMemoryStore: Sendable {
    public let paths: ProjectPaths
    public init(paths: ProjectPaths) { self.paths = paths }
    public var databaseURL: URL { paths.root.appendingPathComponent("Library/Companion/memory.sqlite") }

    public func loadMessages(limit: Int = 200) throws -> [ChatMessage] {
        guard limit > 0 else { return [] }
        let db = try open()
        // Select the newest window, then return it chronologically for the conversation UI.
        let values = try db.messages("SELECT \(MemoryDatabase.columns) FROM messages ORDER BY created_at DESC, rowid DESC LIMIT ?", [.integer(Int64(min(limit, 10000)))])
        return values.reversed()
    }
    public func append(_ message: ChatMessage) throws {
        try Self.validate(message)
        let db = try open()
        try db.transaction { try db.insert(message) }
    }
    public func search(query: String, limit: Int = 6, excludingIDs: Set<UUID> = []) throws -> [ChatMessage] {
        let query = Self.normalize(String(query.prefix(600))).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        let db = try open()
        let terms = Self.searchTerms(query)
        guard !terms.isEmpty else { return [] }
        var candidates: [ChatMessage] = []
        if db.hasTrigramIndex {
            let phrases = Self.trigramTerms(query).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            if !phrases.isEmpty {
                let expression = phrases.joined(separator: " OR ")
                candidates = (try? db.messages("SELECT \(MemoryDatabase.prefixedColumns) FROM messages m JOIN message_search ON m.id=message_search.message_id WHERE message_search MATCH ? ORDER BY bm25(message_search) LIMIT 100", [.text(expression)])) ?? []
            }
        }
        // The bounded LIKE candidate set also handles two-character Chinese queries unsupported by trigram MATCH.
        var matchTerms: [String] = [], seenTerms = Set<String>()
        for term in terms.prefix(24) {
            for variant in [term, term.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? term] where seenTerms.insert(variant).inserted {
                matchTerms.append(variant)
            }
        }
        let predicates = matchTerms.map { _ in "(text LIKE ? ESCAPE '\\' OR game_title LIKE ? ESCAPE '\\')" }.joined(separator: " OR ")
        var bindings: [MemoryDatabase.Value] = []
        for term in matchTerms {
            let escaped = term.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            bindings += [.text("%" + escaped + "%"), .text("%" + escaped + "%")]
        }
        candidates += try db.messages("SELECT \(MemoryDatabase.columns) FROM messages WHERE \(predicates) ORDER BY created_at DESC, rowid DESC LIMIT 240", bindings)
        var seen = Set<UUID>()
        let ranked = candidates.filter { !excludingIDs.contains($0.id) && seen.insert($0.id).inserted }.map { message -> (ChatMessage, Double) in
            let text = Self.normalize(String(message.text.prefix(16000)) + " " + (message.gameTitle ?? ""))
            var score = query.count >= 2 && text.contains(query) ? 15.0 : 0.0
            for term in terms where text.contains(term) { score += min(Double(term.count), 12.0) }
            return (message, score)
        }.filter { $0.1 > 0 }.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.createdAt != b.0.createdAt { return a.0.createdAt > b.0.createdAt }
            return a.0.id.uuidString < b.0.id.uuidString
        }
        return Array(ranked.prefix(min(limit, 50)).map { $0.0 })
    }
    public func notes() throws -> [MemoryNote] {
        let db = try open()
        return try db.notes()
    }
    public func saveNote(_ note: MemoryNote) throws {
        let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else { throw BridgeError("长期记忆事项须为1至4,000个字符。") }
        let db = try open()
        try db.execute("INSERT INTO notes(id,text,created_at,updated_at) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET text=excluded.text,updated_at=excluded.updated_at",
                       [.text(note.id.uuidString), .text(text), .number(note.createdAt.timeIntervalSince1970), .number(max(note.updatedAt.timeIntervalSince1970, Date().timeIntervalSince1970))])
    }
    public func deleteNote(id: UUID) throws {
        let db = try open()
        try db.execute("DELETE FROM notes WHERE id=?", [.text(id.uuidString)])
    }
    public func clearMessages() throws {
        let db = try open()
        try db.transaction {
            if db.hasTrigramIndex { try db.execute("DELETE FROM message_search") }
            try db.execute("DELETE FROM messages")
            // Pinned notes and the migration marker deliberately survive clearing the shared chat.
        }
    }
    public func isMigrationDone() throws -> Bool { try open().metadata("legacy_chat_import_v1") == "done" }
    public func migrateLegacyChats(gameTitles: [UUID: String]) throws {
        let db = try open()
        try db.transaction {
            guard try db.metadata("legacy_chat_import_v1") != "done" else { return }
            let folder = paths.root.appendingPathComponent("Library/Companion/chat")
            try Self.validatePath(folder, root: paths.root, directory: true)
            if FileManager.default.fileExists(atPath: folder.path) {
                let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                guard files.count <= 10000 else { throw BridgeError("旧聊天文件数量过多，迁移未完成，原文件已保留。") }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                for file in files {
                    guard let gameID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
                    try Self.validatePath(file, root: paths.root, directory: false)
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    guard ((attributes[.size] as? NSNumber)?.int64Value ?? Int64.max) <= 64 * 1024 * 1024 else { throw BridgeError("旧聊天文件过大，迁移未完成，原文件已保留。") }
                    let messages: [ChatMessage]
                    do { messages = try decoder.decode([ChatMessage].self, from: Data(contentsOf: file)) }
                    catch { throw BridgeError("旧聊天文件无法读取，迁移未完成，原文件已保留。") }
                    for var message in messages {
                        try Self.validate(message)
                        if message.gameID == nil { message.gameID = gameID }
                        if message.gameTitle == nil { message.gameTitle = gameTitles[gameID] ?? "已归档游戏" }
                        try db.insert(message)
                    }
                }
            }
            try db.execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text("legacy_chat_import_v1"), .text("done")])
        }
    }

    private func open() throws -> MemoryDatabase {
        let folder = databaseURL.deletingLastPathComponent()
        try Self.validatePath(folder, root: paths.root, directory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Self.validatePath(folder, root: paths.root, directory: true)
        for suffix in ["", "-wal", "-shm", "-journal"] { try Self.validatePath(URL(fileURLWithPath: databaseURL.path + suffix), root: paths.root, directory: false) }
        // Foundation can preserve /var and /tmp aliases even after resolvingSymlinksInPath().
        // SQLite NOFOLLOW must receive the POSIX-canonical parent as a plain string.
        let canonicalFolder = try Self.canonicalPath(folder.path)
        let canonicalRoot = try Self.canonicalPath(paths.root.path)
        guard canonicalFolder == canonicalRoot + "/Library/Companion" else { throw BridgeError("记忆库路径解析不一致，已停止操作。") }
        guard chmod(canonicalFolder, 0o700) == 0 else { throw BridgeError("无法收紧记忆目录权限，操作已停止。") }
        return try MemoryDatabase(path: canonicalFolder + "/memory.sqlite")
    }
    private static func canonicalPath(_ path: String) throws -> String {
        guard let value = path.withCString({ realpath($0, nil) }) else { throw BridgeError("无法解析记忆目录的真实路径。") }
        defer { free(value) }
        return String(cString: value)
    }
    private static func validatePath(_ target: URL, root: URL, directory: Bool) throws {
        let root = root.standardizedFileURL
        let expected = root.resolvingSymlinksInPath().appendingPathComponent("Library/Companion").path
        let resolved = target.resolvingSymlinksInPath().path
        guard resolved == expected || resolved.hasPrefix(expected + "/"), target.standardizedFileURL.path.hasPrefix(root.path + "/Library/Companion") else {
            throw BridgeError("记忆库路径无效，已停止操作以保护游戏文件。")
        }
        var item = target.standardizedFileURL
        while item.path.count > root.path.count {
            var info = stat()
            let result = item.path.withCString { lstat($0, &info) }
            if result == 0 {
                let kind = info.st_mode & S_IFMT
                if kind == S_IFLNK { throw BridgeError("记忆库路径含有符号链接，已停止操作。") }
                if item == target.standardizedFileURL {
                    guard (directory && kind == S_IFDIR) || (!directory && kind == S_IFREG), directory || info.st_nlink == 1 else {
                        throw BridgeError("记忆库文件类型或链接状态异常，已停止操作。")
                    }
                } else if kind != S_IFDIR { throw BridgeError("记忆库的上级路径不是文件夹。") }
            } else if errno != ENOENT { throw BridgeError("无法检查记忆库路径。") }
            item.deleteLastPathComponent()
        }
    }
    private static func validate(_ message: ChatMessage) throws {
        guard !message.role.isEmpty, message.role.count <= 40, message.text.utf8.count <= 4 * 1024 * 1024,
              message.sources.count <= 200, (message.gameTitle?.count ?? 0) <= 500,
              message.createdAt.timeIntervalSince1970.isFinite else { throw BridgeError("聊天记录格式或长度无效，原有记忆未修改。") }
    }
    private static func normalize(_ value: String) -> String {
        let simplified = value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
        return simplified.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static let stopTerms: Set<String> = ["什么", "怎么", "这个", "那个", "关于", "一下", "可以", "我们", "你们", "我的", "你的", "现在", "知道", "记得", "时候", "还是", "之前", "能否", "请问", "the", "what", "this", "that", "with", "from"]
    private static func searchTerms(_ value: String) -> [String] {
        let words = value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var terms: [String] = []
        for word in words.prefix(30) {
            let chars = Array(word)
            let containsCJK = word.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) }
            if containsCJK, chars.count >= 2 {
                if chars.count <= 12 { terms.append(word) }
                for index in 0..<(chars.count - 1) { terms.append(String(chars[index...index + 1])) }
            } else if chars.count >= 2 { terms.append(word) }
        }
        var seen = Set<String>()
        return terms.filter { !stopTerms.contains($0) && seen.insert($0).inserted }.prefix(40).map { $0 }
    }
    private static func trigramTerms(_ value: String) -> [String] {
        let words = value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
        var seen = Set<String>(), terms: [String] = []
        for word in words.prefix(20) {
            let chars = Array(word)
            if chars.count <= 24 { terms.append(word) }
            for index in 0..<(chars.count - 2) { terms.append(String(chars[index...index + 2])) }
        }
        return terms.filter { seen.insert($0).inserted }.prefix(30).map { $0 }
    }
}

private final class MemoryDatabase {
    static let columns = "id,role,text,sources,created_at,game_id,game_title"
    static let prefixedColumns = "m.id,m.role,m.text,m.sources,m.created_at,m.game_id,m.game_title"
    enum Value { case text(String), number(Double), integer(Int64), null }
    private var handle: OpaquePointer?
    private(set) var hasTrigramIndex = false
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard status == SQLITE_OK, let db else { if let db { sqlite3_close(db) }; throw BridgeError("无法打开本地记忆库（SQLite \(status)）。") }
        handle = db
        do {
            sqlite3_busy_timeout(db, 5000)
            try execute("PRAGMA trusted_schema=OFF")
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY NOT NULL,role TEXT NOT NULL,text TEXT NOT NULL,sources TEXT NOT NULL,created_at REAL NOT NULL,game_id TEXT,game_title TEXT)")
            try execute("CREATE INDEX IF NOT EXISTS message_time ON messages(created_at)")
            try execute("CREATE TABLE IF NOT EXISTS notes(id TEXT PRIMARY KEY NOT NULL,text TEXT NOT NULL,created_at REAL NOT NULL,updated_at REAL NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY NOT NULL,value TEXT NOT NULL)")
            // Apple SQLite versions differ. Unsupported trigram/FTS5 safely falls back to bounded local 2-gram ranking.
            if (try? execute("CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5(message_id UNINDEXED,text,tokenize='trigram')")) != nil {
                hasTrigramIndex = true
                try transaction {
                    if try metadata("fts_trigram_v1") != "ready" {
                        try execute("DELETE FROM message_search")
                        try execute("INSERT INTO message_search(message_id,text) SELECT id,text FROM messages")
                        try execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text("fts_trigram_v1"), .text("ready")])
                    }
                }
            }
            for suffix in ["", "-wal", "-shm", "-journal"] {
                guard chmod(path + suffix, 0o600) == 0 || errno == ENOENT else { throw BridgeError("无法收紧记忆库文件权限，操作已停止。") }
            }
        } catch { sqlite3_close(db); handle = nil; throw error }
    }
    deinit { if let handle { sqlite3_close(handle) } }
    func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try operation(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func execute(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        // PRAGMA journal_mode emits a row. Drain all rows before checking completion.
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw failure(result) }
    }
    func insert(_ message: ChatMessage) throws {
        let json = String(decoding: try JSONEncoder().encode(message.sources), as: UTF8.self)
        try execute("INSERT OR IGNORE INTO messages(id,role,text,sources,created_at,game_id,game_title) VALUES(?,?,?,?,?,?,?)",
                    [.text(message.id.uuidString), .text(message.role), .text(message.text), .text(json), .number(message.createdAt.timeIntervalSince1970), message.gameID.map { .text($0.uuidString) } ?? .null, message.gameTitle.map { .text($0) } ?? .null])
        if sqlite3_changes(handle) > 0, hasTrigramIndex {
            try execute("INSERT INTO message_search(message_id,text) VALUES(?,?)", [.text(message.id.uuidString), .text(message.text)])
        }
    }
    func messages(_ sql: String, _ values: [Value]) throws -> [ChatMessage] {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        var result: [ChatMessage] = [], status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)), let sourcesData = text(statement, 3).data(using: .utf8) else { throw BridgeError("本地聊天记录格式异常，原始数据库已保留。") }
            let sources: [SourceLink]
            do { sources = try JSONDecoder().decode([SourceLink].self, from: sourcesData) } catch { throw BridgeError("本地聊天来源记录无法读取，原始数据库已保留。") }
            let gameID = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : UUID(uuidString: text(statement, 5))
            let gameTitle = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : text(statement, 6)
            result.append(ChatMessage(id: id, role: text(statement, 1), text: text(statement, 2), sources: sources,
                                      createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)), gameID: gameID, gameTitle: gameTitle))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure(status) }
        return result
    }
    func notes() throws -> [MemoryNote] {
        let statement = try prepare("SELECT id,text,created_at,updated_at FROM notes ORDER BY updated_at DESC,id", []); defer { sqlite3_finalize(statement) }
        var values: [MemoryNote] = [], status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)) else { throw BridgeError("本地长期事项格式异常，原始数据库已保留。") }
            values.append(MemoryNote(id: id, text: text(statement, 1), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)), updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure(status) }
        return values
    }
    func metadata(_ key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM metadata WHERE key=?", [.text(key)]); defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw failure(status) }
        return text(statement, 0)
    }
    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else { if let statement { sqlite3_finalize(statement) }; throw failure(status) }
        for (index, value) in values.enumerated() {
            let result: Int32
            switch value {
            case .text(let value): result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, Int32(value.utf8.count), Self.transient) }
            case .number(let value): result = sqlite3_bind_double(statement, Int32(index + 1), value)
            case .integer(let value): result = sqlite3_bind_int64(statement, Int32(index + 1), value)
            case .null: result = sqlite3_bind_null(statement, Int32(index + 1))
            }
            guard result == SQLITE_OK else { sqlite3_finalize(statement); throw failure(result) }
        }
        return statement
    }
    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }
    private func failure(_ code: Int32) -> BridgeError { BridgeError("本地记忆库操作未完成（SQLite \(code)）。原始记录已保留。") }
}
