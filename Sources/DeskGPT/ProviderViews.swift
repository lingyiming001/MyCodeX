import SwiftUI

struct ProviderSettingsView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<UUID?> private var editingID = nil
    @ViewState<String> private var key = ""
    @ViewState<String> private var status = ""
    @ViewState<Bool> private var testing = false
    @ViewState<Bool> private var credentialPresent = false
    @ViewState<UUID?> private var testID = nil
    @ViewState<Task<Void, Never>?> private var testTask = nil
    var editing: ProviderProfile { store.library.providers.first { $0.id == editingID } ?? store.library.providers[0] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeading(eyebrow: "Connection hub", title: "模型供应商", subtitle: "选择你喜欢的模型，每个供应商独立配置与保存凭据。")
                HStack {
                    Menu("添加供应商") { ForEach(ProviderKind.allCases, id: \.self) { kind in Button(kind.name) {
                        var profile = ProviderProfile(kind: kind); profile.credentialAccount = "provider-" + profile.id.uuidString
                        store.library.providers.append(profile); switchProfile(profile.id); store.persist()
                    } } }
                    Button("复制配置") {
                        var profile = editing; profile.id = UUID(); profile.name += " 副本"; profile.credentialAccount = "provider-" + profile.id.uuidString
                        store.library.providers.append(profile); switchProfile(profile.id); store.persist()
                    }.buttonStyle(QuietButton())
                }
                VStack(alignment: .leading, spacing: 22) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 5) {
                        ForEach(store.library.providers) { profile in
                            Button {
                                testTask?.cancel(); testTask = nil; testing = false; testID = nil
                                editingID = profile.id; key = ""; status = ""; credentialPresent = Keychain.hasKey(account: profile.credentialAccount)
                            } label: {
                                HStack(spacing: 11) {
                                    Text(profile.kind.monogram).font(.system(size: 12, weight: .semibold)).frame(width: 29, height: 29).background(Theme.elevated).clipShape(RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 4) { Text(profile.name).font(.system(size: 12, weight: .medium)); Text(profile.kind == .ollama ? "LOCAL" : profile.format.rawValue).font(.system(size: 9)).foregroundStyle(.tertiary) }
                                    Spacer(minLength: 0)
                                    if store.library.activeProviderID == profile.id { Circle().fill(Theme.accent).frame(width: 5, height: 5) }
                                }.padding(10).background(editing.id == profile.id ? Color.primary.opacity(0.07) : .clear).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }.padding(8).frame(maxWidth: .infinity).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) { Text(editing.name).font(.system(size: 21, weight: .medium)); Text(editing.kind == .ollama ? "本地模型 · 无需 API Key" : credentialPresent ? "API Key 已保存在钥匙串" : "等待配置 API Key").font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer()
                            Button(store.library.activeProviderID == editing.id ? "全局默认" : "设为全局默认") { store.library.activeProviderID = editing.id; store.persist() }.buttonStyle(QuietButton()).disabled(store.library.activeProviderID == editing.id)
                        }
                        providerField("显示名称", placeholder: editing.kind.name, text: profileBinding(\.name))
                        providerField("API 基础地址", placeholder: editing.kind.endpoint, text: profileBinding(\.endpoint))
                        providerField("模型 ID", placeholder: editing.kind.model, text: profileBinding(\.model))
                        HStack { Text("API 协议").foregroundStyle(.secondary); Spacer(); Picker("API 协议", selection: profileBinding(\.format)) { ForEach(APIFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 210) }
                        if editing.format == .anthropic { Stepper("最大输出：\(editing.maxTokens) Tokens", value: profileBinding(\.maxTokens), in: 256...65536, step: 256).font(.system(size: 11)) }
                        if editing.kind != .ollama {
                            VStack(alignment: .leading, spacing: 8) { Text("API Key").font(.system(size: 11)).foregroundStyle(.secondary); SecureField(credentialPresent ? "输入新 Key 可替换已保存凭据" : "输入 API Key", text: $key).textFieldStyle(.roundedBorder) }
                            Button("保存 API Key") {
                                do { try Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: editing.credentialAccount); key = ""; credentialPresent = Keychain.hasKey(account: editing.credentialAccount); status = "凭据已保存"; store.persist() } catch { status = error.localizedDescription }
                            }.buttonStyle(QuietButton()).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if credentialPresent && editing.kind != .ollama {
                            Button("清除已保存的 Key", role: .destructive) {
                                do { try Keychain.save("", account: editing.credentialAccount); credentialPresent = false; key = ""; status = "凭据已清除" }
                                catch { status = error.localizedDescription }
                            }.buttonStyle(.plain).font(.system(size: 10))
                        }
                        HStack(spacing: 12) {
                            Button { testConnection() } label: { HStack { if testing { ProgressView().controlSize(.mini) }; Text(testing ? "测试中…" : "测试连接") } }.buttonStyle(QuietButton()).disabled(testing || editing.model.isEmpty)
                            Text(status).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Text("连接测试会向所选地址发送一条短消息，可能产生 API 用量。地址和模型可按所在区域及账户权限修改。").font(.system(size: 10)).foregroundStyle(.tertiary)
                        if editing.format != .responses { Label("联网搜索、云端代码解释器和 MCP 仅用于 Responses 协议。", systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 1))
                }
            }.padding(24).frame(maxWidth: 1120).frame(maxWidth: .infinity)
        }.onChange(of: store.library.configuration.instructions) { _, _ in store.persist() }
        .onChange(of: store.library.configuration.webSearch) { _, _ in store.persist() }
        .onChange(of: store.library.configuration.codeInterpreter) { _, _ in store.persist() }
        .onAppear { if editingID == nil { editingID = store.library.activeProviderID }; credentialPresent = Keychain.hasKey(account: editing.credentialAccount) }.onDisappear { testTask?.cancel(); testTask = nil; testing = false; testID = nil; store.persist() }
    }
    func providerField(_ title: String, placeholder: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 11)).foregroundStyle(.secondary); TextField(placeholder, text: text).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced)) } }
    func profileBinding<T>(_ path: WritableKeyPath<ProviderProfile, T>) -> Binding<T> {
        let id = editing.id
        return Binding(get: { (store.library.providers.first { $0.id == id } ?? editing)[keyPath: path] }, set: { value in if let index = store.library.providers.firstIndex(where: { $0.id == id }) { store.library.providers[index][keyPath: path] = value; store.persist() } })
    }
    func switchProfile(_ id: UUID) {
        testTask?.cancel(); testTask = nil; testing = false; testID = nil
        editingID = id; key = ""; status = ""; credentialPresent = Keychain.hasKey(account: editing.credentialAccount)
    }
    func testConnection() {
        testing = true; status = ""; let token = UUID(); testID = token
        let profile = editing
        var config = profile.configuration(from: Configuration()); config.webSearch = false; config.codeInterpreter = false
        let credential = Keychain.read(account: profile.credentialAccount)
        testTask = Task {
            do {
                try await ResponseClient.stream(conversation: Conversation(messages: [Message(role: "user", text: "Reply with OK only.")]), config: config, plugins: [], context: "", key: credential, delta: { _ in }, approve: { _, _ in false })
                if testID == token { status = "连接成功" }
            } catch { if testID == token { status = Task.isCancelled ? "测试已取消" : error.localizedDescription } }
            if testID == token { testing = false; testTask = nil }
        }
    }
}
struct SettingsView: View {
    var body: some View { SettingsCenterView().frame(width: 1100, height: 760) }
}
