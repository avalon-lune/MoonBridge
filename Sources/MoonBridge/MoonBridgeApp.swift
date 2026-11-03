import SwiftUI
import AppKit
import MoonBridgeCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var finishing = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !finishing, let model, !model.running.isEmpty else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "还有游戏正在运行"; alert.informativeText = "请先在游戏内保存进度。停止运行环境会结束当前游戏。"; alert.addButton(withTitle: "返回游戏"); alert.addButton(withTitle: "停止游戏并退出")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        finishing = true
        let games = model.document.games.filter { model.running.contains($0.id) }; let engine = model.engine
        Task {
            await Task.detached { for game in games { try? engine.stop(game) } }.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct MoonBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("MoonBridge · 月渡", id: "main") {
            RootView().environmentObject(model)
                .frame(minWidth: 1100, minHeight: 760)
                .preferredColorScheme(.light)
                .task { delegate.model = model; model.checkRuntime() }
                .onOpenURL { url in model.acceptImport([url]) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) { Button("导入游戏…") { model.chooseGame() }.keyboardShortcut("o") }
            CommandGroup(replacing: .help) { Button("MoonBridge 使用指南") { model.section = .guide }; Button("打开项目文件夹") { model.reveal(model.paths.root) } }
        }
    }
}
