import SwiftUI
import UniformTypeIdentifiers
import MoonBridgeCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var errorPresented: Binding<Bool> { Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }) }
    var noticePresented: Binding<Bool> { Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }) }
    var body: some View {
        HStack(spacing: 0) {
            SidebarView().frame(width: 218)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                mainContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBar()
            }
            .background(Palette.canvas)
        }
        .foregroundStyle(Palette.ink)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $model.dragActive, perform: model.handleDrop)
        .overlay {
            if model.dragActive {
                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(Palette.blue.opacity(0.06))
                    RoundedRectangle(cornerRadius: 22).stroke(Palette.blue, style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
                    Label("松开以导入游戏", systemImage: "tray.and.arrow.down.fill")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.blue)
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }.padding(12).allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $model.showImport) { ImportSheet().environmentObject(model) }
        .sheet(isPresented: $model.showLog) { LogView().environmentObject(model) }
        .alert("操作未完成", isPresented: errorPresented) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert("月渡", isPresented: noticePresented) { Button("好的") { model.notice = nil } } message: { Text(model.notice ?? "") }
        .onChange(of: model.detailID) { _, id in if id != nil { model.section = .library } }
        .onChange(of: model.section) { _, section in if section != .library { model.detailID = nil } }
    }
    @ViewBuilder private var mainContent: some View {
        if model.section == .library, let id = model.detailID {
            GameHomeView(gameID: id).id(id)
        } else if model.section == .settings {
            CompanionSettingsView()
        } else {
            ScrollView {
                Group {
                    switch model.section {
                    case .library: LibraryView()
                    case .runtime: RuntimeView()
                    case .activity: ActivityView()
                    case .guide: GuideView()
                    case .settings: EmptyView()
                    }
                }.padding(.horizontal, 30).padding(.top, 35).padding(.bottom, 30)
                    .frame(maxWidth: 1350)
                    .frame(maxWidth: .infinity, alignment: .top)
            }.scrollIndicators(.hidden)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Palette.blue, Palette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 43, height: 43)
                    Image(systemName: "moon.stars.fill").font(.system(size: 23)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("月渡").font(.system(size: 21, weight: .bold))
                    Text("MOONBRIDGE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.0).foregroundStyle(Palette.muted)
                }
            }.padding(.top, 46).padding(.horizontal, 10).padding(.bottom, 37)
            Text("游戏与资料").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                .padding(.leading, 13).padding(.bottom, 12)
            nav(.library, icon: "square.grid.2x2.fill", badge: "\(model.document.games.count)")
            Button { model.chooseGame() } label: { navLabel("导入游戏", icon: "plus.app", active: false, badge: nil) }
                .buttonStyle(.plain).padding(.bottom, 5).disabled(model.operation)
            nav(.settings, icon: "sparkles", title: "AI 与资料设置")
            Rectangle().fill(Palette.line.opacity(0.8)).frame(height: 1).padding(.horizontal, 12).padding(.vertical, 19)
            Text("工具").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                .padding(.leading, 13).padding(.bottom, 12)
            nav(.runtime, icon: "shippingbox")
            nav(.activity, icon: "clock.arrow.circlepath")
            nav(.guide, icon: "book.closed")
            Spacer(minLength: 24)
            sidebarArtwork
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(model.runtime.wineReady && model.runtime.rosettaReady ? Palette.success : Palette.pink).frame(width: 6, height: 6)
                    Text(model.runtime.wineReady && model.runtime.rosettaReady ? "运行环境已就绪" : "查看运行环境")
                        .font(.system(size: 11, weight: .medium))
                }
                Text("游戏与存档保存在本机").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 13))
            HStack {
                Text("MOONBRIDGE").tracking(1.3)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1")
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted).padding(.top, 18).padding(.bottom, 22)
        }.padding(.horizontal, 15)
            .background(LinearGradient(colors: [Color(red: 0.92, green: 0.95, blue: 0.995), Color(red: 0.97, green: 0.94, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    private var sidebarArtwork: some View {
        BundledArtView(asset: "sidebar-eva-study.png")
            .frame(height: 139)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
            .padding(.bottom, 15).accessibilityHidden(true)
    }
    func nav(_ section: AppModel.Section, icon: String, badge: String? = nil, title: String? = nil) -> some View {
        Button {
            model.detailID = nil
            model.section = section
        } label: { navLabel(title ?? section.rawValue, icon: icon, active: model.section == section, badge: badge) }
            .buttonStyle(.plain).padding(.bottom, 5)
    }
    func navLabel(_ title: String, icon: String, active: Bool, badge: String?) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 15, weight: active ? .semibold : .regular)).frame(width: 20)
            Text(title).font(.system(size: 13, weight: active ? .semibold : .medium))
            Spacer(minLength: 3)
            if let badge {
                Text(badge).font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Palette.blue.opacity(0.10), in: Capsule())
            }
        }.foregroundStyle(active ? Palette.blue : Palette.muted)
            .padding(.horizontal, 13).padding(.vertical, 12)
            .background(active ? Color.white.opacity(0.94) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) { if active { Rectangle().fill(Palette.pink).frame(width: 2).padding(.vertical, 10) } }
            .contentShape(Rectangle())
    }
}

