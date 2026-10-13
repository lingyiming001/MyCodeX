import SwiftUI

struct TasksView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<Bool> private var showNew = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading) { PageHeading(eyebrow: "Automations", title: "定时任务", subtitle: "为重复工作设置一个节奏。") }; Spacer(); Button("新建任务", systemImage: "plus") { showNew = true }.buttonStyle(QuietButton()) }
            Text("应用需保持运行，Mac 需处于唤醒状态。恢复后补跑一次到期任务。结果保存在对话列表，运行失败会记录原因。").font(.callout).foregroundStyle(.secondary)
            if store.library.automations.isEmpty { ContentUnavailableView("还没有定时任务", systemImage: "clock", description: Text("安排一次提醒或每天的 AI 工作。")) }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(store.library.automations) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(item.title).font(.headline); Spacer(); Toggle("启用", isOn: Binding(get: { store.library.automations.first { $0.id == item.id }?.enabled ?? false }, set: { value in if let index = store.library.automations.firstIndex(where: { $0.id == item.id }) { store.library.automations[index].enabled = value; store.persist() } })).toggleStyle(.switch) }
                            Text(item.prompt).lineLimit(3).foregroundStyle(.secondary)
                            HStack { Text(item.nextRun, format: .dateTime.month().day().hour().minute()); Text(item.interval == 0 ? "一次" : item.interval == 3600 ? "每小时" : item.interval == 86400 ? "每天" : "每周"); Spacer(); Text(item.lastResult).font(.caption) }
                            HStack { Button("立即运行") { store.runAutomation(item.id) }.disabled(item.lastResult == "运行中"); Button("删除", role: .destructive) { store.library.automations.removeAll { $0.id == item.id }; store.persist() } }
                        }.padding(20).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }.padding(40).sheet(isPresented: $showNew) { NewTaskView() }
    }
}
struct NewTaskView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var title = ""
    @ViewState<String> private var prompt = ""
    @ViewState<Date> private var date = Date().addingTimeInterval(3600)
    @ViewState<Double> private var interval = 0
    @ViewState<ChatMode> private var mode = .chat
    @ViewState<UUID?> private var projectID = nil
    @ViewState<UUID?> private var providerID = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("新建定时任务").font(.title2.bold())
            TextField("任务名称", text: $title)
            TextField("届时发送给 AI 的指令", text: $prompt, axis: .vertical).lineLimit(4...8)
            DatePicker("首次运行", selection: $date)
            Picker("重复", selection: $interval) { Text("一次").tag(0.0); Text("每小时").tag(3600.0); Text("每天").tag(86400.0); Text("每周").tag(604800.0) }
            Picker("模式", selection: $mode) { ForEach(ChatMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("关联项目", selection: $projectID) { Text("无项目").tag(nil as UUID?); ForEach(store.library.projects.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) } }
            Picker("供应商", selection: $providerID) { Text("跟随默认").tag(nil as UUID?); ForEach(store.library.providers) { Text($0.name).tag(Optional($0.id)) } }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("创建") { store.library.automations.append(Automation(title: title, prompt: prompt, mode: mode, nextRun: date, interval: interval, projectID: projectID, providerID: providerID)); store.persist(); dismiss() }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 480)
    }
}
struct PluginsView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<String> private var name = ""
    @ViewState<String> private var url = ""
    var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && URL(string: url)?.scheme == "https" && URL(string: url)?.host != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(eyebrow: "Extensions", title: "插件", subtitle: "为工作台连接更多能力。")
            Text("支持无需认证的 HTTPS 远程 MCP 服务。每次工具调用都会显示服务地址、工具名称与参数，由你批准或拒绝。OAuth 与本地 stdio MCP 尚未支持。").foregroundStyle(.secondary)
            GroupBox("添加服务") {
                HStack { TextField("插件名称", text: $name); TextField("https://example.com/mcp", text: $url); Button("添加") { store.library.plugins.append(Plugin(name: name, serverURL: url)); name = ""; url = ""; store.persist() }.disabled(!valid) }.padding(12)
            }
            ScrollView {
                ForEach(store.library.plugins) { plugin in
                    HStack {
                        Image(systemName: "puzzlepiece.extension.fill").font(.title2).foregroundStyle(.mint)
                        VStack(alignment: .leading) { Text(plugin.name).font(.headline); Text(plugin.serverURL).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Toggle("连接", isOn: Binding(get: { store.library.plugins.first { $0.id == plugin.id }?.enabled ?? false }, set: { value in if let index = store.library.plugins.firstIndex(where: { $0.id == plugin.id }) { store.library.plugins[index].enabled = value; store.persist() } })).toggleStyle(.switch)
                        Button(role: .destructive) { store.library.plugins.removeAll { $0.id == plugin.id }; store.persist() } label: { Image(systemName: "trash") }
                    }.padding(20).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }.padding(40)
    }
}
