import SwiftUI
import AppKit

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用", providers = "模型供应商", chat = "聊天", creation = "自动创作", work = "工作区", tasks = "定时任务", plugins = "插件", data = "数据与隐私", shortcuts = "快捷键", about = "关于"
    var id: String { rawValue }
    var icon: String { switch self {
    case .general: "gearshape"; case .providers: "network"; case .chat: "bubble.left.and.bubble.right"; case .creation: "sparkles"; case .work: "folder"; case .tasks: "clock"; case .plugins: "puzzlepiece.extension"; case .data: "externaldrive"; case .shortcuts: "keyboard"; case .about: "info.circle"
    } }
    var keywords: String { switch self {
    case .general: "外观 启动 默认模式 声音"; case .providers: "API Key 地址 模型 连接 协议"; case .chat: "字体 时间戳 历史 超时 语言 指令 搜索 解释器"; case .creation: "图片 自动 模型 生图 编辑 路由"; case .work: "文件 附件 大小 隐藏 排除目录"; case .tasks: "暂停 补跑 并发 自动"; case .plugins: "MCP 审批 工具"; case .data: "备份 导出 存储 隐私 重置"; case .shortcuts: "发送 新建 设置"; case .about: "版本 诊断"
    } }
}
struct SettingsCenterView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<SettingsCategory> private var category = .general
    @ViewState<String> private var search = ""
    @ViewState<String> private var status = ""
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置").font(.system(size: 23, weight: .semibold))
                TextField("搜索设置", text: $search).textFieldStyle(.roundedBorder)
                VStack(spacing: 4) {
                    ForEach(SettingsCategory.allCases.filter { search.isEmpty || ($0.rawValue + $0.keywords).localizedCaseInsensitiveContains(search) }) { item in
                        NavigationRow(title: item.rawValue, icon: item.icon, selected: category == item) { category = item; status = "" }
                    }
                }
                Spacer()
                Text("DESKGPT\n你的工作方式，由你决定。 ").font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(5)
            }.padding(20).frame(width: 188).background(Theme.sidebar)
            Rectangle().fill(Theme.border).frame(width: 1)
            if category == .providers { ProviderSettingsView() }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PageHeading(eyebrow: "Preferences", title: category.rawValue, subtitle: category.keywords.replacingOccurrences(of: " ", with: " · "))
                        content
                        if !status.isEmpty { Text(status).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled) }
                    }.padding(30).frame(maxWidth: 850).frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }.background(Theme.canvas)
    }
    func preference<T>(_ path: WritableKeyPath<AppPreferences, T>) -> Binding<T> {
        Binding(get: { store.library.preferences[keyPath: path] }, set: { store.library.preferences[keyPath: path] = $0; store.persist(); if category == .work { store.refreshWorkspace() } })
    }
    func config<T>(_ path: WritableKeyPath<Configuration, T>) -> Binding<T> {
        Binding(get: { store.library.configuration[keyPath: path] }, set: { store.library.configuration[keyPath: path] = $0; store.persist() })
    }
    @ViewBuilder var content: some View {
        switch category {
        case .general: general
        case .chat: chat
        case .creation: ImageRoutingSettings()
        case .work: work
        case .tasks: tasks
        case .plugins: plugins
        case .data: data
        case .shortcuts: shortcuts
        case .about: about
        case .providers: EmptyView()
        }
    }
    var general: some View {
        VStack(spacing: 18) {
            SettingsCard("外观与启动") {
                Picker("外观", selection: Binding(get: { store.library.configuration.appearance ?? "dark" }, set: { store.library.configuration.appearance = $0; store.persist() })) { Text("跟随系统").tag("system"); Text("深色").tag("dark"); Text("浅色").tag("light") }
                Picker("启动时显示", selection: preference(\.startupPage)) { Text("最近的对话").tag("recent"); Text("新对话").tag("new"); Text("项目列表").tag("projects") }
                Text("启动页面在下一次打开应用时生效。").font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard("默认行为") {
                Picker("新对话模式", selection: preference(\.defaultMode)) { ForEach(ChatMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("切换到 Work 时展开文件面板", isOn: preference(\.showWorkInspector))
                Toggle("回答完成时播放提示音", isOn: preference(\.completionSound))
            }
        }
    }
    var chat: some View {
        VStack(spacing: 18) {
            SettingsCard("阅读体验") {
                Stepper("消息字号：\(store.library.preferences.chatFontSize) pt", value: preference(\.chatFontSize), in: 12...24)
                Stepper("代码字号：\(store.library.preferences.codeFontSize) pt", value: preference(\.codeFontSize), in: 10...20)
                Stepper("内容最大宽度：\(store.library.preferences.chatWidth) pt", value: preference(\.chatWidth), in: 640...1200, step: 40)
                Toggle("显示消息时间", isOn: preference(\.showTimestamps))
                Toggle("生成时自动滚动到底部", isOn: preference(\.autoScroll))
            }
            SettingsCard("回答与上下文") {
                Picker("回答语言", selection: preference(\.replyLanguage)) { Text("遵循自定义指令").tag("auto"); Text("简体中文").tag("简体中文"); Text("English").tag("英语"); Text("日本語").tag("日语") }
                Text("全局自定义指令").foregroundStyle(.secondary)
                TextField("助手的回答方式", text: config(\.instructions), axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder)
                Stepper("历史消息上限：\(store.library.preferences.historyLimit == 0 ? "不限" : String(store.library.preferences.historyLimit))", value: preference(\.historyLimit), in: 0...200, step: 2)
                Text("仅影响发送给模型的上下文；本机聊天记录完整保留。0 表示不限，截取后会从用户消息开始。").font(.caption).foregroundStyle(.secondary)
                Stepper("请求超时：\(store.library.preferences.requestTimeout) 秒", value: preference(\.requestTimeout), in: 30...1800, step: 30)
            }
            SettingsCard("内置工具 · Responses") {
                Toggle("联网搜索", isOn: config(\.webSearch))
                Toggle("云端代码解释器", isOn: config(\.codeInterpreter))
                Text("需供应商和模型支持，工具调用可能产生额外费用。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    var work: some View {
        SettingsCard("文件上下文") {
            Stepper("单文件上限：\(store.library.preferences.fileLimitKB) KB", value: preference(\.fileLimitKB), in: 10...2000, step: 10)
            Stepper("消息与附件总上限：\(store.library.preferences.messageLimitKB) KB", value: preference(\.messageLimitKB), in: 100...10000, step: 100)
            Stepper("最多显示文件：\(store.library.preferences.workspaceFileLimit)", value: preference(\.workspaceFileLimit), in: 100...5000, step: 100)
            Toggle("显示隐藏文件", isOn: preference(\.showHiddenFiles))
            Text("排除的目录名（逗号分隔）").foregroundStyle(.secondary)
            TextField("node_modules, build, dist, .git", text: preference(\.excludedDirectories)).textFieldStyle(.roundedBorder)
            Text("文件仅在手动加入消息后作为上下文发送。支持 UTF-8 文本；符号链接不会被遍历。单文件和总大小限制分别检查。").font(.caption).foregroundStyle(.secondary)
        }
    }
    var tasks: some View {
        SettingsCard("自动执行") {
            Toggle("启用定时任务调度", isOn: preference(\.schedulingEnabled))
            Toggle("打开应用后补跑错过的任务", isOn: preference(\.catchUpMissedTasks))
            Stepper("自动任务最大并发：\(store.library.preferences.maximumConcurrentTasks)", value: preference(\.maximumConcurrentTasks), in: 1...8)
            Text("应用需要保持运行。暂停调度不会中断已经运行的任务，仍可手动执行。关闭补跑后，迟到超过 60 秒的执行会跳过；周期任务继续等待下次计划。").font(.caption).foregroundStyle(.secondary)
            Button("管理定时任务") { store.section = "tasks" }.buttonStyle(QuietButton())
        }
    }
    var plugins: some View {
        SettingsCard("远程 MCP 工具") {
            Toggle("允许聊天使用已启用的插件", isOn: preference(\.pluginsEnabled))
            Stepper("每次回答最多工具往返：\(store.library.preferences.pluginRounds)", value: preference(\.pluginRounds), in: 1...30)
            Text("适用于 Responses 协议。每次 MCP 调用都需要审批，审批会展示服务器、工具和参数。开关对下一次发送生效。").font(.caption).foregroundStyle(.secondary)
            Button("管理插件") { store.section = "plugins" }.buttonStyle(QuietButton())
        }
    }
    var data: some View {
        VStack(spacing: 18) {
            SettingsCard("本机数据与备份") {
                Text("\(store.library.conversations.count) 个对话 · \(store.library.projects.count) 个项目 · \(store.library.automations.count) 个任务").foregroundStyle(.secondary)
                Text("备份包含聊天内容、项目指令、供应商配置、任务和设置，不包含钥匙串中的 API Key 或作品图片文件（图片请在图库单独保存）。请妥善保存备份。").font(.caption).foregroundStyle(.secondary)
                HStack { Button("导出完整备份…") { exportBackup() }; Button("打开存储目录") { NSWorkspace.shared.open(store.storageURL.deletingLastPathComponent()) } }.buttonStyle(QuietButton())
                Text(store.storageURL.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled)
            }
            SettingsCard("恢复默认偏好") {
                Text("恢复本页的应用偏好和外观。聊天记录、项目、任务、插件、供应商及 API Key 会保留，自定义指令也会保留。").font(.caption).foregroundStyle(.secondary)
                Button("恢复默认偏好") { store.library.preferences = AppPreferences(); store.library.configuration.appearance = "dark"; store.persist(); store.refreshWorkspace(); status = "应用偏好已恢复默认。" }.buttonStyle(QuietButton())
            }
        }
    }
    var shortcuts: some View {
        SettingsCard("键盘操作") {
            shortcut("新建对话", "⌘ N")
            shortcut("打开设置", "⌘ ,")
            shortcut("发送消息", "⌘ Return")
            shortcut("消息换行", "Return")
            shortcut("复制选中文本", "⌘ C")
            shortcut("粘贴", "⌘ V")
            Text("中文输入法确认候选词使用 Return；发送使用 ⌘ Return。").font(.caption).foregroundStyle(.secondary)
        }
    }
    func shortcut(_ label: String, _ key: String) -> some View { HStack { Text(label); Spacer(); Text(key).font(.system(size: 12, design: .monospaced)).padding(6).background(Theme.elevated).clipShape(RoundedRectangle(cornerRadius: 5)) } }
    var about: some View {
        SettingsCard("DeskGPT") {
            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")").font(.headline)
            Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)").foregroundStyle(.secondary)
            Text("Chat 与 Work · 多供应商 · Projects · 定时任务 · MCP").font(.caption).foregroundStyle(.secondary)
            Text("Work 使用手动选择的文件上下文，代码可保存到本机。当前不提供自动执行终端命令。").font(.caption).foregroundStyle(.secondary)
            Button("复制诊断摘要") {
                let info = "DeskGPT \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")\n\(ProcessInfo.processInfo.operatingSystemVersionString)\n对话: \(store.library.conversations.count), 项目: \(store.library.projects.count), 供应商: \(store.library.providers.count)\n运行请求: \(store.running.count)\n调度: \(store.library.preferences.schedulingEnabled), 插件: \(store.library.preferences.pluginsEnabled)"
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string); status = "已复制诊断摘要，不包含聊天内容、地址或凭据。"
            }.buttonStyle(QuietButton())
        }
    }
    func exportBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "DeskGPT-backup-" + Date().formatted(.iso8601.year().month().day()) + ".json"
        if panel.runModal() == .OK, let url = panel.url {
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(store.library).write(to: url, options: .atomic); status = "备份已保存：" + url.path }
            catch { status = "备份失败：" + error.localizedDescription }
        }
    }
}
private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) { Text(title).font(.system(size: 14, weight: .semibold)); Divider(); content }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}