struct StatusBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            if model.operation { ProgressView().controlSize(.mini) }
            else { Image(systemName: model.running.isEmpty ? "checkmark.circle" : "play.circle.fill").foregroundStyle(Palette.blue) }
            Text(model.status).lineLimit(1)
            Spacer(minLength: 20)
            Label("本地游戏库", systemImage: "internaldrive").font(.system(size: 10))
            Rectangle().fill(Palette.line).frame(width: 1, height: 11).padding(.horizontal, 5)
            Text("AI 按需联网").font(.system(size: 10))
        }.font(.system(size: 10)).foregroundStyle(Palette.muted)
            .padding(.horizontal, 30).frame(height: 37).background(.white.opacity(0.8))
            .overlay(alignment: .top) { Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 1) }
    }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case added = "最近添加", played = "最近游玩", title = "游戏名称"
    var id: String { rawValue }
}
@MainActor private final class LibraryViewState: ObservableObject {
    @Published var sorting = LibrarySort.added
}
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var companion: CompanionModel
    @StateObject private var fields = LibraryViewState()
    private var filteredGames: [Game] {
        let term = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = model.document.games.filter { game in
            guard !term.isEmpty else { return true }
            let info = companion.metadata[game.id]
            return [game.title, game.engine, info?.title ?? "", info?.originalTitle ?? "", info?.developer ?? ""]
                .joined(separator: " ").localizedCaseInsensitiveContains(term)
        }
        return matches.sorted { left, right in
            switch fields.sorting {
            case .added: return left.importedAt > right.importedAt
            case .played: return (left.lastPlayedAt ?? .distantPast) > (right.lastPlayedAt ?? .distantPast)
            case .title: return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
        }
    }
    private var recentGame: Game? {
        model.document.games.filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 27) {
            header
            if model.document.games.isEmpty {
                LibraryArtworkBanner()
                DropCard()
                emptyGuide
            } else {
                if model.query.isEmpty { LibraryArtworkBanner() }
                if model.query.isEmpty, let game = recentGame {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("继续游玩", systemImage: "play.circle").font(.system(size: 15, weight: .semibold))
                        ContinueGameCard(game: game)
                    }
                }
                collection
                DropCard(compact: true)
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Rectangle().fill(Palette.pink).frame(width: 18, height: 3)
                        Text("LIBRARY").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
                    }
                    Text("游戏库").font(.system(size: 34, weight: .bold))
                }
                Spacer(minLength: 20)
                Button { model.chooseGame() } label: { Label("导入游戏", systemImage: "plus") }
                    .buttonStyle(PrimaryStyle()).disabled(model.operation)
            }
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Palette.muted)
                TextField("搜索游戏名称、原名或开发商", text: $model.query).textFieldStyle(.plain).font(.system(size: 13))
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted.opacity(0.7)) }
                        .buttonStyle(.plain).help("清除搜索").accessibilityLabel("清除搜索")
                }
                Text("⌘ O 导入").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.8))
            }.padding(.horizontal, 15).frame(height: 45)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        }
    }
    private var collection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Text(model.query.isEmpty ? "全部游戏" : "搜索结果").font(.system(size: 15, weight: .semibold))
                Text("\(filteredGames.count)").font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.muted).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Palette.line.opacity(0.45), in: Capsule())
                Spacer()
                Picker("排序", selection: $fields.sorting) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).fixedSize().font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            if filteredGames.isEmpty {
                Card {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: 27, weight: .light)).foregroundStyle(Palette.blue)
                        Text("没有找到匹配的游戏").font(.system(size: 14, weight: .semibold))
                        Text("试试中文名、日文原名或开发商名称。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Button("清除搜索") { model.query = "" }.buttonStyle(SoftStyle())
                    }.frame(maxWidth: .infinity).padding(.vertical, 26)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 345), spacing: 19)], spacing: 21) {
                    ForEach(filteredGames) { game in GameCard(game: game) }
                }
            }
        }
    }
    private var emptyGuide: some View {
        HStack(alignment: .top, spacing: 14) {
            GuideTile(number: "01", icon: "tray.and.arrow.down", title: "导入完整游戏", subtitle: "选择压缩包或游戏文件夹，\n自动解压并识别主程序。", tint: Palette.blue) { model.chooseGame() }
            GuideTile(number: "02", icon: "sparkles", title: "补全游戏资料", subtitle: "匹配封面与简介，\n建立本地游戏主页。", tint: Palette.pink) { model.section = .settings }
            GuideTile(number: "03", icon: "play.rectangle", title: "开始游玩", subtitle: "按游戏选择运行设置，\n验证中文、声音和存读档。", tint: Palette.lavender) { model.section = .guide }
        }
    }
}

