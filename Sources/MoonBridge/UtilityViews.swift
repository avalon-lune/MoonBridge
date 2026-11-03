import SwiftUI
import MoonBridgeCore

struct RuntimeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack { SectionTitle(eyebrow: "BEHIND EVERY STORY", title: "准备好，去另一个世界", subtitle: "检查本地运行组件，每款游戏的设置彼此独立。"); Spacer(); Button("重新检查") { model.checkRuntime() }.buttonStyle(SoftStyle()) }
            HStack(spacing: 16) {
                statusCard("Windows 运行内核", value: model.runtime.wineVersion, icon: "shippingbox", ready: model.runtime.wineReady)
                statusCard("指令翻译", value: "Apple Rosetta", icon: "cpu", ready: model.runtime.rosettaReady)
                statusCard("游戏包导入", value: "7-Zip · ZIP / 7Z / RAR", icon: "doc.zipper", ready: model.runtime.archiverReady)
            }
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Image(systemName: "sparkles.tv").foregroundStyle(Palette.blue); Text("画面、语言与声音").font(.system(size: 15, weight: .semibold)); Spacer(); Tag(text: "按游戏配置", tint: Palette.pink) }
                    runtimeLine("日文 / 中文区域", note: "可在游戏详情切换；汉化版也可能依赖日文区域。", icon: "character.bubble")
                    runtimeLine("窗口与全屏", note: "默认跟随游戏全屏开关；异常时可选择固定尺寸的虚拟桌面。", icon: "arrow.up.left.and.arrow.down.right")
                    runtimeLine("视频播放", note: model.runtime.mediaReady ? "已接入本地视频组件；OP / ED 与特殊编码仍需按游戏验证。" : "基础播放由运行内核提供；特殊视频格式需要进一步验证。", icon: "film")
                    runtimeLine("独立存档环境", note: "游戏副本、Windows 用户目录与运行日志保存在项目中。", icon: "externaldrive")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Card {
                VStack(alignment: .leading, spacing: 15) {
                    Text("你的 MoonBridge 在这里").font(.system(size: 14, weight: .semibold))
                    Text(model.paths.root.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    HStack { Button { model.reveal(model.paths.root) } label: { Label("打开项目文件夹", systemImage: "folder") }.buttonStyle(SoftStyle()); Button { model.exportDiagnostics() } label: { Label("导出诊断信息", systemImage: "square.and.arrow.up") }.buttonStyle(SoftStyle()) }
                    Text("MoonBridge 界面原生运行。Windows 游戏通过本地兼容层启动，是否可完整游玩请以实际测试为准。").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    func statusCard(_ title: String, value: String, icon: String, ready: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Palette.blue); Spacer(); Circle().fill(ready ? Color.green.opacity(0.7) : Palette.pink).frame(width: 6, height: 6) }
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(value).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
                Tag(text: ready ? "已就绪" : "待检查", tint: ready ? Palette.blue : Palette.pink)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func runtimeLine(_ title: String, note: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 13) { Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Palette.blue).frame(width: 22); VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 12, weight: .medium)); Text(note).font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4) }; Spacer() }
    }
}
struct ActivityView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack { SectionTitle(eyebrow: "LITTLE FOOTPRINTS", title: "故事经过的地方", subtitle: "查看启动记录，给偶尔的小故障留一点线索。"); Spacer(); Button("导出诊断") { model.exportDiagnostics() }.buttonStyle(SoftStyle()) }
            if model.document.games.isEmpty {
                Card { VStack(spacing: 15) { Image(systemName: "clock.badge.questionmark").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Palette.blue); Text("第一段足迹，还在等你。").font(.system(size: 15, weight: .medium)); Text("导入并启动游戏后，这里会留下它的运行记录。").font(.system(size: 11)).foregroundStyle(Palette.muted); Button("导入游戏") { model.chooseGame() }.buttonStyle(PrimaryStyle()) }.frame(maxWidth: .infinity).padding(40) }
            }
            ForEach(model.document.games.sorted { ($0.lastPlayedAt ?? $0.importedAt) > ($1.lastPlayedAt ?? $1.importedAt) }) { game in
                Card { HStack(spacing: 17) { Image(systemName: "book.closed").font(.system(size: 25, weight: .light)).foregroundStyle(Palette.blue); VStack(alignment: .leading, spacing: 7) { Text(game.title).font(.system(size: 13, weight: .semibold)); Text(game.lastResult + (game.lastPlayedAt.map { "  ·  " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")).font(.system(size: 10)).foregroundStyle(Palette.muted) }; Spacer(); Button("运行日志") { model.showLog(for: game) }.buttonStyle(SoftStyle()); Button("游戏设置") { model.detailID = game.id }.buttonStyle(SoftStyle()) } }
            }
            if !model.events.isEmpty { Card { VStack(alignment: .leading, spacing: 12) { Text("本次打开期间").font(.system(size: 13, weight: .semibold)); ForEach(Array(model.events.prefix(30).enumerated()), id: \.offset) { item in Text(item.element).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled) } }.frame(maxWidth: .infinity, alignment: .leading) } }
        }
    }
}
struct GuideView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionTitle(eyebrow: "BEFORE THE FIRST CHAPTER", title: "故事开始之前", subtitle: "从导入到第一次存档，一步一步就好。")
            HeroBanner()
            guide("01", "导入完整游戏", "选择 ZIP、7Z、RAR 或完整文件夹。单独的 EXE 往往还需要同目录的图片、声音和脚本。压缩包有密码时，在导入窗口填写。", icon: "tray.and.arrow.down", tint: Palette.blue)
            guide("02", "应用汉化补丁", "已经汉化的游戏可以直接尝试运行。另附补丁压缩包时，在游戏详情中选择并应用；覆盖的原文件会保存在备份目录。补丁有特殊安装步骤时，请先阅读随包说明。", icon: "character.book.closed", tint: Palette.pink)
            guide("03", "选择主程序与区域", "优先选择游戏本体或汉化启动器。首次运行会创建独立环境，可能需要稍等。若只有 setup.exe，请先运行安装，再点击“重新扫描”。日文原版通常使用日文区域；汉化版按说明选择。", icon: "slider.horizontal.3", tint: Palette.blue)
            guide("04", "验证画面和声音", "先阅读一小段剧情，检查文字、立绘、背景音乐、语音与 OP / ED。使用游戏本身的全屏开关，部分游戏支持 Alt + Enter；若黑屏或窗口异常，尝试虚拟桌面。", icon: "play.rectangle", tint: Palette.pink)
            guide("05", "存一次，再读一次", "实际保存并重新读取进度，然后在游戏详情的“游玩验证清单”记录结果。遇到无响应或退出，可查看运行日志并切换语言、显示或兼容版本。", icon: "bookmark", tint: Palette.blue)
        }
    }
    func guide(_ number: String, _ title: String, _ text: String, icon: String, tint: Color) -> some View {
        Card { HStack(alignment: .top, spacing: 20) { Text(number).font(.system(size: 26, weight: .ultraLight, design: .rounded)).foregroundStyle(tint.opacity(0.65)).frame(width: 37); VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold)); Text(text).font(.system(size: 11)).lineSpacing(6).foregroundStyle(Palette.muted) }; Spacer() } }
    }
}
