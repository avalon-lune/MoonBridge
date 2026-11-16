import Foundation
import MoonBridgeCore

private enum CheckResults {
    static var failures: [String] = []
    static func fail(_ text: String, file: String, line: UInt) { failures.append("\(file):\(line) \(text)") }
}
private func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #fileID, line: UInt = #line) {
    if a != b { CheckResults.fail("expected equal: \(message)", file: file, line: line) }
}
private func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #fileID, line: UInt = #line) {
    if a == b { CheckResults.fail("expected different: \(message)", file: file, line: line) }
}
private func expectTrue(_ value: Bool, _ message: String = "", file: String = #fileID, line: UInt = #line) {
    if !value { CheckResults.fail("expected true: \(message)", file: file, line: line) }
}
private func expectFalse(_ value: Bool, _ message: String = "", file: String = #fileID, line: UInt = #line) { expectTrue(!value, message, file: file, line: line) }
private func expectNil<T>(_ value: T?, file: String = #fileID, line: UInt = #line) {
    if value != nil { CheckResults.fail("expected nil", file: file, line: line) }
}
private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw BridgeError("Required test value was nil") }; return value
}
private func expectThrows<T>(_ body: @autoclosure () throws -> T, _ message: String = "", file: String = #fileID, line: UInt = #line, handler: ((Error) -> Void)? = nil) {
    do { _ = try body(); CheckResults.fail("expected error: \(message)", file: file, line: line) } catch { handler?(error) }
}