struct LibraryArtworkBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                Text("本地收藏").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("\(model.document.games.count)").font(.system(size: 43, weight: .light, design: .monospaced))
                    Text("款游戏").font(.system(size: 13, weight: .medium))
                }
                Rectangle().fill(Palette.blue.opacity(0.30)).frame(width: 36, height: 1)
                Text("封面 · 简介 · 运行配置").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(.leading, 24).padding(.trailing, 20).frame(width: 205, alignment: .leading)
            Rectangle().fill(Palette.line).frame(width: 1).padding(.vertical, 21)
            BundledArtView(asset: "library-eva-panorama.png", alignment: .center)
                .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(height: 174).background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
}

struct ContinueGameCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var companion: CompanionModel
    let game: Game
    var body: some View {
        HStack(spacing: 23) {
            Button { model.detailID = game.id } label: {
                GameCoverArtwork(cover: game.coverPath ?? companion.metadata[game.id]?.coverPath, title: game.title, gameID: game.id)
                    .frame(width: 135, height: 128).clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).help("打开游戏主页")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(game.title).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                    if model.running.contains(game.id) { Tag(text: "运行中", tint: Palette.success) }
                }
                Text(companion.metadata[game.id]?.developer.isEmpty == false ? companion.metadata[game.id]!.developer : game.engine)
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                if let date = game.lastPlayedAt {
                    Text("上次游玩 · " + date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Button { model.detailID = game.id } label: { HStack(spacing: 5) { Text("游戏主页"); Image(systemName: "arrow.right").font(.system(size: 10)) } }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.blue)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { model.running.contains(game.id) ? model.stop(game) : model.launch(game) } label: {
                Label(model.running.contains(game.id) ? "停止运行" : "开始游戏", systemImage: model.running.contains(game.id) ? "stop.fill" : "play.fill")
            }.buttonStyle(PrimaryStyle()).disabled(model.operation || game.selectedExecutable.isEmpty || model.stopping.contains(game.id))
        }.padding(18).background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
}

struct HeroBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 13) {
                Text("导入与运行").font(.system(size: 22, weight: .bold))
                Text("导入完整游戏，整理资料，\n按游戏保存运行设置。").font(.system(size: 12)).lineSpacing(6).foregroundStyle(Palette.muted)
                Button { model.chooseGame() } label: { Label("选择游戏", systemImage: "folder.badge.plus") }
                    .buttonStyle(SoftStyle()).disabled(model.operation).padding(.top, 2)
            }.frame(width: 220, alignment: .leading)
            ArtView(alignment: .center, asset: "spring-bridge.png").frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(22).frame(height: 205).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }
}

