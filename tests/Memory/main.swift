import Foundation
import MoonBridgeCore

private enum Checks {
    static var failures: [String] = []
    static func equal<T: Equatable>(_ a: T, _ b: T, _ message: String = "", line: UInt = #line) {
        if a != b { failures.append("line \(line): expected equal: \(message)") }
    }
    static func expect(_ value: Bool, _ message: String = "", line: UInt = #line) {
        if !value { failures.append("line \(line): \(message)") }
    }
    static func throwsError<T>(_ operation: @autoclosure () throws -> T, line: UInt = #line) {
        do { _ = try operation(); failures.append("line \(line): expected error") } catch { }
    }
}
final class MemoryChecks {
    var cleanup: [() -> Void] = []
    func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MoonBridge-MemoryCheck-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        cleanup.append { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func store(_ root: URL) -> LocalMemoryStore { LocalMemoryStore(paths: ProjectPaths(root: root)) }
    func testPersistenceLabelsSourcesAndDuplicateIDs() throws {
        let dir = try root(), a = store(dir), gameID = UUID()
        let first = ChatMessage(role: "user", text: "我喜欢推理题材。", sources: [SourceLink(title: "来源", url: "https://vndb.org/v17")], createdAt: Date(timeIntervalSince1970: 100.25), gameID: gameID, gameTitle: "天津罪")
        try a.append(first)
        var duplicate = first; duplicate.text = "不得覆盖最初记录"
        try a.append(duplicate)
        Checks.equal(try store(dir).loadMessages(), [first])
        Checks.equal(try store(dir).loadMessages().first?.gameID, gameID)
        Checks.expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Library/Companion/memory.sqlite").path))
    }
    func testCrossGameCJKSearchAndExclusion() throws {
        let dir = try root(), db = store(dir), gameA = UUID(), gameB = UUID()
        let old = ChatMessage(role: "user", text: "我最喜欢的角色是萤，偏爱推理题材。", createdAt: Date(timeIntervalSince1970: 1), gameID: gameA, gameTitle: "天津罪")
        let other = ChatMessage(role: "user", text: "这款作品的配乐很安静。", createdAt: Date(timeIntervalSince1970: 2), gameID: gameB, gameTitle: "纸上的魔法使")
        let traditional = ChatMessage(role: "user", text: "我喜歡溫柔的角色。", createdAt: Date(timeIntervalSince1970: 3), gameID: gameB)
        try db.append(old); try db.append(other); try db.append(traditional)
        Checks.equal(try db.search(query: "推理").first?.id, old.id)
        Checks.equal(try db.search(query: "配乐").first?.id, other.id)
        Checks.expect(try db.search(query: "我喜欢什么角色").contains { $0.id == old.id })
        Checks.expect(try db.search(query: "温柔").contains { $0.id == traditional.id }, "simplified query recalls traditional text")
        Checks.expect(try db.search(query: "推理", excludingIDs: [old.id]).isEmpty)
    }
    func testPinnedNotesRemainAfterClearingConversation() throws {
        let dir = try root(), db = store(dir)
        let note = MemoryNote(text: "称呼我为青岚", createdAt: Date(timeIntervalSince1970: 10))
        try db.saveNote(note)
        try db.append(ChatMessage(role: "user", text: "聊天原文"))
        try db.clearMessages()
        Checks.expect(try db.loadMessages().isEmpty)
        let notes = try store(dir).notes()
        Checks.equal(notes.count, 1); Checks.equal(notes.first?.text, note.text)
        Checks.equal(notes.first?.createdAt, note.createdAt)
        var changed = note; changed.text = "偏好无剧透的回答"
        try db.saveNote(changed)
        Checks.equal(try db.notes().count, 1); Checks.equal(try db.notes().first?.text, changed.text)
        try db.deleteNote(id: note.id)
        Checks.expect(try db.notes().isEmpty)
    }
    func testParameterizedTextCannotBecomeSQL() throws {
        let dir = try root(), db = store(dir)
        let hostile = "Robert'); DROP TABLE messages; -- 100% _ \" OR 1=1"
        try db.append(ChatMessage(role: "user", text: hostile))
        let note = MemoryNote(text: hostile)
        try db.saveNote(note)
        Checks.equal(try db.loadMessages().first?.text, hostile)
        Checks.equal(try db.notes().first?.text, hostile)
        _ = try db.search(query: "\" OR 1=1 --")
        _ = try db.search(query: "100% _")
        try db.append(ChatMessage(role: "assistant", text: "表仍然存在"))
        Checks.equal(try db.loadMessages().count, 2)
    }
    func testMigrationIsAtomicIdempotentAndRetainsOriginals() throws {
        let dir = try root(), db = store(dir), firstGame = UUID(), secondGame = UUID()
        let folder = dir.appendingPathComponent("Library/Companion/chat")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = ChatMessage(role: "user", text: "曾经聊过的推理作品", createdAt: Date(timeIntervalSince1970: 1))
        let second = ChatMessage(role: "assistant", text: "后来聊过的音乐", createdAt: Date(timeIntervalSince1970: 2))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let a = try encoder.encode([first]), b = try encoder.encode([first, second])
        let fileA = folder.appendingPathComponent(firstGame.uuidString + ".json"), fileB = folder.appendingPathComponent(secondGame.uuidString + ".json")
        try a.write(to: fileA); try b.write(to: fileB)
        try db.migrateLegacyChats(gameTitles: [firstGame: "天津罪", secondGame: "纸上的魔法使"])
        Checks.equal(try db.loadMessages().count, 2)
        Checks.expect(try db.loadMessages().allSatisfy { $0.gameID != nil && $0.gameTitle != nil })
        Checks.expect(try db.isMigrationDone())
        try store(dir).migrateLegacyChats(gameTitles: [firstGame: "新的显示名"])
        Checks.equal(try db.loadMessages().count, 2)
        Checks.equal(try Data(contentsOf: fileA), a); Checks.equal(try Data(contentsOf: fileB), b)
        try db.clearMessages()
        try db.migrateLegacyChats(gameTitles: [:])
        Checks.expect(try db.loadMessages().isEmpty, "cleared chat is not re-imported on restart")
    }
    func testMalformedLegacyFileRollsBackWithoutPartialImport() throws {
        let dir = try root(), db = store(dir), idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let folder = dir.appendingPathComponent("Library/Companion/chat")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let valid = try encoder.encode([ChatMessage(role: "user", text: "旧消息")])
        try valid.write(to: folder.appendingPathComponent(idA.uuidString + ".json"))
        let badFile = folder.appendingPathComponent(idB.uuidString + ".json")
        try Data("{broken}".utf8).write(to: badFile)
        Checks.throwsError(try db.migrateLegacyChats(gameTitles: [:]))
        Checks.expect(try db.loadMessages().isEmpty)
        Checks.expect(try !db.isMigrationDone())
        try valid.write(to: badFile)
        try db.migrateLegacyChats(gameTitles: [:])
        Checks.equal(try db.loadMessages().count, 1)
    }
    func testOriginalGameIndexExecutableSaveAndPrefixUntouched() throws {
        let dir = try root(), fm = FileManager.default
        let relative = ["Library/library.json", "Library/Games/A/content/game.exe", "Library/Games/A/content/savedata/slot.ksd", "Library/Prefixes/A/user.reg"]
        let data = Data([0,255,13,37,5,67])
        for path in relative {
            let url = dir.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let db = store(dir)
        try db.append(ChatMessage(role: "user", text: "测试长期记忆"))
        try db.saveNote(MemoryNote(text: "测试固定事项"))
        try db.migrateLegacyChats(gameTitles: [:]); try db.clearMessages()
        for path in relative { Checks.equal(try Data(contentsOf: dir.appendingPathComponent(path)), data, path) }
    }
    func testSymbolicLinksAtFolderDatabaseWALAndSHMAreRejected() throws {
        let fm = FileManager.default
        for name in ["Companion", "memory.sqlite", "memory.sqlite-wal", "memory.sqlite-shm", "memory.sqlite-journal"] {
            let dir = try root(), outside = try root()
            let target: URL
            if name == "Companion" {
                try fm.createDirectory(at: dir.appendingPathComponent("Library"), withIntermediateDirectories: true)
                target = dir.appendingPathComponent("Library/Companion")
                try fm.createSymbolicLink(at: target, withDestinationURL: outside)
            } else {
                try fm.createDirectory(at: dir.appendingPathComponent("Library/Companion"), withIntermediateDirectories: true)
                target = dir.appendingPathComponent("Library/Companion/" + name)
                try Data("untouched".utf8).write(to: outside.appendingPathComponent("victim"))
                try fm.createSymbolicLink(at: target, withDestinationURL: outside.appendingPathComponent("victim"))
            }
            Checks.throwsError(try store(dir).append(ChatMessage(role: "user", text: "不能写入")))
            if name != "Companion" { Checks.equal(try Data(contentsOf: outside.appendingPathComponent("victim")), Data("untouched".utf8)) }
        }
    }
    func testLegacyChatSymlinkAndHardlinkedDatabaseAreRejected() throws {
        let dir = try root(), db = store(dir), fm = FileManager.default, outside = try root()
        _ = try db.loadMessages()
        try fm.createSymbolicLink(at: dir.appendingPathComponent("Library/Companion/chat"), withDestinationURL: outside)
        Checks.throwsError(try db.migrateLegacyChats(gameTitles: [:]))
        try fm.linkItem(at: db.databaseURL, to: outside.appendingPathComponent("hardlink.sqlite"))
        Checks.throwsError(try db.append(ChatMessage(role: "user", text: "禁止硬链接写入")))
    }
    func testChronologicalWindowAndBounds() throws {
        let dir = try root(), db = store(dir)
        for i in 0..<8 { try db.append(ChatMessage(role: "user", text: "消息\(i)", createdAt: Date(timeIntervalSince1970: Double(i)))) }
        Checks.equal(try db.loadMessages(limit: 3).map { $0.text }, ["消息5", "消息6", "消息7"])
        Checks.expect(try db.loadMessages(limit: 0).isEmpty)
        Checks.expect(try db.search(query: "", limit: 3).isEmpty)
        Checks.expect(try db.search(query: "消息", limit: 0).isEmpty)
        Checks.equal(try db.search(query: "消息", limit: 2).count, 2)
    }
    func testLegacyMessageJSONRemainsCompatible() throws {
        let data = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "role": "user", "text": "旧消息", "sources": [], "createdAt": "2023-11-14T22:13:20Z"])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: data)
        Checks.expect(message.gameID == nil && message.gameTitle == nil)
    }
    func testInvalidNotesAndMessagesDoNotChangeArchive() throws {
        let dir = try root(), db = store(dir)
        Checks.throwsError(try db.saveNote(MemoryNote(text: " \n ")))
        Checks.throwsError(try db.saveNote(MemoryNote(text: String(repeating: "字", count: 4001))))
        Checks.throwsError(try db.append(ChatMessage(role: "", text: "无角色")))
        Checks.expect(try db.loadMessages().isEmpty)
        Checks.expect(try db.notes().isEmpty)
    }
}