final class CompanionChecks {
    var cleanup: [() -> Void] = []
    func addTeardownBlock(_ block: @escaping () -> Void) { cleanup.append(block) }
    func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoonBridge-CompanionTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func encoded(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    func testStorePreservesLegacyLibraryGameAndSaveBytes() throws {
        let root = try temporaryRoot(), paths = ProjectPaths(root: root)
        let fm = FileManager.default
        let legacy = root.appendingPathComponent("Library/library.json")
        let game = root.appendingPathComponent("Library/Games/legacy/content/game.exe")
        let save = root.appendingPathComponent("Library/Games/legacy/content/savedata/slot.ksd")
        let prefix = root.appendingPathComponent("Library/Prefixes/legacy/user.reg")
        let fixtures = [(legacy, Data("{\"version\":1,\"games\":[]}".utf8)), (game, Data([0x4d,0x5a,0,37])), (save, Data([0,255,13,42])), (prefix, Data("old-prefix".utf8))]
        for (url, bytes) in fixtures { try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try bytes.write(to: url) }
        let store = CompanionStore(paths: paths), id = UUID()
        var settings = CompanionSettings(); settings.autoLookup = false
        try store.saveSettings(settings)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = GameMetadata(id: "v17", title: "测试作品", originalTitle: "Test", summary: "有来源的简介", developer: "Studio", sourceURL: "https://vndb.org/v17", fetchedAt: date)
        try store.saveMetadata(metadata, gameID: id)
        expectEqual(try store.loadMetadata(gameID: id), metadata)
        expectEqual(try store.loadSettings(), settings)
        let chat = [ChatMessage(role: "user", text: "测试问题", createdAt: date), ChatMessage(role: "assistant", text: "有来源的回答", sources: [SourceLink(title: "来源", url: "https://vndb.org/v17")], createdAt: date)]
        try store.saveChat(chat, gameID: id)
        expectEqual(try store.loadChat(gameID: id), chat)
        try store.clearChat(gameID: id)
        expectEqual(try store.loadChat(gameID: id), [])
        for (url, bytes) in fixtures { expectEqual(try Data(contentsOf: url), bytes, url.path) }
    }
    func testLegacyMetadataAndSummaryProvenanceRoundTrip() throws {
        let root = try temporaryRoot(), store = CompanionStore(paths: ProjectPaths(root: root)), id = UUID()
        let legacy: [String: Any] = ["id": "v17", "title": "原名", "originalTitle": "原名", "summary": "Source paragraph", "developer": "Studio", "releaseDate": "2020-01-01", "tags": [], "sourceURL": "https://vndb.org/v17", "fetchedAt": "2023-11-14T22:13:20Z"]
        let folder = root.appendingPathComponent("Library/Companion/metadata")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoded(legacy).write(to: folder.appendingPathComponent(id.uuidString + ".json"))
        var restored = try unwrap(try store.loadMetadata(gameID: id))
        expectNil(restored.originalSummary); expectNil(restored.summaryOrigin)
        restored.originalSummary = restored.summary
        restored.summaryOrigin = "ai"
        restored.summary = "中文整理后的简介"
        try store.saveMetadata(restored, gameID: id)
        let persisted = try unwrap(try store.loadMetadata(gameID: id))
        expectEqual(persisted.originalSummary, "Source paragraph")
        expectEqual(persisted.summaryOrigin, "ai")
        expectEqual(persisted.summary, "中文整理后的简介")
        expectEqual(persisted.sourceURL, "https://vndb.org/v17")
    }
    func testSettingsPrevalidationRejectsInvalidProxyAndReasoning() throws {
        var settings = CompanionSettings()
        try CompanionStore.validateSettings(settings)
        settings.proxyURL = "http://127.0.0.1:70000"
        expectThrows(try CompanionStore.validateSettings(settings))
        settings.proxyURL = "http://127.0.0.1:7897"
        settings.reasoningEffort = "unknown"
        expectThrows(try CompanionStore.validateSettings(settings))
        settings.reasoningEffort = "medium"
        try CompanionStore.validateSettings(settings)
    }
    func testEmptyStoreDoesNotCreateGameOrPrefixFolders() throws {
        let root = try temporaryRoot(), store = CompanionStore(paths: ProjectPaths(root: root))
        expectNil(try store.loadMetadata(gameID: UUID()))
        expectEqual(try store.loadChat(gameID: UUID()), [])
        expectTrue(try store.loadSettings().enabled)
        expectFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library").path))
    }
    func testSymlinkCompanionDirectoryCannotOverwriteGameFiles() throws {
        let root = try temporaryRoot(), fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Library/Games"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("Library/Companion"), withDestinationURL: root.appendingPathComponent("Library/Games"))
        let store = CompanionStore(paths: ProjectPaths(root: root))
        expectThrows(try store.saveSettings(CompanionSettings()))
        expectFalse(fm.fileExists(atPath: root.appendingPathComponent("Library/Games/settings.json").path))
    }
    func testEndpointNormalizationKeepsCredentialsSeparated() throws {
        expectEqual(try CompanionEndpoint.normalized(" HTTPS://API.OPENAI.COM:443/v1/ "), "https://api.openai.com/v1")
        expectNotEqual(try CompanionEndpoint.normalized("https://api.openai.com/v1"), try CompanionEndpoint.normalized("https://another.example/v1"))
        for url in ["http://api.openai.com/v1", "https://user:secret@example.com", "https://example.com?key=secret", "https://example.com/#part", "https://example.com/%2e%2e/secret", "file:///etc/passwd"] {
            expectThrows(try CompanionEndpoint.normalized(url), url)
        }
    }
    func testReplyRequestContainsOnlyBoundedReferenceContext() throws {
        let root = "/Users/private/Games/never-upload"
        var settings = CompanionSettings(); settings.webSearch = true
        let client = AIClient(settings: settings, key: "test-key-not-real")
        let info = GameMetadata(title: "作品", summary: "这是一段简介", sourceURL: "https://vndb.org/v17", coverPath: root)
        let history = (0..<30).map { ChatMessage(role: $0 % 2 == 0 ? "user" : "assistant", text: "第\($0)条消息") }
        let request = try client.replyRequest(question: "作者是谁？", gameTitle: "作品", metadata: info, history: history, allowSpoilers: false)
        expectEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key-not-real")
        let bytes = try unwrap(request.httpBody), raw = String(decoding: bytes, as: UTF8.self)
        expectFalse(raw.contains(root)); expectFalse(raw.contains("test-key-not-real"))
        let body = try unwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        expectEqual(body["store"] as? Bool, false)
        expectEqual((body["tools"] as? [[String: String]])?.first?["type"], "web_search")
        expectEqual((body["input"] as? [[String: String]])?.count, 14)
        expectTrue((body["instructions"] as? String ?? "").contains("未允许剧透"))
    }
    func testWebSearchToggleAndDisabledFeature() throws {
        var settings = CompanionSettings(); settings.webSearch = false
        let client = AIClient(settings: settings, key: "fake")
        let request = try client.replyRequest(question: "测试", gameTitle: "作品", metadata: nil, history: [], allowSpoilers: true)
        let body = try unwrap(try JSONSerialization.jsonObject(with: unwrap(request.httpBody)) as? [String: Any])
        expectNil(body["tools"])
        expectTrue((body["instructions"] as? String ?? "").contains("允许剧透"))
        settings.enabled = false
        expectThrows(try AIClient(settings: settings, key: "fake").replyRequest(question: "测试", gameTitle: "作品", metadata: nil, history: [], allowSpoilers: true))
    }
    func testCitationFixtureProducesClickableMarkdownAndSources() throws {
        let prefix = "中文😀内容。", marker = "citeturn0search0", suffix = "另一句话。"
        let text = prefix + marker + suffix
        let payload: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text, "annotations": [["type": "url_citation", "url": "https://vndb.org/v17", "title": "作品资料", "start_index": prefix.unicodeScalars.count, "end_index": (prefix + marker).unicodeScalars.count]]]]]]]
        let reply = try AIClient.parseResponse(encoded(payload))
        expectEqual(reply.role, "assistant")
        expectEqual(reply.sources, [SourceLink(title: "作品资料", url: "https://vndb.org/v17")])
        expectEqual(reply.text, prefix + "[来源](https://vndb.org/v17)" + suffix)
    }
    func testUnsafeCitationURLIsNeverExposedAsSource() throws {
        let payload: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": "参考资料citex", "annotations": [["type": "url_citation", "url": "javascript:alert(1)", "title": "unsafe"]]]]]]]
        let reply = try AIClient.parseResponse(encoded(payload))
        expectTrue(reply.sources.isEmpty)
        expectEqual(reply.text, "参考资料")
    }
    func testRefusalAndIncompleteNeverBecomeSuccessfulReply() throws {
        let refusal: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "refusal", "refusal": "no"]]]]]
        expectThrows(try AIClient.parseResponse(encoded(refusal)))
        expectThrows(try AIClient.parseResponse(encoded(["status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"], "output": []])))
        expectThrows(try AIClient.parseResponse(encoded(["status": "completed", "output": []])))
    }
    func testModelListFixtureAndSafeErrors() throws {
        let fixture: [String: Any] = ["object": "list", "data": [["id": "gpt-6.1-terra"], ["id": "custom-provider/my-model"], ["id": "gpt-6.1-terra"], ["id": "  "], ["id": "image-model"], ["id": "invalid\nmodel"], ["created": 123]]]
        expectEqual(try AIClient.parseModelList(encoded(fixture)), ["custom-provider/my-model", "gpt-6.1-terra", "image-model"])
        expectEqual(try AIClient.parseModelList(encoded(["data": []])), [])
        expectThrows(try AIClient.parseModelList(encoded(["object": "list"])))
        expectThrows(try AIClient.parseModelList(encoded(["data": "wrong-shape"])))
        let error = try encoded(["error": ["message": "DO_NOT_REFLECT_secret_key"]])
        expectThrows(try AIClient.parseModelList(error, statusCode: 401)) { error in
            expectFalse(error.localizedDescription.contains("DO_NOT_REFLECT_secret_key"))
            expectTrue(error.localizedDescription.contains("401"))
        }
    }
    func testHTTPErrorDoesNotReflectServerMessageOrCredentials() throws {
        let bytes = try encoded(["error": ["message": "Secret test-key-not-real copied into server error", "code": "invalid_key"]])
        for status in [301,400,401,403,429,500] {
            expectThrows(try AIClient.parseResponse(bytes, statusCode: status)) { error in
                expectFalse(error.localizedDescription.contains("test-key-not-real"))
                expectTrue(error.localizedDescription.contains(String(status)))
            }
        }
    }
    func testCatalogFixturesFilterSpoilerTagsAndRetainSourceIdentity() throws {
        let vn: [String: Any] = ["results": [["id": "v17", "title": "Original", "alttitle": "原名", "titles": [["lang": "zh-Hans", "title": "中文名"]], "description": "简介[spoiler]重大反转[/spoiler]", "developers": [["name": "Studio"]], "tags": [["name": "Mystery", "spoiler": 0, "lie": false, "rating": 2.0], ["name": "Killer", "spoiler": 2, "lie": false, "rating": 3.0]]]]]
        let result = try unwrap(try GameCatalog.parseVNDB(encoded(vn)).first)
        expectEqual(result.title, "中文名"); expectEqual(result.originalTitle, "原名")
        expectEqual(result.sourceURL, "https://vndb.org/v17"); expectEqual(result.tags, ["悬疑"])
        expectFalse(result.summary.contains("重大反转"))
        let bgm: [String: Any] = ["data": [["id": 123, "type": 4, "name": "原名", "name_cn": "中文", "summary": "简介", "tags": [["name": "galgame"], ["name": "主角死亡"]], "images": ["large": "https://lain.bgm.tv/pic/cover/l/1.jpg"]], ["id": 456, "type": 2, "name": "同名动画"]]]
        let matches = try GameCatalog.parseBangumi(encoded(bgm))
        expectEqual(matches.count, 1); expectEqual(matches.first?.id, "bgm:123"); expectEqual(matches.first?.tags, ["galgame"])
    }
    func testCoverAllowlistRejectsArbitraryURLsAndCredentials() {
        expectTrue(GameCatalog.isAllowedCoverURL("https://s.vndb.org/cv/1.jpg"))
        expectTrue(GameCatalog.isAllowedCoverURL("https://lain.bgm.tv/pic/cover/l/1.jpg"))
        for url in ["http://s.vndb.org/a.jpg", "https://s.vndb.org.evil.example/a.jpg", "https://user:pass@s.vndb.org/a.jpg", "https://s.vndb.org:444/a.jpg", "https://127.0.0.1/a.jpg"] { expectFalse(GameCatalog.isAllowedCoverURL(url), url) }
    }
    func testTitleCleanupPreservesDistinctGameNames() {
        expectEqual(GameCatalog.cleanedQuery("【汉化组】纸上的魔法使 [汉化版].zip"), "纸上的魔法使")
        expectNotEqual(GameCatalog.cleanedQuery("废村少女2.zip"), GameCatalog.cleanedQuery("废村少女.zip"))
    }
}

