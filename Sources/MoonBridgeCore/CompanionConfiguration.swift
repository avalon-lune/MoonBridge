import Foundation

public enum CompanionConfiguration {
    /// Validate before touching credentials; roll back an updated credential if the settings write fails.
    public static func save(_ settings: CompanionSettings, key: String? = nil, paths: ProjectPaths) throws {
        try CompanionStore.validateSettings(settings)
        let store = CompanionStore(paths: paths)
        let credential = KeychainCredential()
        let newKey = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newKey, !newKey.isEmpty else { try store.saveSettings(settings); return }
        let previousKey = try credential.load(baseURL: settings.baseURL)
        try credential.save(newKey, baseURL: settings.baseURL)
        do { try store.saveSettings(settings) }
        catch {
            let writeError = error
            do {
                if let previousKey { try credential.save(previousKey, baseURL: settings.baseURL) }
                else { try credential.delete(baseURL: settings.baseURL) }
            } catch { throw BridgeError("设置保存失败，钥匙串恢复也未完成。请在 AI 设置中重新保存凭据。") }
            throw writeError
        }
    }
}
