import SwiftUI
import AppKit

@main struct DeskGPTApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).frame(minWidth: 1000, minHeight: 680)
                .preferredColorScheme(store.library.configuration.appearance == "light" ? .light : store.library.configuration.appearance == "system" ? nil : .dark)
        }.windowStyle(.hiddenTitleBar).defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { Button("新对话") { store.newChat(projectID: store.selectedProject) }.keyboardShortcut("n") }
            CommandGroup(replacing: .appSettings) { Button("设置…") { store.section = "providers" }.keyboardShortcut(",") }
        }
        Settings { SettingsView().environmentObject(store) }
    }
}
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<String> private var search = ""
    @ViewState<Bool> private var newProject = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 242)
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                Rectangle().fill(Theme.border).frame(height: 1)
                Group {
                    switch store.section {
                    case "create": CreationView()
                    case "tasks": TasksView()
                    case "plugins": PluginsView()
                    case "projects": ProjectsView()
                    case "project": ProjectDetailView()
                    case "providers": SettingsCenterView()
                    default: ChatView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Theme.canvas)
            if store.inspectorVisible && ["chats", "project"].contains(store.section) {
                Rectangle().fill(Theme.border).frame(width: 1)
                WorkspaceInspector().frame(width: 260).background(Theme.sidebar)
            }
        }.tint(Theme.accent).font(.system(size: 13))
        .sheet(isPresented: $newProject) { ProjectEditor() }
        .sheet(isPresented: Binding(get: { !store.approvals.isEmpty }, set: { if !$0 { store.resolveApproval(false) } })) {
            VStack(alignment: .leading, spacing: 18) {
                Text("插件调用审批").font(.title2.bold())
                Text(store.approvals.first?.name ?? "").font(.headline)
                ScrollView { Text(store.approvals.first?.detail ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 250)
                Text("批准后，远程服务会收到这些参数并执行操作。").foregroundStyle(.secondary)
                HStack { Spacer(); Button("拒绝") { store.resolveApproval(false) }; Button("批准本次调用") { store.resolveApproval(true) }.buttonStyle(.borderedProminent) }
            }.padding(28).frame(width: 520)
        }.alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Theme.accent).font(.system(size: 15))
                Text("DeskGPT").font(.system(size: 14, weight: .semibold)); Spacer()
                IconButton(icon: "square.and.pencil", help: "新对话") { store.newChat(projectID: store.selectedProject) }
            }.padding(.horizontal, 18).padding(.top, 47).padding(.bottom, 23)
            VStack(spacing: 3) {
                NavigationRow(title: "所有对话", icon: "bubble.left.and.bubble.right", selected: store.section == "chats" && store.current?.projectID == nil, count: store.library.conversations.count) { store.selectedProject = nil; store.section = "chats"; store.selected = nil; store.draft = ""; store.attachments = [] }
                NavigationRow(title: "作品图库", icon: "photo.stack", selected: store.section == "create") { store.section = "create" }
                NavigationRow(title: "Projects", icon: "square.grid.2x2", selected: store.section == "projects") { store.section = "projects" }
                NavigationRow(title: "定时任务", icon: "clock", selected: store.section == "tasks", count: store.library.automations.filter(\.enabled).count) { store.section = "tasks" }
                NavigationRow(title: "插件", icon: "puzzlepiece.extension", selected: store.section == "plugins") { store.section = "plugins" }
            }.padding(.horizontal, 12)
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.tertiary); TextField("搜索对话", text: $search).textFieldStyle(.plain).font(.system(size: 12)) }.padding(9).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 7)).padding(.horizontal, 16).padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("PROJECTS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.tertiary); Spacer(); IconButton(icon: "plus", help: "创建项目") { newProject = true } }.padding(.leading, 10)
                    ForEach(store.library.projects.filter { !$0.archived }) { project in
                        VStack(spacing: 3) {
                            NavigationRow(title: project.name, icon: "folder", selected: store.selectedProject == project.id && store.section == "project") { store.openProject(project.id) }
                            if store.selectedProject == project.id || !search.isEmpty {
                                ForEach(filteredChats(projectID: project.id)) { chat in chatRow(chat).padding(.leading, 14) }
                                Button { store.newChat(mode: .work, projectID: project.id) } label: { Label("新建项目对话", systemImage: "plus").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 24).padding(.vertical, 7) }.buttonStyle(.plain)
                            }
                        }
                    }
                    if store.library.projects.isEmpty {
                        Button { newProject = true } label: { Text("创建项目，整理你的工作").font(.system(size: 11)).foregroundStyle(.tertiary).padding(10) }.buttonStyle(.plain)
                    }
                    Text("RECENTS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.tertiary).padding(.leading, 10).padding(.top, 23).padding(.bottom, 5)
                    ForEach(filteredChats(projectID: nil)) { chat in chatRow(chat) }
                }.padding(.horizontal, 12).padding(.top, 16)
            }
            Spacer(minLength: 0)
            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 16)
            NavigationRow(title: "供应商与设置", icon: "slider.horizontal.3", selected: store.section == "providers") { store.section = "providers" }.padding(12)
            HStack { Circle().fill(Theme.accent).frame(width: 5, height: 5); Text("LOCAL WORKSPACE").font(.system(size: 9, design: .monospaced)).tracking(1); Spacer(); Text("0.5").font(.system(size: 9, design: .monospaced)) }.foregroundStyle(.tertiary).padding(.horizontal, 22).padding(.bottom, 18)
        }.background(Theme.sidebar)
    }
    func filteredChats(projectID: UUID?) -> [Conversation] {
        store.library.conversations.filter { $0.projectID == projectID && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(search) }) }.sorted { $0.updated > $1.updated }
    }
    func chatRow(_ chat: Conversation) -> some View {
        NavigationRow(title: chat.title, icon: store.running.contains(chat.id) ? "circle.dotted" : chat.mode == .work ? "terminal" : "bubble.left", selected: store.selected == chat.id && store.section == "chats") { store.selectChat(chat.id) }
        .contextMenu {
            Menu("移动到项目") {
                Button("无项目") { store.moveChat(chat.id, to: nil) }
                ForEach(store.library.projects.filter { !$0.archived }) { project in Button(project.name) { store.moveChat(chat.id, to: project.id) } }
            }
            Button("导出 Markdown") { store.selectChat(chat.id); store.exportChat() }
            Button("删除对话", role: .destructive) { store.delete(chat.id) }
        }
    }
    var topbar: some View {
        HStack(spacing: 8) {
            if let project = store.project, ["chats", "project"].contains(store.section) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Button(project.name) { store.openProject(project.id) }.buttonStyle(.plain).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer()
            if store.section == "chats" {
                Label("自动", systemImage: "sparkles").font(.system(size: 11)).foregroundStyle(.secondary).help("按请求自动选择文字回答、图片生成或图片编辑")
                IconButton(icon: "arrow.clockwise", help: "重新生成") { store.retry() }.disabled(store.current?.messages.isEmpty != false || store.selected.map { store.running.contains($0) } == true)
                IconButton(icon: "square.and.arrow.up", help: "导出对话") { store.exportChat() }.disabled(store.current == nil)
            }
            if ["chats", "project"].contains(store.section) { IconButton(icon: "sidebar.right", help: "切换文件面板") { store.inspectorVisible.toggle(); store.refreshWorkspace() } }
        }.padding(.horizontal, 24).frame(height: 56)
    }
    var title: String { switch store.section { case "create": return "作品图库"; case "projects": return "Projects"; case "project": return "项目概览"; case "tasks": return "定时任务"; case "plugins": return "插件"; case "providers": return "供应商与设置"; default: return store.current?.title ?? "新对话" } }
}
