import SwiftUI
import MoonBridgeCore

@MainActor private final class GameHomeFields: ObservableObject {
    @Published var tab = "概览"
    @Published var showRunSettings = false
    @Published var showEditor = false
    @Published var showClearConfirmation = false
    @Published var showMemory = false
    @Published var historyExpanded = false
    @Published var currentRoundStartID: UUID?
    @Published var question = ""
    @Published var allowSpoilers = false
}

struct GameHomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var companion: CompanionModel
    let gameID: UUID
    @StateObject private var fields = GameHomeFields()

    private var info: GameMetadata? { companion.metadata[gameID] }
    private var messages: [ChatMessage] { companion.messages }
    private var answering: Bool { companion.isAnswering }
    private var currentRoundIndex: Int? {
        fields.currentRoundStartID.flatMap { id in messages.firstIndex { $0.id == id } }
    }
    private var historicalMessages: [ChatMessage] {
        currentRoundIndex.map { Array(messages.prefix($0)) } ?? messages
    }
    private var currentRound: [ChatMessage] {
        currentRoundIndex.map { Array(messages.dropFirst($0)) } ?? []
    }

    var body: some View {
        Group {
            if let game = model.game(gameID) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 25) {
                            navigation(game)
                            hero(game)
                            HStack {
                                Picker("游戏页面", selection: $fields.tab) {
                                    Text("概览").tag("概览")
                                    Text("和千咲聊聊").tag("AI 问答")
                                }.pickerStyle(.segmented).frame(width: 250)
                                Spacer()
                                Label("资料保存在本机", systemImage: "internaldrive")
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                            if let notice = companion.aiNotice {
                                CompanionNotice(text: notice) { companion.aiNotice = nil }
                            }
                            if fields.tab == "概览" { overview(game) }
                            else { chatContent(game) }
                            Color.clear.frame(height: 1).id("home-bottom")
                        }.padding(30).frame(maxWidth: 1120).frame(maxWidth: .infinity)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if fields.tab == "AI 问答" { withAnimation { proxy.scrollTo("home-bottom", anchor: .bottom) } }
                    }
                }
                .sheet(isPresented: $fields.showRunSettings) {
                    GameDetailView(gameID: game.id).environmentObject(model)
                }
                .sheet(isPresented: $fields.showEditor) {
                    MetadataEditor(game: game, metadata: info)
                        .environmentObject(companion)
                }
                .sheet(isPresented: $companion.showLookup) {
                    GameLookupSheet(game: game).environmentObject(companion)
                }
                .sheet(isPresented: $fields.showMemory) { MemoryPanelView().environmentObject(companion) }
            } else {
                ContentUnavailableView("找不到这款游戏", systemImage: "book.closed", description: Text("返回游戏库，重新选择一款游戏。"))
            }
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.wash)
        .onAppear { companion.refreshCredentialStatus() }
        .confirmationDialog("清空所有游戏共享的问答历史？", isPresented: $fields.showClearConfirmation) {
            Button("清空共享历史", role: .destructive) {
                companion.clearHistory()
                fields.currentRoundStartID = nil
                fields.historyExpanded = false
            }
            Button("取消", role: .cancel) { }
        } message: { Text("所有游戏页面共用同一份问答历史。独立的长期记忆条目会保留，游戏文件和存档不受影响。") }
    }

    private func navigation(_ game: Game) -> some View {
        HStack(spacing: 12) {
            Button { model.detailID = nil } label: { Label("游戏库", systemImage: "chevron.left") }
                .buttonStyle(.plain).font(.system(size: 13, weight: .medium))
                .accessibilityIdentifier("home-back")
            Text("/").foregroundStyle(Palette.line)
            Text(game.title).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
            Spacer()
            ChisaIdentity(size: 35)
            Button { fields.showMemory = true } label: { Image(systemName: "brain.head.profile") }
                .buttonStyle(SoftStyle()).help("管理共享记忆").accessibilityLabel("管理共享记忆")
            Button { fields.showRunSettings = true } label: { Label("运行设置", systemImage: "slider.horizontal.3") }
                .buttonStyle(SoftStyle()).accessibilityIdentifier("home-settings")
        }
    }

    private func hero(_ game: Game) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 9) {
                GameCoverArtwork(cover: game.coverPath ?? info?.coverPath, title: game.title, gameID: game.id)
                    .frame(width: 188, height: 258).clipShape(RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.8), lineWidth: 2))
                    .shadow(color: Palette.ink.opacity(0.13), radius: 15, y: 8)
                Button("更换本地封面") { model.chooseCover(for: game) }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Tag(text: model.running.contains(gameID) ? "正在运行" : "本地游戏")
                    if let architecture = game.selected?.architecture { Tag(text: architecture, tint: Palette.pink) }
                }
                Text(game.title).font(.system(size: 29, weight: .bold)).textSelection(.enabled)
                    .accessibilityIdentifier("home-game-title")
                if let original = info?.originalTitle, !original.isEmpty, original != game.title {
                    Text(original).font(.system(size: 13)).foregroundStyle(Palette.muted).textSelection(.enabled)
                } else if let title = info?.title, !title.isEmpty, title != game.title {
                    Text(title).font(.system(size: 13)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
                HStack(spacing: 24) {
                    detailValue("开发商", value: info?.developer)
                    detailValue("发行日期", value: info?.releaseDate)
                }
                if let tags = info?.tags, !tags.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { ForEach(Array(tags.prefix(5).enumerated()), id: \.offset) { _, tag in Tag(text: tag) } }
                        HStack(spacing: 6) { ForEach(Array(tags.prefix(3).enumerated()), id: \.offset) { _, tag in Tag(text: tag) } }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    if model.running.contains(gameID) {
                        Button { model.stop(game) } label: { Label("停止运行", systemImage: "stop.fill") }
                            .buttonStyle(SoftStyle(pink: true)).disabled(model.stopping.contains(gameID))
                    } else {
                        Button { model.launch(game) } label: { Label("开始游戏", systemImage: "play.fill") }
                            .buttonStyle(PrimaryStyle()).disabled(model.operation || game.selectedExecutable.isEmpty)
                            .accessibilityIdentifier("home-play")
                    }
                    Button { companion.presentLookup(for: game) } label: { Label("匹配资料", systemImage: "sparkle.magnifyingglass") }
                        .buttonStyle(SoftStyle()).disabled(!companion.settings.enabled || companion.savingMetadata.contains(gameID))
                        .accessibilityIdentifier("home-match")
                    if companion.savingMetadata.contains(gameID) { ProgressView().controlSize(.small) }
                }
                Text(game.lastPlayedAt.map { "上次游玩 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "尚未记录游玩时间")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, minHeight: 258, alignment: .topLeading)
        }.padding(26)
            .background(LinearGradient(colors: [.white, Palette.blue.opacity(0.065), Palette.pink.opacity(0.065)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(Palette.line.opacity(0.75), lineWidth: 1))
    }

    private func detailValue(_ label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.muted)
            Text(value?.isEmpty == false ? value! : "待补充").font(.system(size: 12, weight: .medium)).lineLimit(2)
        }
    }

    private func overview(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Card {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Label("作品介绍", systemImage: "text.book.closed").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Button { companion.regenerateOverview(gameID: gameID) } label: {
                            HStack(spacing: 6) {
                                if companion.savingMetadata.contains(gameID) { ProgressView().controlSize(.small) }
                                Text(companion.savingMetadata.contains(gameID) ? "正在整理…" : "整理中文概况")
                            }
                        }.buttonStyle(.plain).foregroundStyle(Palette.blue).font(.system(size: 12))
                            .disabled(info == nil || !companion.settings.enabled || !companion.keyReady || companion.savingMetadata.contains(gameID))
                            .accessibilityIdentifier("overview-organize")
                        Button("编辑资料") { fields.showEditor = true }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                            .font(.system(size: 12)).disabled(companion.savingMetadata.contains(gameID))
                    }
                    if let summary = info?.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if info?.summaryOrigin == "ai" || info?.summaryOrigin == "manual" {
                            Tag(text: info?.summaryOrigin == "ai" ? "AI 整理" : "手动编辑",
                                tint: info?.summaryOrigin == "ai" ? Palette.pink : Palette.blue)
                            Text(summary).font(.system(size: 13)).lineSpacing(7).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("中文概况待整理").font(.system(size: 14, weight: .medium))
                                Text("来源资料已保存。点击“整理中文概况”，让千咲依据资料重新组织介绍。")
                                    .font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.muted)
                            }.padding(.vertical, 7)
                        }
                        let original = info?.originalSummary ?? summary
                        if !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           original != summary || (info?.summaryOrigin != "ai" && info?.summaryOrigin != "manual") {
                            DisclosureGroup {
                                Text(original).font(.system(size: 12)).lineSpacing(6).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 9)
                            } label: {
                                Text("查看来源原文").font(.system(size: 11)).foregroundStyle(Palette.blue)
                            }.tint(Palette.blue)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("还没有这款游戏的介绍").font(.system(size: 14, weight: .medium))
                            Text("匹配公开资料以获取封面和简介，或手动填写。暂时不添加资料也可以直接运行游戏。")
                                .font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.muted)
                        }.padding(.vertical, 10)
                    }
                    if let info, let url = companionURL(info.sourceURL) {
                        Divider().overlay(Palette.line)
                        HStack {
                            Link(destination: url) { Label("查看资料来源 · " + (url.host ?? "网页"), systemImage: "arrow.up.right.square") }
                                .font(.system(size: 11)).foregroundStyle(Palette.blue)
                            Spacer()
                            Text("缓存于 " + info.fetchedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 13) {
                Button { model.revealContent(game) } label: { Label("游戏文件", systemImage: "folder") }.buttonStyle(SoftStyle())
                Button { model.revealSaves(game) } label: { Label("存档环境", systemImage: "externaldrive") }.buttonStyle(SoftStyle())
                Button { model.showLog(for: game) } label: { Label("运行日志", systemImage: "doc.text") }.buttonStyle(SoftStyle())
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: game.sizeBytes, countStyle: .file))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            if !companion.settings.enabled {
                HStack {
                    Text("联网资料与 AI 功能已关闭，已缓存的资料仍可查看。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("AI 设置") { model.section = .settings }.buttonStyle(.plain).foregroundStyle(Palette.blue)
                }
            }
        }
    }

    private func chatContent(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("和千咲聊聊这款游戏").font(.system(size: 17, weight: .semibold))
                    Text(companion.settings.webSearch ? "结合已保存资料与联网检索回答，来源会显示在回复下方。" : "联网搜索已关闭；回答可能受限于已保存资料和模型已有知识。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text("所有游戏共享聊天与长期记忆，切换游戏后也能接着聊。")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("管理记忆") { fields.showMemory = true }.buttonStyle(SoftStyle())
                if !messages.isEmpty {
                    Button("清空历史") { fields.showClearConfirmation = true }.buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).disabled(answering)
                }
            }
            if !companion.settings.enabled || !companion.keyReady {
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "key.horizontal").font(.system(size: 23)).foregroundStyle(Palette.blue)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(!companion.settings.enabled ? "AI 功能已关闭" : "先连接你的 AI 服务").font(.system(size: 13, weight: .semibold))
                            Text("在 AI 设置中保存 API Key 后即可提问。游戏仍可离线启动。")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("打开 AI 设置") { model.section = .settings }.buttonStyle(SoftStyle())
                    }
                }
            }
            if messages.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    ChisaAvatar(size: 46)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("可以问作品背景、人物关系或游玩顺序").font(.system(size: 13, weight: .medium))
                        HStack(spacing: 8) {
                            promptButton("无剧透介绍一下这款游戏")
                            promptButton("这款游戏有哪些相关作品？")
                        }
                        Text("千咲无法直接看到游戏画面或存档；重要信息请核对来源。")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            }
            if !historicalMessages.isEmpty {
                DisclosureGroup(isExpanded: $fields.historyExpanded) {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(historicalMessages) { message in ChatBubble(message: message) }
                    }.padding(.top, 14)
                } label: {
                    Label("共享聊天历史 · \(historicalMessages.count) 条", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                }.tint(Palette.blue).padding(16)
                    .background(Palette.blue.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            }
            if !currentRound.isEmpty {
                Text("本轮对话").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                ForEach(currentRound) { message in ChatBubble(message: message) }
            }
            if answering {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(companion.settings.webSearch ? "正在查找资料并整理回答…" : "正在整理回答…")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("停止回答") { companion.cancelChat(gameID: gameID) }.buttonStyle(SoftStyle())
                }.padding(15)
            }
            composer(game)
        }
    }

    private func promptButton(_ text: String) -> some View {
        Button(text) { fields.question = text }.buttonStyle(SoftStyle())
    }

    private func composer(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if fields.question.isEmpty {
                    Text("输入关于「\(game.title)」的问题…")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.horizontal, 7).padding(.top, 9)
                }
                TextEditor(text: $fields.question).font(.system(size: 13)).scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 130).padding(3)
                    .accessibilityLabel("游戏问题").accessibilityIdentifier("chat-question")
            }.background(Palette.wash, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Toggle("允许剧透", isOn: $fields.allowSpoilers).toggleStyle(.checkbox)
                    .font(.system(size: 11)).help("默认关闭。若允许剧透，回复可能涉及结局与关键剧情。")
                Spacer()
                Text("⌘ ↵ 发送").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Button {
                    let value = fields.question.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    let previousIDs = Set(companion.messages.map(\.id))
                    companion.send(value, for: game, allowSpoilers: fields.allowSpoilers)
                    if let latest = companion.messages.last(where: { $0.role == "user" && !previousIDs.contains($0.id) }) {
                        fields.currentRoundStartID = latest.id
                        fields.historyExpanded = false
                        fields.question = ""
                    }
                } label: { Label("发送", systemImage: "arrow.up") }
                    .buttonStyle(PrimaryStyle()).keyboardShortcut(.return, modifiers: .command)
                    .disabled(answering || !companion.settings.enabled || !companion.keyReady || fields.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.question.count > 4000)
                    .accessibilityIdentifier("chat-send")
            }
            Text("仅提交游戏名称、资料摘要、近期对话和相关记忆片段；游戏文件与存档保留在本机。")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
            if fields.question.count > 4000 { Text("问题最多 4,000 个字符。").font(.system(size: 11)).foregroundStyle(Palette.pink) }
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }
    private var formattedText: AttributedString {
        var value = (try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text)
        let disallowedLinks = value.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let link = run.link, companionURL(link.absoluteString) == nil else { return nil }
            return run.range
        }
        for range in disallowedLinks { value[range].link = nil }
        return value
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Image(systemName: "person.crop.circle").font(.system(size: 16)).foregroundStyle(Palette.pink)
                    .frame(width: 30, height: 30).background(Palette.pink.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            } else { ChisaAvatar(size: 30) }
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text(isUser ? "你" : "千咲").font(.system(size: 11, weight: .semibold))
                    if let title = message.gameTitle, !title.isEmpty {
                        Text(title).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer()
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
                Text(formattedText).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).tint(Palette.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !message.sources.isEmpty {
                    Divider().overlay(Palette.line)
                    Text("参考来源").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
                    ForEach(message.sources) { source in
                        if let url = companionURL(source.url) {
                            Link(destination: url) { Label(source.title.isEmpty ? (url.host ?? "来源网页") : source.title, systemImage: "arrow.up.right.square") }
                                .font(.system(size: 11)).foregroundStyle(Palette.blue).lineLimit(2)
                        }
                    }
                }
            }
        }.padding(19).background(isUser ? Palette.pink.opacity(0.045) : Color.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line.opacity(0.7), lineWidth: 1))
    }
}