let checks = CompanionChecks()
let cases: [(String, () throws -> Void)] = [
    ("testStorePreservesLegacyLibraryGameAndSaveBytes", checks.testStorePreservesLegacyLibraryGameAndSaveBytes),
    ("testLegacyMetadataAndSummaryProvenanceRoundTrip", checks.testLegacyMetadataAndSummaryProvenanceRoundTrip),
    ("testSettingsPrevalidationRejectsInvalidProxyAndReasoning", checks.testSettingsPrevalidationRejectsInvalidProxyAndReasoning),
    ("testEmptyStoreDoesNotCreateGameOrPrefixFolders", checks.testEmptyStoreDoesNotCreateGameOrPrefixFolders),
    ("testSymlinkCompanionDirectoryCannotOverwriteGameFiles", checks.testSymlinkCompanionDirectoryCannotOverwriteGameFiles),
    ("testEndpointNormalizationKeepsCredentialsSeparated", checks.testEndpointNormalizationKeepsCredentialsSeparated),
    ("testReplyRequestContainsOnlyBoundedReferenceContext", checks.testReplyRequestContainsOnlyBoundedReferenceContext),
    ("testWebSearchToggleAndDisabledFeature", checks.testWebSearchToggleAndDisabledFeature),
    ("testCitationFixtureProducesClickableMarkdownAndSources", checks.testCitationFixtureProducesClickableMarkdownAndSources),
    ("testUnsafeCitationURLIsNeverExposedAsSource", checks.testUnsafeCitationURLIsNeverExposedAsSource),
    ("testRefusalAndIncompleteNeverBecomeSuccessfulReply", checks.testRefusalAndIncompleteNeverBecomeSuccessfulReply),
    ("testModelListFixtureAndSafeErrors", checks.testModelListFixtureAndSafeErrors),
    ("testHTTPErrorDoesNotReflectServerMessageOrCredentials", checks.testHTTPErrorDoesNotReflectServerMessageOrCredentials),
    ("testCatalogFixturesFilterSpoilerTagsAndRetainSourceIdentity", checks.testCatalogFixturesFilterSpoilerTagsAndRetainSourceIdentity),
    ("testCoverAllowlistRejectsArbitraryURLsAndCredentials", checks.testCoverAllowlistRejectsArbitraryURLsAndCredentials),
    ("testTitleCleanupPreservesDistinctGameNames", checks.testTitleCleanupPreservesDistinctGameNames)
]
for (name, run) in cases {
    let before = CheckResults.failures.count
    do { try run() } catch { CheckResults.failures.append(name + ": " + error.localizedDescription) }
    checks.cleanup.reversed().forEach { $0() }; checks.cleanup.removeAll()
    print((CheckResults.failures.count == before ? "PASS " : "FAIL ") + name)
}
if !CheckResults.failures.isEmpty { CheckResults.failures.forEach { print($0) }; exit(1) }
print("Companion regression: \(cases.count)/\(cases.count) checks passed; no network or Keychain mutations.")