struct DropCard: View {
    @EnvironmentObject var model: AppModel
    var compact = false
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: compact ? 23 : 29, weight: .light))
                .foregroundStyle(Palette.blue).frame(width: compact ? 42 : 55, height: compact ? 42 : 55)
                .background(Palette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(compact ? "拖入更多游戏" : "将游戏拖到窗口中").font(.system(size: compact ? 13 : 17, weight: .semibold))
                Text("ZIP · 7Z · RAR · 完整文件夹 · EXE").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Button("选择文件") { model.chooseGame() }.buttonStyle(SoftStyle()).disabled(model.operation)
        }.padding(compact ? 17 : 24).frame(maxWidth: .infinity)
            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
    }
}

struct GuideTile: View {
    let number: String; let icon: String; let title: String; let subtitle: String; let tint: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: icon).font(.system(size: 20, weight: .light)).foregroundStyle(tint)
                    Spacer()
                    Text(number).font(.system(size: 23, weight: .light, design: .rounded)).foregroundStyle(tint.opacity(0.5))
                }
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(subtitle).font(.system(size: 11)).lineSpacing(5).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(tint.opacity(0.15)))
        }.buttonStyle(.plain)
    }
}

@MainActor private final class GameCardState: ObservableObject {
    @Published var hovering = false
}
struct GameCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var companion: CompanionModel
    @StateObject private var fields = GameCardState()
    let game: Game
    private var info: GameMetadata? { companion.metadata[game.id] }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.detailID = game.id } label: {
                GameCoverArtwork(cover: game.coverPath ?? info?.coverPath, title: game.title, gameID: game.id)
                    .frame(height: 200)
                    .overlay(alignment: .topLeading) {
                        if model.running.contains(game.id) {
                            Label("运行中", systemImage: "waveform").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Palette.success.opacity(0.95), in: Capsule()).padding(11)
                        }
                    }
            }.buttonStyle(.plain).accessibilityLabel("打开「\(game.title)」游戏主页")
            VStack(alignment: .leading, spacing: 10) {
                Button { model.detailID = game.id } label: {
                    Text(game.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Text(info?.developer.isEmpty == false ? info!.developer : game.engine)
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                Rectangle().fill(Palette.line.opacity(0.65)).frame(height: 1).padding(.top, 3)
                HStack(spacing: 7) {
                    Text(model.running.contains(game.id) ? "游戏正在运行" : game.lastResult)
                        .font(.system(size: 10)).foregroundStyle(model.running.contains(game.id) ? Palette.success : Palette.muted).lineLimit(1)
                    Spacer(minLength: 2)
                    Button { model.detailID = game.id } label: { Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted).frame(width: 27, height: 29) }
                        .buttonStyle(.plain).help("游戏主页").accessibilityLabel("游戏主页")
                    Button { model.running.contains(game.id) ? model.stop(game) : model.launch(game) } label: {
                        Image(systemName: model.running.contains(game.id) ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold)).frame(width: 31, height: 29)
                            .foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                        .disabled(model.operation || game.selectedExecutable.isEmpty || model.stopping.contains(game.id))
                        .help(model.running.contains(game.id) ? "停止运行" : "开始游戏")
                        .accessibilityLabel(model.running.contains(game.id) ? "停止「\(game.title)」" : "启动「\(game.title)」")
                }
            }.padding(16)
        }.background(.white, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(fields.hovering ? Palette.blue.opacity(0.55) : Palette.line, lineWidth: 1))
            .shadow(color: Palette.blue.opacity(fields.hovering ? 0.12 : 0), radius: 8, y: 3)
            .onHover { fields.hovering = $0 }
            .contextMenu {
                Button("游戏主页") { model.detailID = game.id }
                Button("更换封面") { model.chooseCover(for: game) }
                Button("在 Finder 中显示") { model.revealContent(game) }
                Divider()
                Button("从游戏库隐藏（保留文件）") { model.hide(game) }.disabled(model.running.contains(game.id) || model.operation)
            }
    }
}
