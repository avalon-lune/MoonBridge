import SwiftUI
import MoonBridgeCore

@MainActor private final class CompanionSettingsFields: ObservableObject {
    @Published var draft = CompanionSettings()
    @Published var apiKey = ""
    @Published var saved = false
    @Published var showMemory = false
}

struct CompanionSettingsView: View {
    @EnvironmentObject var companion: CompanionModel
    @StateObject private var fields = CompanionSettingsFields()

    private var hasChanges: Bool { fields.draft != companion.settings || !fields.apiKey.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("AI 与游戏资料").font(.system(size: 27, weight: .bold))
                        Text("独立连接你的模型服务，补全游戏资料并回答问题。")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Tag(text: companion.keyReady ? "已保存 API Key" : "尚未配置密钥", tint: companion.keyReady ? Palette.blue : Palette.pink)
                }
                if let notice = companion.aiNotice {
                    CompanionNotice(text: notice) { companion.aiNotice = nil }
                }
                featureSettings
                connectionSettings
                memorySettings
                privacyCard
            }.padding(30).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }
        .background(Palette.wash).foregroundStyle(Palette.ink)
        .sheet(isPresented: $fields.showMemory) { MemoryPanelView().environmentObject(companion) }
        .onAppear {
            companion.refreshCredentialStatus()
            fields.draft = companion.settings
            fields.apiKey = ""
            fields.saved = false
            if companion.keyReady && companion.availableModels.isEmpty && !hasChanges && companion.settings.enabled {
                companion.fetchModels()
            }
        }
        .onDisappear { fields.apiKey = "" }
        .onChange(of: fields.draft) { _, _ in fields.saved = false }
        .onChange(of: fields.apiKey) { _, newValue in if !newValue.isEmpty { fields.saved = false } }
    }

    private var featureSettings: some View {
        Card {
            VStack(alignment: .leading, spacing: 19) {
                Label("功能开关", systemImage: "switch.2").font(.system(size: 15, weight: .semibold))
                settingToggle("启用联网资料与 AI", description: "关闭后仍可启动游戏、查看已缓存的资料与本地问答记录。", value: $fields.draft.enabled)
                Divider().overlay(Palette.line)
                settingToggle("导入后匹配资料", description: "导入完成后检索候选作品，由你确认后保存封面和简介。", value: $fields.draft.autoLookup)
                    .disabled(!fields.draft.enabled)
                settingToggle("问答时允许联网搜索", description: "为回答检索公开网页，并附上来源。搜索可能产生额外 API 费用。", value: $fields.draft.webSearch)
                    .disabled(!fields.draft.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var connectionSettings: some View {
        Card {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("模型连接", systemImage: "network").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Responses API").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                VStack(spacing: 15) {
                    fieldRow("API 地址", hint: "填写兼容 Responses API 的 HTTPS 基础地址，通常以 /v1 结尾。") {
                        TextField("https://api.openai.com/v1", text: $fields.draft.baseURL)
                            .accessibilityIdentifier("ai-base-url")
                    }
                    fieldRow("模型名称", hint: "列表来自当前服务；问答需支持 Responses，联网需支持搜索。选择后保存设置生效。") {
                        modelSelection
                    }
                    fieldRow("推理强度", hint: "更高的强度可能需要更长时间和更多额度。") {
                        Picker("推理强度", selection: $fields.draft.reasoningEffort) {
                            Text("低 · 更快").tag("low")
                            Text("中 · 均衡").tag("medium")
                            Text("高 · 更充分").tag("high")
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    fieldRow("代理地址", hint: "可选；留空使用系统网络。可填写本机 HTTP 代理地址。") {
                        TextField("例如 http://127.0.0.1:7897", text: $fields.draft.proxyURL)
                            .accessibilityIdentifier("ai-proxy-url")
                    }
                    fieldRow("API Key", hint: "留空保留已保存的密钥。密钥按 API 地址独立保存在本机钥匙串。") {
                        SecureField("输入新密钥，或留空保留", text: $fields.apiKey)
                            .accessibilityIdentifier("ai-api-key")
                    }
                }.textFieldStyle(.roundedBorder)
                Divider().overlay(Palette.line)
                HStack(spacing: 11) {
                    Button {
                        if companion.updateSettings(fields.draft, key: fields.apiKey.isEmpty ? nil : fields.apiKey) {
                            fields.apiKey = ""
                            fields.saved = true
                        }
                    } label: { Label("保存设置", systemImage: "checkmark") }
                        .buttonStyle(PrimaryStyle()).accessibilityIdentifier("ai-save-settings")
                    Button { companion.testConnection() } label: { Label("测试已保存的连接", systemImage: "bolt.horizontal") }
                        .buttonStyle(SoftStyle()).disabled(!companion.keyReady || !companion.settings.enabled || hasChanges)
                        .help("先保存修改，再发出一次简短的模型请求。")
                        .accessibilityIdentifier("ai-test-connection")
                    Spacer()
                    if hasChanges { Text("有未保存的修改").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    else if fields.saved { Label("已保存", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(Palette.blue) }
                }
                Text(companion.connectionStatus).font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                TextField("选择模型或输入自定义名称", text: $fields.draft.model)
                    .accessibilityIdentifier("ai-model")
                Menu {
                    ForEach(companion.availableModels, id: \.self) { name in
                        Button { fields.draft.model = name } label: {
                            if fields.draft.model == name { Label(name, systemImage: "checkmark") }
                            else { Text(name) }
                        }
                    }
                } label: { Text("选择模型") }
                    .menuStyle(.borderlessButton).frame(width: 90)
                    .disabled(companion.availableModels.isEmpty || companion.modelsBusy)
                    .accessibilityIdentifier("ai-model-picker")
                Button { companion.fetchModels() } label: {
                    if companion.modelsBusy { ProgressView().controlSize(.small) }
                    else { Text(companion.availableModels.isEmpty ? "获取接口模型列表" : "刷新列表") }
                }.buttonStyle(SoftStyle())
                    .disabled(companion.modelsBusy || hasChanges || !companion.keyReady || !companion.settings.enabled)
                    .help("读取已保存的服务地址与密钥。修改连接后请先保存设置。")
                    .accessibilityIdentifier("ai-refresh-models")
            }
            if let status = companion.modelsStatus, !status.isEmpty {
                Text(status).font(.system(size: 10)).lineSpacing(4).foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
            }
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.blue)
            VStack(alignment: .leading, spacing: 9) {
                Text("联网范围清楚，资料留在本地").font(.system(size: 14, weight: .semibold))
                Text("资料匹配提交游戏名称；问答提交游戏名称、资料摘要、近期对话和相关记忆片段。游戏本体与存档不会随这些功能上传。封面、介绍、共享聊天与长期记忆保存在本机。")
                    .font(.system(size: 12)).lineSpacing(6).foregroundStyle(Palette.muted)
                Text("月渡独立使用 API。复用同一个 Key 时，调用会计入同一账户额度；关闭本软件的 AI 功能不会改变其他项目的配置。")
                    .font(.system(size: 11)).lineSpacing(5).foregroundStyle(Palette.muted)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
    }

    private var memorySettings: some View {
        Card {
            HStack(spacing: 19) {
                ChisaIdentity(size: 43)
                Divider().frame(height: 43).overlay(Palette.line)
                VStack(alignment: .leading, spacing: 7) {
                    Text("共享长期记忆").font(.system(size: 14, weight: .semibold))
                    Text("所有游戏共用聊天与记忆。查看已保存的偏好，或在本机搜索历史对话。")
                        .font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("管理记忆") { fields.showMemory = true }.buttonStyle(SoftStyle())
                    .accessibilityIdentifier("ai-manage-memory")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingToggle(_ title: String, description: String, value: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(description).font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.muted)
            }
            Spacer()
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).tint(Palette.blue)
        }
    }

    private func fieldRow<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 17) {
            Text(title).font(.system(size: 12, weight: .medium)).frame(width: 83, alignment: .leading).padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                content().font(.system(size: 12))
                Text(hint).font(.system(size: 10)).lineSpacing(4).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
