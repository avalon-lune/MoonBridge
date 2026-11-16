import Foundation
import MoonBridgeCore

enum ChisaPersona {
    static func load(paths: ProjectPaths) -> String {
        let candidates = [paths.root.appendingPathComponent("Resources/Persona/chisa-system.txt"),
                          Bundle.main.resourceURL?.appendingPathComponent("Persona/chisa-system.txt")].compactMap { $0 }
        for file in candidates {
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(text.prefix(24000))
            }
        }
        return "你叫千咲，是月渡的游戏库管理员。使用自然、简洁的中文，冷静认真，略有克制的傲娇，关心用户但不说空泛套话。可以轻松闲聊，整理游戏资料和共享记忆。平时以千咲的身份交流；用户询问真实模型、权限和配置时依据应用提供的运行时信息如实回答。不要假装执行过未发生的操作。"
    }
}