struct CompanionNotice: View {
    let text: String
    var dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Palette.blue)
            Text(text).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
            Spacer(minLength: 8)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
                .accessibilityLabel("关闭提示")
        }.padding(15).background(Palette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct GameLookupSheet: View {
    @EnvironmentObject var companion: CompanionModel
    @Environment(\.dismiss) var dismiss
    let game: Game
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("匹配游戏资料").font(.system(size: 23, weight: .bold))
                    Text("查找真实作品条目，确认后保存封面和简介到本机。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(SoftStyle()).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 10) {
                TextField("中文、日文或英文游戏名", text: $companion.lookupQuery)
                    .textFieldStyle(.roundedBorder).onSubmit { companion.search(companion.lookupQuery) }
                    .accessibilityIdentifier("metadata-query")
                Button { companion.search(companion.lookupQuery) } label: { Label("搜索", systemImage: "magnifyingglass") }
                    .buttonStyle(PrimaryStyle()).disabled(companion.lookupQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = companion.lookupError {
                Text(error).font(.system(size: 12)).lineSpacing(5).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if companion.lookupBusy {
                        HStack { ProgressView().controlSize(.small); Text("正在检索作品资料…").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                            .frame(maxWidth: .infinity).padding(40)
                    }
                    ForEach(companion.candidates) { candidate in candidateRow(candidate) }
                    if !companion.lookupBusy && companion.candidates.isEmpty && companion.lookupError == nil {
                        Text("输入名称后搜索。可以尝试去掉汉化组、版本号等附加文字。")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.vertical, 35)
                    }
                }.padding(.trailing, 4)
            }.frame(minHeight: 270)
            Text("资料来自公开数据库；本篇、续作与追加内容可能是不同条目，请核对名称和发行信息。")
                .font(.system(size: 10)).lineSpacing(4).foregroundStyle(Palette.muted)
        }.padding(27).frame(width: 710, height: 610).background(Palette.wash).foregroundStyle(Palette.ink)
    }
    private func candidateRow(_ candidate: GameMetadata) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.title).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                    if !candidate.originalTitle.isEmpty, candidate.originalTitle != candidate.title {
                        Text(candidate.originalTitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Text([candidate.developer, candidate.releaseDate].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 12)
                Button("使用这项资料") { companion.apply(candidate, to: game) }.buttonStyle(SoftStyle())
                    .disabled(companion.savingMetadata.contains(game.id))
            }
            if !candidate.summary.isEmpty {
                Text(candidate.summary).font(.system(size: 11)).lineSpacing(4).lineLimit(4).foregroundStyle(Palette.muted)
            }
            if let url = companionURL(candidate.sourceURL) {
                Link("查看来源 · " + (url.host ?? candidate.id), destination: url)
                    .font(.system(size: 10)).foregroundStyle(Palette.blue)
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line, lineWidth: 1))
    }
}

