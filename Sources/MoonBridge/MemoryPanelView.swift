import SwiftUI
import AppKit
import MoonBridgeCore

struct ChisaAvatar: View {
    @EnvironmentObject var model: AppModel
    var size: CGFloat = 38

    private var image: NSImage? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Art/chisa-avatar.png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(contentsOf: model.paths.root.appendingPathComponent("Resources/Art/chisa-avatar.png"))
    }

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else {
                ZStack {
                    LinearGradient(colors: [Palette.blue.opacity(0.15), Palette.pink.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "person.crop.circle").font(.system(size: size * 0.67, weight: .light)).foregroundStyle(Palette.blue)
                }
            }
        }.frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.95), lineWidth: 1.5))
            .accessibilityLabel("千咲头像")
    }
}

struct ChisaIdentity: View {
    var size: CGFloat = 38
    var body: some View {
        HStack(spacing: 9) {
            ChisaAvatar(size: size)
            VStack(alignment: .leading, spacing: 4) {
                Text("千咲").font(.system(size: 12, weight: .semibold))
                Text("游戏库管理员").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
        }.foregroundStyle(Palette.ink)
    }
}

@MainActor private final class MemoryPanelFields: ObservableObject {
    @Published var noteText = ""
    @Published var query = ""
    @Published var didSearch = false
    @Published var showDeleteConfirmation = false
    @Published var pendingDelete: UUID?
    @Published var showClearConfirmation = false
}

struct MemoryPanelView: View {
    @EnvironmentObject var companion: CompanionModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var fields = MemoryPanelFields()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                ChisaIdentity(size: 43)
                Divider().frame(height: 34).overlay(Palette.line)
                VStack(alignment: .leading, spacing: 5) {
                    Text("共享记忆").font(.system(size: 21, weight: .bold))
                    Text("各款游戏共用，本地保存与管理。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(SoftStyle()).keyboardShortcut(.cancelAction)
            }.padding(25)
            Divider().overlay(Palette.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let status = companion.memoryStatus {
                        CompanionNotice(text: status) { companion.memoryStatus = nil }
                    }
                    localStorageNote
                    lastingNotes
                    historySearch
                    HStack {
                        Text("清空聊天历史会保留上方的长期记忆条目。")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Spacer()
                        Button("清空共享聊天历史…") { fields.showClearConfirmation = true }
                            .buttonStyle(SoftStyle(pink: true)).disabled(companion.isAnswering)
                    }
                }.padding(25)
            }
        }.frame(width: 790, height: 710).background(Palette.wash).foregroundStyle(Palette.ink)
            .alert("删除这条长期记忆？", isPresented: $fields.showDeleteConfirmation) {
                Button("取消", role: .cancel) { fields.pendingDelete = nil }
                Button("删除记忆", role: .destructive) {
                    if let id = fields.pendingDelete { companion.deleteMemory(id: id) }
                    fields.pendingDelete = nil
                }
            } message: { Text("这条记忆会从所有游戏共用的记忆列表中移除，聊天原文仍然保留。") }
            .confirmationDialog("清空所有游戏共享的聊天历史？", isPresented: $fields.showClearConfirmation) {
                Button("清空共享历史", role: .destructive) { companion.clearHistory() }
                Button("取消", role: .cancel) { }
            } message: { Text("本机聊天原文和历史检索结果会被清空。长期记忆条目、游戏文件和存档保持不变。") }
    }

    private var localStorageNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "internaldrive").font(.system(size: 20, weight: .light)).foregroundStyle(Palette.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("共享的本地资料库").font(.system(size: 13, weight: .semibold))
                Text("管理与搜索在本机完成，不会上传整个数据库。聊天时，相关记忆片段会作为上下文随问题提交给模型。")
                    .font(.system(size: 11)).lineSpacing(5).foregroundStyle(Palette.muted)
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private var lastingNotes: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("长期记忆", systemImage: "bookmark").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(companion.memoryNotes.count) 条").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Text("保存你希望千咲持续记住的偏好或信息，例如喜欢的题材、称呼和游玩习惯。")
                    .font(.system(size: 11)).lineSpacing(5).foregroundStyle(Palette.muted)
                ZStack(alignment: .topLeading) {
                    if fields.noteText.isEmpty {
                        Text("例如：介绍作品时请先避免透露结局。")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.horizontal, 8).padding(.top, 10)
                    }
                    TextEditor(text: $fields.noteText).font(.system(size: 12)).scrollContentBackground(.hidden)
                        .frame(height: 70).padding(4).accessibilityLabel("新增长期记忆")
                }.background(Palette.wash, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    if fields.noteText.count > 2000 {
                        Text("每条记忆最多 2,000 个字符。").font(.system(size: 10)).foregroundStyle(Palette.pink)
                    }
                    Spacer()
                    Button {
                        let value = fields.noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let before = companion.memoryNotes.count
                        companion.addMemory(value)
                        if companion.memoryNotes.count > before { fields.noteText = "" }
                    } label: { Label("添加记忆", systemImage: "plus") }
                        .buttonStyle(SoftStyle())
                        .disabled(fields.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.noteText.count > 2000)
                        .accessibilityIdentifier("memory-add")
                }
                if companion.memoryNotes.isEmpty {
                    Text("尚未添加长期记忆。你可以随时在这里查看和删除。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.vertical, 7)
                } else {
                    Divider().overlay(Palette.line)
                    ForEach(companion.memoryNotes.sorted { $0.updatedAt > $1.updatedAt }) { note in memoryRow(note) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func memoryRow(_ note: MemoryNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bookmark.fill").font(.system(size: 11)).foregroundStyle(Palette.pink).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                Text(note.text).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            Button {
                fields.pendingDelete = note.id
                fields.showDeleteConfirmation = true
            } label: { Image(systemName: "trash").foregroundStyle(Palette.muted) }
                .buttonStyle(.plain).help("删除这条长期记忆").accessibilityLabel("删除记忆")
        }.padding(13).background(Palette.wash, in: RoundedRectangle(cornerRadius: 10))
    }

    private var historySearch: some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                Label("查找聊天历史", systemImage: "magnifyingglass").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 10) {
                    TextField("搜索所有游戏的聊天记录", text: $fields.query)
                        .textFieldStyle(.roundedBorder).onSubmit { search() }
                        .accessibilityIdentifier("memory-search-query")
                    Button("本地搜索") { search() }.buttonStyle(SoftStyle())
                        .disabled(fields.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if fields.didSearch {
                    if companion.memorySearchResults.isEmpty {
                        Text("没有找到相关聊天。可以换一个关键词。")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.vertical, 7)
                    }
                    ForEach(companion.memorySearchResults) { message in MemorySearchRow(message: message) }
                } else {
                    Text("输入关键词，在本机查找相关对话；不会调用模型。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func search() {
        let query = fields.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        fields.didSearch = true
        companion.searchMemory(query)
    }
}

private struct MemorySearchRow: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text(message.role == "user" ? "你" : "千咲").font(.system(size: 11, weight: .semibold))
                if let title = message.gameTitle, !title.isEmpty { Tag(text: title) }
                Spacer()
                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            Text(message.text).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(Palette.wash, in: RoundedRectangle(cornerRadius: 10))
    }
}
