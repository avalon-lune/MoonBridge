import SwiftUI
import UniformTypeIdentifiers
import MoonBridgeCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var detailPresented: Binding<Bool> { Binding(get: { model.detailID != nil }, set: { if !$0 { model.detailID = nil } }) }
    var errorPresented: Binding<Bool> { Binding(get: { model.error != nil && model.detailID == nil }, set: { if !$0 { model.error = nil } }) }
    var noticePresented: Binding<Bool> { Binding(get: { model.notice != nil && model.detailID == nil }, set: { if !$0 { model.notice = nil } }) }
    var rootLogPresented: Binding<Bool> { Binding(get: { model.showLog && model.detailID == nil }, set: { if !$0 { model.showLog = false } }) }
    var body: some View {
        HStack(spacing: 0) {
            SidebarView().frame(width: 214)
            Rectangle().fill(Palette.line.opacity(0.7)).frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        switch model.section {
                        case .library: LibraryView()
                        case .runtime: RuntimeView()
                        case .activity: ActivityView()
                        case .guide: GuideView()
                        }
                    }.padding(.horizontal, 32).padding(.top, 37).padding(.bottom, 24)
                }
                StatusBar()
            }
            .background(LinearGradient(colors: [Color(red: 0.975, green: 0.985, blue: 1), Color(red: 0.99, green: 0.975, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .foregroundStyle(Palette.ink)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $model.dragActive, perform: model.handleDrop)
        .overlay { if model.dragActive { RoundedRectangle(cornerRadius: 20).stroke(Palette.blue, style: StrokeStyle(lineWidth: 3, dash: [10, 7])).padding(10).allowsHitTesting(false) } }
        .sheet(isPresented: $model.showImport) { ImportSheet().environmentObject(model) }
        .sheet(isPresented: detailPresented) { if let id = model.detailID { GameDetailView(gameID: id).environmentObject(model) } }
        .sheet(isPresented: rootLogPresented) { LogView().environmentObject(model) }
        .alert("操作未完成", isPresented: errorPresented) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
        .alert("MoonBridge", isPresented: noticePresented) { Button("好的") { model.notice = nil } } message: { Text(model.notice ?? "") }
    }
}
struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Palette.blue.opacity(0.85), Palette.pink.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 43, height: 43)
                    Image(systemName: "moon.stars.fill").font(.system(size: 23)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("MoonBridge").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("月渡  /  故事的另一岸").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
            }.padding(.top, 47).padding(.bottom, 38)
            Text("你的空间").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted).padding(.leading, 13).padding(.bottom, 13)
            nav(.library, icon: "square.grid.2x2.fill", badge: "\(model.document.games.count)")
            Button { model.chooseGame() } label: { navLabel("导入新故事", icon: "plus.app", active: false, badge: nil) }.buttonStyle(.plain).padding(.bottom, 6).disabled(model.operation)
            nav(.runtime, icon: "sparkles.rectangle.stack")
            nav(.activity, icon: "clock.arrow.circlepath")
            nav(.guide, icon: "book.closed")
            Spacer(minLength: 22)
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: "sparkles").foregroundStyle(Palette.pink); Text("小小的桥，很远的故事").font(.system(size: 11, weight: .semibold)) }
                Text("让收藏里的那些世界，\n在你的 Mac 上慢慢展开。").font(.system(size: 10)).lineSpacing(5).foregroundStyle(Palette.muted)
                HStack(spacing: 6) {
                    Circle().fill(model.runtime.wineReady ? Color.green.opacity(0.7) : Palette.pink).frame(width: 5, height: 5)
                    Text(model.runtime.wineReady ? "本地运行环境已就绪" : "正在检查运行环境").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.white.opacity(0.8), Palette.pink.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white, lineWidth: 1))
            HStack { Text("MOONBRIDGE").tracking(1.8); Spacer(); Text("v0.1.1") }.font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted.opacity(0.8)).padding(.top, 20).padding(.bottom, 23)
        }
        .padding(.horizontal, 16)
        .background(LinearGradient(colors: [Color(red: 0.91, green: 0.95, blue: 0.995), Color(red: 0.97, green: 0.94, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    func nav(_ section: AppModel.Section, icon: String, badge: String? = nil) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { model.section = section } } label: { navLabel(section.rawValue, icon: icon, active: model.section == section, badge: badge) }.buttonStyle(.plain).padding(.bottom, 6)
    }
    func navLabel(_ title: String, icon: String, active: Bool, badge: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: active ? .semibold : .regular)).frame(width: 19)
            Text(title).font(.system(size: 12, weight: active ? .semibold : .regular))
            Spacer()
            if let badge { Text(badge).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 3).background(Palette.blue.opacity(0.12), in: Capsule()) }
        }.foregroundStyle(active ? Palette.blue : Palette.muted).padding(.horizontal, 13).padding(.vertical, 13)
            .background(active ? .white.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Palette.blue.opacity(active ? 0.07 : 0), radius: 9, y: 3)
            .contentShape(Rectangle())
    }
}
struct StatusBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            if model.operation { ProgressView().controlSize(.mini).scaleEffect(0.75) }
            else { Image(systemName: model.running.isEmpty ? "moon.zzz" : "play.circle.fill").foregroundStyle(Palette.blue) }
            Text(model.status).lineLimit(1)
            Spacer()
            Text("APPLE SILICON").tracking(1.2).font(.system(size: 8, weight: .semibold))
            Circle().fill(Palette.pink.opacity(0.7)).frame(width: 3, height: 3)
            Text("LOCAL FIRST").tracking(1.2).font(.system(size: 8, weight: .semibold))
        }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 32).frame(height: 36).background(.white.opacity(0.65))
    }
}
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(alignment: .center) {
                SectionTitle(eyebrow: "YOUR LITTLE STORY ROOM", title: "你的故事收藏室", subtitle: "把喜欢的世界，留在触手可及的地方。")
                Spacer()
                HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted); TextField("寻找一个故事…", text: $model.query).textFieldStyle(.plain) }
                    .font(.system(size: 11)).padding(11).frame(width: 170).background(.white, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line.opacity(0.8)))
                Button { model.chooseGame() } label: { Label("导入游戏", systemImage: "plus") }.buttonStyle(PrimaryStyle()).disabled(model.operation)
            }
            HeroBanner()
            HStack(spacing: 18) {
                Label("\(model.document.games.count) 个故事", systemImage: "square.stack.3d.up").foregroundStyle(Palette.ink)
                Rectangle().fill(Palette.line).frame(width: 1, height: 13)
                Label("每款游戏独立配置", systemImage: "shippingbox").foregroundStyle(Palette.muted)
                Spacer()
                Text("ZIP · 7Z · RAR · 文件夹 · EXE").tracking(0.8).foregroundStyle(Palette.muted)
            }.font(.system(size: 10))
            if model.document.games.isEmpty {
                DropCard()
                HStack { Text("从这里，开始一段新故事").font(.system(size: 14, weight: .semibold)); Spacer(); Text("A LITTLE GUIDE").tracking(1.7).font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted) }.padding(.top, 1)
                HStack(spacing: 15) {
                    GuideTile(number: "01", icon: "tray.and.arrow.down", title: "带上你的游戏", subtitle: "拖入完整游戏包，\n自动解压并寻找主程序。", tint: Palette.blue) { model.chooseGame() }
                    GuideTile(number: "02", icon: "wand.and.stars", title: "准备恰好的环境", subtitle: "按游戏保存语言与显示配置，\n独立汉化包也可以稍后应用。", tint: Palette.pink) { model.section = .runtime }
                    GuideTile(number: "03", icon: "play.rectangle", title: "从序章开始", subtitle: "检查文字、语音与视频，\n再存一个属于你的进度。", tint: Color(red: 0.59, green: 0.55, blue: 0.76)) { model.section = .guide }
                }
            } else {
                HStack { Text("全部故事").font(.system(size: 15, weight: .semibold)); Spacer(); Button("拖入或选择更多游戏") { model.chooseGame() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.blue) }
                if model.games.isEmpty { Card { Text("还没有找到这个故事，试试别的名字。").foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(25) } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245, maximum: 380), spacing: 18)], spacing: 18) { ForEach(model.games) { game in GameCard(game: game) } }
                DropCard(compact: true)
            }
        }
    }
}
struct HeroBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack(alignment: .leading) {
            ArtView(alignment: .top)
            LinearGradient(stops: [.init(color: .white.opacity(0.85), location: 0), .init(color: .white.opacity(0.62), location: 0.28), .init(color: .white.opacity(0.02), location: 0.53)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 6) { Image(systemName: "sparkle"); Text("CROSS THE BRIDGE, INTO A STORY").tracking(1.1) }.font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.blue)
                Text("把喜欢的故事，\n带到 Mac 上。").font(.system(size: 30, weight: .bold)).lineSpacing(7).foregroundStyle(Palette.ink)
                Text("一座小小的桥，连接你的收藏与下一次心动。").font(.system(size: 10)).foregroundStyle(Palette.ink.opacity(0.7)).padding(.top, 2)
                Button { model.chooseGame() } label: { HStack(spacing: 8) { Text("迎接下一段故事"); Image(systemName: "arrow.right") } }.buttonStyle(SoftStyle()).padding(.top, 4).disabled(model.operation)
            }.padding(.leading, 28)
        }.frame(height: 259).clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: Palette.blue.opacity(0.1), radius: 18, y: 7)
    }
}
struct DropCard: View {
    @EnvironmentObject var model: AppModel
    var compact = false
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Palette.blue.opacity(0.14), Palette.pink.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: compact ? 42 : 58, height: compact ? 42 : 58)
                Image(systemName: "folder.badge.plus").font(.system(size: compact ? 20 : 27, weight: .light)).foregroundStyle(Palette.blue)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(compact ? "还有故事想带过来？拖到这里就好。" : "拖入游戏，开启下一段故事").font(.system(size: compact ? 12 : 16, weight: .semibold))
                Text(compact ? "支持压缩包、完整游戏文件夹及 EXE。" : "选择压缩包或完整游戏文件夹；独立汉化补丁可在导入后应用。").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Button { model.chooseGame() } label: { Label(compact ? "选择文件" : "选择游戏文件", systemImage: "plus") }.buttonStyle(SoftStyle()).disabled(model.operation)
        }.padding(compact ? 18 : 24).frame(maxWidth: .infinity)
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.blue.opacity(0.37), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
    }
}
struct GuideTile: View {
    let number: String; let icon: String; let title: String; let subtitle: String; let tint: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack { Image(systemName: icon).font(.system(size: 19, weight: .light)).foregroundStyle(tint); Spacer(); Text(number).font(.system(size: 23, weight: .ultraLight, design: .rounded)).foregroundStyle(tint.opacity(0.45)) }
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                HStack(alignment: .bottom) { Text(subtitle).font(.system(size: 10)).lineSpacing(4).foregroundStyle(Palette.muted); Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(tint) }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.14)))
        }.buttonStyle(.plain)
    }
}
struct GameCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.detailID = game.id } label: {
                ArtView(cover: game.coverPath, alignment: .trailing).frame(height: 135).overlay(alignment: .topLeading) { Tag(text: game.selected?.architecture ?? "待识别").padding(11) }
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 11) {
                Text(game.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(game.engine).font(.system(size: 10)).foregroundStyle(Palette.muted)
                HStack {
                    Text(model.running.contains(game.id) ? "运行中" : game.lastResult).font(.system(size: 9)).foregroundStyle(model.running.contains(game.id) ? Palette.blue : Palette.muted).lineLimit(1)
                    Spacer()
                    Button { model.detailID = game.id } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    Button { model.running.contains(game.id) ? model.stop(game) : model.launch(game) } label: { Image(systemName: model.running.contains(game.id) ? "stop.fill" : "play.fill").font(.system(size: 11)).frame(width: 29, height: 27).foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).disabled(model.operation || game.selectedExecutable.isEmpty)
                }
            }.padding(15)
        }.background(.white, in: RoundedRectangle(cornerRadius: 15)).clipShape(RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line.opacity(0.6)))
            .contextMenu { Button("游戏设置") { model.detailID = game.id }; Button("更换封面") { model.chooseCover(for: game) }; Button("在 Finder 中显示") { model.revealContent(game) }; Divider(); Button("从游戏库隐藏（保留文件）") { model.hide(game) }.disabled(model.running.contains(game.id) || model.operation) }
    }
}