@MainActor private final class MetadataEditorFields: ObservableObject {
    @Published var draft: GameMetadata
    @Published var tags: String
    init(metadata: GameMetadata) {
        draft = metadata
        tags = metadata.tags.joined(separator: "，")
    }
}

private struct MetadataEditor: View {
    @EnvironmentObject var companion: CompanionModel
    @Environment(\.dismiss) var dismiss
    let game: Game
    @StateObject private var fields: MetadataEditorFields
    init(game: Game, metadata: GameMetadata?) {
        self.game = game
        var value = metadata ?? GameMetadata()
        if value.title.isEmpty { value.title = game.title }
        if value.id.isEmpty { value.id = "local-" + game.id.uuidString }
        _fields = StateObject(wrappedValue: MetadataEditorFields(metadata: value))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("编辑本地资料").font(.system(size: 23, weight: .bold))
            Text("资料独立保存，不会改变游戏主程序、语言设置或存档。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            Form {
                TextField("资料标题", text: $fields.draft.title)
                TextField("日文 / 原文名称", text: $fields.draft.originalTitle)
                TextField("开发商", text: $fields.draft.developer)
                TextField("发行日期", text: $fields.draft.releaseDate)
                TextField("标签（逗号分隔）", text: $fields.tags)
                TextField("资料来源网址", text: $fields.draft.sourceURL)
                VStack(alignment: .leading, spacing: 8) {
                    Text("作品介绍").font(.system(size: 12, weight: .medium))
                    TextEditor(text: $fields.draft.summary).font(.system(size: 12)).frame(height: 165)
                        .padding(7).background(Palette.wash, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
                }
            }.formStyle(.columns).textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { dismiss() }.buttonStyle(SoftStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存资料") {
                    fields.draft.tags = fields.tags.components(separatedBy: CharacterSet(charactersIn: ",，、\n"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    fields.draft.fetchedAt = Date()
                    companion.saveManualMetadata(fields.draft, gameID: game.id)
                    dismiss()
                }.buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 640).background(.white).foregroundStyle(Palette.ink)
    }
}

func companionURL(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil,
          url.user == nil, url.password == nil else { return nil }
    return url
}