let suite = MemoryChecks()
let cases: [(String, () throws -> Void)] = [
    ("persistence, labels, sources, duplicate IDs", suite.testPersistenceLabelsSourcesAndDuplicateIDs),
    ("cross-game Chinese retrieval and exclusion", suite.testCrossGameCJKSearchAndExclusion),
    ("notes survive chat clearing", suite.testPinnedNotesRemainAfterClearingConversation),
    ("SQL and FTS input parameterization", suite.testParameterizedTextCannotBecomeSQL),
    ("legacy migration idempotency and source preservation", suite.testMigrationIsAtomicIdempotentAndRetainsOriginals),
    ("malformed migration transaction rollback", suite.testMalformedLegacyFileRollsBackWithoutPartialImport),
    ("game, save, index, prefix preservation", suite.testOriginalGameIndexExecutableSaveAndPrefixUntouched),
    ("directory, database, WAL, SHM symlink rejection", suite.testSymbolicLinksAtFolderDatabaseWALAndSHMAreRejected),
    ("legacy symlink and database hardlink rejection", suite.testLegacyChatSymlinkAndHardlinkedDatabaseAreRejected),
    ("chronological window and limits", suite.testChronologicalWindowAndBounds),
    ("old message JSON compatibility", suite.testLegacyMessageJSONRemainsCompatible),
    ("invalid memory writes preserve archive", suite.testInvalidNotesAndMessagesDoNotChangeArchive)
]
for (name, run) in cases {
    let before = Checks.failures.count
    do { try run() } catch { Checks.failures.append(name + ": " + error.localizedDescription) }
    suite.cleanup.reversed().forEach { $0() }; suite.cleanup.removeAll()
    print((Checks.failures.count == before ? "PASS " : "FAIL ") + name)
}
if !Checks.failures.isEmpty { Checks.failures.forEach { print($0) }; exit(1) }
print("Shared local memory: \(cases.count)/\(cases.count) checks passed; no network or Keychain mutations.")
