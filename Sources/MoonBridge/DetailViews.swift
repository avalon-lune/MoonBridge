import SwiftUI
import AppKit
import MoonBridgeCore

@MainActor final class SheetFields: ObservableObject {
    @Published var password = ""
    @Published var codePage = ""
    @Published var text = ""
}

struct ImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var fields = SheetFields()
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { SectionTitle(eyebrow: "A NEW STORY", title: "带一个故事过来", subtitle: "原始游戏包会保留，我们会导入一份独立副本。"); Spacer(); Image(systemName: "folder.badge.plus").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Palette.blue) }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(model.importSources, id: \.path) { url in
                    HStack { Image(systemName: url.hasDirectoryPath ? "folder" : "doc.zipper").foregroundStyle(Palette.blue); Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(2); Spacer() }.padding(12).background(Palette.wash, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("解压选项").font(.system(size: 13, weight: .semibold))
                HStack { Text("文件名编码").frame(width: 100, alignment: .leading); Picker("", selection: $fields.codePage) { Text("自动识别（推荐）").tag(""); Text("日文 · CP932").tag("932"); Text("简体中文 · GBK").tag("936") }.labelsHidden().frame(maxWidth: .infinity) }
                HStack { Text("解压密码").frame(width: 100, alignment: .leading); SecureField("没有密码可留空", text: $fields.password).textFieldStyle(.roundedBorder) }
                Text("如果解压后的日文或中文文件名乱码，可重新导入并切换文件名编码。密码仅用于本次解压，不会保存。").font(.system(size: 10)).lineSpacing(4).foregroundStyle(Palette.muted)
            }.font(.system(size: 12))
            HStack(alignment: .top, spacing: 9) { Image(systemName: "sparkles").foregroundStyle(Palette.pink); Text("若游戏包内另附汉化压缩包，导入后可在游戏详情中选择“附带压缩包”，先备份再应用。补丁需要原版游戏文件。").font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.muted) }.padding(15).background(Palette.pink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            HStack { Button("取消") { dismiss() }.buttonStyle(SoftStyle()); Spacer(); Button { model.beginImport(options: ImportOptions(password: fields.password, filenameCodePage: fields.codePage)) } label: { Label("导入这个故事", systemImage: "arrow.down.to.line") }.buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 580).background(Color.white)
    }
}
struct GameDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let gameID: UUID
    static let checks = ["标题与正文", "立绘与动画", "背景音乐", "角色语音", "OP / ED 视频", "存档与读档", "全屏与鼠标"]
    func field<T>(_ keyPath: WritableKeyPath<Game, T>) -> Binding<T> {
        Binding(get: { model.game(gameID)![keyPath: keyPath] }, set: { value in guard var game = model.game(gameID) else { return }; game[keyPath: keyPath] = value; model.update(game) })
    }
    var body: some View {
        Group {
            if let game = model.game(gameID) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 19) {
                        ArtView(cover: game.coverPath, alignment: .trailing).frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 14))
                        HStack { Tag(text: game.selected?.architecture ?? "待选择程序"); Spacer() }
                        Text(game.engine).font(.system(size: 13, weight: .semibold))
                        Text(ByteCountFormatter.string(fromByteCount: game.sizeBytes, countStyle: .file) + "  ·  " + game.importedAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Button { model.chooseCover(for: game) } label: { Label("更换封面", systemImage: "photo") }.buttonStyle(SoftStyle())
                        Spacer()
                        Text("YOUR NEXT CHAPTER").tracking(1.7).font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.blue)
                        Text(model.running.contains(gameID) ? model.status : "故事可以慢慢读，\n喜欢可以留很久。").font(.system(size: 15, weight: .light)).lineSpacing(7).foregroundStyle(Palette.ink.opacity(0.7))
                    }.padding(25).frame(width: 272).background(LinearGradient(colors: [Palette.blue.opacity(0.09), Palette.pink.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("STORY SETTINGS").tracking(1.8).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.blue)
                                TextField("故事名称", text: field(\.title)).textFieldStyle(.plain).font(.system(size: 23, weight: .bold))
                            }
                            Spacer()
                            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(width: 27, height: 27).background(Palette.wash, in: Circle()) }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
                        }.padding(.bottom, 21)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 21) {
                                if let notice = model.notice {
                                    HStack(alignment: .top) { Image(systemName: "checkmark.circle").foregroundStyle(Palette.blue); Text(notice).font(.system(size: 10)).lineSpacing(4).textSelection(.enabled); Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }.padding(12).background(Palette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 9) {
                                    Text("游戏主程序").font(.system(size: 12, weight: .semibold))
                                    if game.candidates.isEmpty {
                                        Text("尚未找到 Windows 32/64 位 EXE。请检查是否导入了完整游戏，或包内是否还有待解压的游戏主体。").font(.system(size: 11)).foregroundStyle(Palette.pink)
                                    } else {
                                        Picker("游戏主程序", selection: field(\.selectedExecutable)) {
                                            ForEach(game.candidates) { candidate in Text(candidate.name + " · " + candidate.architecture + (candidate.isInstaller ? " · 安装程序" : "")).tag(candidate.relativePath) }
                                        }.labelsHidden().frame(maxWidth: .infinity)
                                        Text(game.selectedExecutable).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled).lineLimit(3)
                                        if game.selected?.isInstaller == true { Text("这是安装程序。安装完成后点击“重新扫描”，再选择安装后的游戏 EXE。").font(.system(size: 10)).foregroundStyle(Palette.blue) }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack { Text("语言区域").frame(width: 76, alignment: .leading); Picker("语言区域", selection: field(\.profile.locale)) { ForEach(GameLocale.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
                                    Text("汉化版也可能需要日文区域，请以补丁说明为准。").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    HStack { Text("显示方式").frame(width: 76, alignment: .leading); Picker("显示方式", selection: field(\.profile.display)) { ForEach(DisplayMode.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
                                    if game.profile.display == .desktop {
                                        HStack { Text("桌面尺寸").frame(width: 76, alignment: .leading); TextField("宽", value: field(\.profile.width), format: .number.grouping(.never)).frame(width: 75); Text("×").foregroundStyle(Palette.muted); TextField("高", value: field(\.profile.height), format: .number.grouping(.never)).frame(width: 75); Text("像素").foregroundStyle(Palette.muted); Spacer() }.textFieldStyle(.roundedBorder)
                                    }
                                    HStack { Text("兼容版本").frame(width: 76, alignment: .leading); Picker("兼容版本", selection: field(\.profile.windowsVersion)) { Text("Windows 10（默认）").tag("win10"); Text("Windows 7").tag("win7"); Text("Windows XP").tag("winxp") }.labelsHidden() }
                                }.font(.system(size: 11))
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("汉化与附带内容").font(.system(size: 12, weight: .semibold)); Spacer()
                                        Button("选择汉化补丁…") { model.choosePatch(for: game) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.blue)
                                    }
                                    if game.bundledPatches.isEmpty { Text("暂未发现内嵌压缩包；可选择独立补丁包，或直接运行已经汉化的游戏。").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                                    else { ForEach(game.bundledPatches, id: \.self) { patch in
                                        HStack { Image(systemName: "doc.zipper").foregroundStyle(Palette.pink); Text(URL(fileURLWithPath: patch).lastPathComponent).font(.system(size: 10)).lineLimit(1); Spacer(); Button("备份并应用…") { if let url = try? model.paths.url(patch) { model.presentPatch(url, game: game) } }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.blue) }
                                    } }
                                }.padding(14).background(Palette.pink.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("按实际游玩结果勾选；进程启动或退出不代表已经兼容。").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 7)
                                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 9) {
                                            ForEach(Self.checks, id: \.self) { check in
                                                Toggle(check, isOn: Binding(get: { model.game(gameID)?.validation[check] ?? false }, set: { value in guard var latest = model.game(gameID) else { return }; latest.validation[check] = value; model.update(latest) })).toggleStyle(.checkbox).font(.system(size: 10))
                                            }
                                        }
                                    }
                                } label: { Text("游玩验证清单 · \(game.validation.values.filter { $0 }.count)/\(Self.checks.count)").font(.system(size: 11, weight: .medium)) }.tint(Palette.blue)
                                HStack(spacing: 8) {
                                    Button { model.revealContent(game) } label: { Label("游戏文件", systemImage: "folder") }.buttonStyle(SoftStyle())
                                    Button { model.revealSaves(game) } label: { Label("存档环境", systemImage: "externaldrive") }.buttonStyle(SoftStyle())
                                    Button { model.showLog(for: game) } label: { Label("运行日志", systemImage: "text.alignleft") }.buttonStyle(SoftStyle())
                                }
                            }.padding(.trailing, 6)
                        }.scrollIndicators(.hidden)
                        Divider().overlay(Palette.line).padding(.vertical, 17)
                        HStack(spacing: 10) {
                            Button("重新扫描") { model.rescan(game) }.buttonStyle(SoftStyle()).disabled(model.operation || model.running.contains(game.id))
                            Menu { Button("打开 Windows 配置") { model.wineConfiguration(game) }; Button("打开备份文件夹") { let path = model.paths.root.appendingPathComponent("Library/Backups"); model.reveal(path) } } label: { Image(systemName: "ellipsis").frame(width: 16, height: 17) }.menuStyle(.borderlessButton).frame(width: 28)
                            Spacer()
                            if model.running.contains(game.id) { Button { model.stop(game) } label: { Label("停止运行", systemImage: "stop.fill") }.buttonStyle(SoftStyle(pink: true)) }
                            else { Button { model.launch(game) } label: { Label(game.selected?.isInstaller == true ? "运行安装程序" : "开始这个故事", systemImage: "play.fill") }.buttonStyle(PrimaryStyle()).disabled(model.operation || game.selectedExecutable.isEmpty) }
                        }
                    }.padding(28).frame(maxWidth: .infinity)
                }.frame(width: 925, height: 715).background(.white).foregroundStyle(Palette.ink)
            } else { Text("游戏记录不可用").padding(50) }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
        .sheet(isPresented: $model.showPatch) { PatchSheet().environmentObject(model) }
        .sheet(isPresented: $model.showLog) { LogView().environmentObject(model) }
    }
}
struct PatchSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var fields = SheetFields()
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle(eyebrow: "A LITTLE TRANSLATION MAGIC", title: "让故事说熟悉的语言", subtitle: "应用独立汉化包，原文件会先备份。")
            VStack(alignment: .leading, spacing: 12) {
                Text("补丁：" + (model.patchSource?.lastPathComponent ?? "")).font(.system(size: 12, weight: .semibold))
                if let id = model.patchGameID, let game = model.game(id) {
                    Text("目标：" + ((try? model.paths.url(game.selectedExecutable))?.deletingLastPathComponent().path ?? "")).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
                Text("请确认这是游戏文件补丁。如果补丁要求运行安装器，请导入后直接选择它的 EXE 运行。").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Palette.wash, in: RoundedRectangle(cornerRadius: 12))
            Picker("文件名编码", selection: $fields.codePage) { Text("自动识别").tag(""); Text("日文 CP932").tag("932"); Text("简体中文 GBK").tag("936") }.font(.system(size: 12))
            SecureField("解压密码（没有可留空）", text: $fields.password).textFieldStyle(.roundedBorder)
            HStack { Button("取消") { dismiss() }.buttonStyle(SoftStyle()); Spacer(); Button("备份并应用补丁") { model.applyPatch(options: ImportOptions(password: fields.password, filenameCodePage: fields.codePage)) }.buttonStyle(PrimaryStyle()) }
        }.padding(30).frame(width: 575).background(.white)
    }
}
struct LogView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var fields = SheetFields()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { SectionTitle(eyebrow: "SESSION NOTES", title: "运行日志", subtitle: model.logGameID.flatMap { model.game($0)?.title } ?? "MoonBridge"); Spacer(); Button("关闭") { dismiss() }.buttonStyle(SoftStyle()).keyboardShortcut(.cancelAction) }
            ScrollView { Text(fields.text).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(17) }.background(Palette.wash, in: RoundedRectangle(cornerRadius: 13))
            HStack { Text("日志保存在项目内，可直接复制用于排查。").font(.system(size: 10)).foregroundStyle(Palette.muted); Spacer(); Button("复制日志") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(fields.text, forType: .string) }.buttonStyle(SoftStyle()); Button("在 Finder 中查看") { if let id = model.logGameID { model.reveal(model.paths.log(id)) } }.buttonStyle(SoftStyle()) }
        }.padding(28).frame(width: 830, height: 600).background(.white)
            .task {
                while !Task.isCancelled {
                    if let id = model.logGameID, let data = try? Data(contentsOf: model.paths.log(id)) { fields.text = String(decoding: data.suffix(200_000), as: UTF8.self) }
                    else { fields.text = "第一次启动后将在这里生成运行日志。" }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}
