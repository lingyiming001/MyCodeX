import SwiftUI
import AppKit

struct ProjectsView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<Bool> private var showEditor = false
    @ViewState<Bool> private var showArchived = false
    @ViewState<Project?> private var editing = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .top) {
                    PageHeading(eyebrow: "Organize your work", title: "Projects", subtitle: "把对话、代码和项目指令放在同一个地方。")
                    Spacer()
                    Button { editing = nil; showEditor = true } label: { Label("新建项目", systemImage: "plus") }.buttonStyle(QuietButton())
                }
                HStack { Text("\(store.library.projects.filter { !$0.archived }.count) 个活跃项目").foregroundStyle(.secondary); Spacer(); Toggle("显示归档", isOn: $showArchived).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11)) }
                if store.library.projects.filter({ showArchived || !$0.archived }).isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 30)).foregroundStyle(Theme.accent)
                        Text("为下一项工作留一个空间").font(.system(size: 19, weight: .medium))
                        Text("关联本地目录、设定项目指令，并在项目内开展多轮对话。").foregroundStyle(.secondary)
                        Button("创建第一个项目") { editing = nil; showEditor = true }.buttonStyle(QuietButton())
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(32).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border, lineWidth: 1))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 255), spacing: 16)], spacing: 16) {
                    ForEach(store.library.projects.filter { showArchived || !$0.archived }) { project in
                        Button { store.openProject(project.id) } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack { Image(systemName: project.archived ? "archivebox" : "folder").font(.system(size: 19)).foregroundStyle(Theme.accent); Spacer(); Text(project.archived ? "已归档" : "PROJECT").font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(.tertiary) }
                                Text(project.name).font(.system(size: 17, weight: .medium))
                                Text(project.summary.isEmpty ? "添加项目描述，记录你的目标。" : project.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).frame(height: 36, alignment: .top)
                                Rectangle().fill(Theme.border).frame(height: 1)
                                HStack { Label("\(store.library.conversations.filter { $0.projectID == project.id }.count) 个对话", systemImage: "bubble.left"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 10)).foregroundStyle(.secondary)
                            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                        }.buttonStyle(.plain).contextMenu {
                            Button("编辑项目") { editing = project; showEditor = true }
                            Button(project.archived ? "恢复项目" : "归档项目") { store.archiveProject(project.id, archived: !project.archived) }
                            Button("移除项目，保留对话", role: .destructive) { store.removeProject(project.id) }
                        }
                    }
                }
            }.padding(40).frame(maxWidth: 1150).frame(maxWidth: .infinity)
        }.sheet(isPresented: $showEditor) { ProjectEditor(existing: editing) }
    }
}
struct ProjectDetailView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<Bool> private var editing = false
    var body: some View {
        if let project = store.project {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(alignment: .top) {
                        PageHeading(eyebrow: "Project workspace", title: project.name, subtitle: project.summary.isEmpty ? "独立上下文，让工作持续向前。" : project.summary)
                        Spacer(); IconButton(icon: "slider.horizontal.3", help: "编辑项目") { editing = true }
                    }
                    HStack(spacing: 14) {
                        detailTile("对话", value: "\(chats(project).count)", icon: "bubble.left.and.bubble.right")
                        detailTile("工作目录", value: project.directory.isEmpty ? "未连接" : URL(fileURLWithPath: project.directory).lastPathComponent, icon: "folder")
                        detailTile("默认供应商", value: project.providerID.flatMap { store.provider($0)?.name } ?? "跟随全局", icon: "cpu")
                    }
                    HStack {
                        Text("项目对话").font(.system(size: 15, weight: .medium)); Spacer()
                        Button { store.newChat(mode: .work, projectID: project.id); store.inspectorVisible = true } label: { Label("开始 Work", systemImage: "terminal") }.buttonStyle(QuietButton())
                        Button { store.newChat(projectID: project.id) } label: { Label("新对话", systemImage: "plus") }.buttonStyle(QuietButton())
                    }
                    if chats(project).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("下一项任务，从这里开始。").font(.system(size: 18, weight: .medium))
                            Text("项目内的对话会继承目录和项目指令，文件由你选择后加入上下文。").foregroundStyle(.secondary)
                            Button("创建项目对话") { store.newChat(mode: .work, projectID: project.id) }.buttonStyle(QuietButton()).padding(.top, 8)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(26).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(spacing: 0) {
                        ForEach(chats(project)) { chat in
                            Button { store.selectChat(chat.id) } label: {
                                HStack(spacing: 14) { Image(systemName: chat.mode == .work ? "terminal" : "bubble.left").foregroundStyle(.secondary); VStack(alignment: .leading, spacing: 5) { Text(chat.title).font(.system(size: 13, weight: .medium)); Text(chat.messages.last?.text ?? "尚未发送消息").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Text(chat.updated, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary); Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary) }.padding(18).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Rectangle().fill(Theme.border).frame(height: 1)
                        }
                    }.background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 10))
                    if !project.instructions.isEmpty { VStack(alignment: .leading, spacing: 10) { Label("项目指令", systemImage: "text.alignleft").font(.system(size: 12, weight: .medium)); Text(project.instructions).foregroundStyle(.secondary).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 10)) }
                }.padding(40).frame(maxWidth: 1080).frame(maxWidth: .infinity)
            }.sheet(isPresented: $editing) { ProjectEditor(existing: project) }
        } else { ProjectsView() }
    }
    func chats(_ project: Project) -> [Conversation] { store.library.conversations.filter { $0.projectID == project.id }.sorted { $0.updated > $1.updated } }
    func detailTile(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 13) { Label(title, systemImage: icon).font(.system(size: 10)).foregroundStyle(.secondary); Text(value).font(.system(size: 15, weight: .medium)).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }
}
struct ProjectEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let existing: Project?
    @ViewState<String> private var name: String
    @ViewState<String> private var summary: String
    @ViewState<String> private var directory: String
    @ViewState<String> private var instructions: String
    @ViewState<Data?> private var directoryBookmark: Data?
    @ViewState<UUID?> private var providerID: UUID?
    init(existing: Project? = nil) {
        self.existing = existing
        _name = ViewState(initialValue: existing?.name ?? "")
        _summary = ViewState(initialValue: existing?.summary ?? "")
        _directory = ViewState(initialValue: existing?.directory ?? "")
        _instructions = ViewState(initialValue: existing?.instructions ?? "")
        _providerID = ViewState(initialValue: existing?.providerID)
        _directoryBookmark = ViewState(initialValue: existing?.directoryBookmark)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(eyebrow: "Project", title: existing == nil ? "创建项目" : "编辑项目", subtitle: "一个目录，一组指令，一段持续的工作。")
            field("项目名称", placeholder: "例如：网站重构、研究笔记", text: $name)
            field("项目描述", placeholder: "这个项目想完成什么？", text: $summary)
            VStack(alignment: .leading, spacing: 8) {
                Text("本地工作目录").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack { TextField("可选：连接本地目录", text: $directory).textFieldStyle(.roundedBorder); Button("选择…") { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK { directory = panel.url?.path ?? ""; directoryBookmark = try? panel.url?.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) } } }
            }
            VStack(alignment: .leading, spacing: 8) { Text("项目指令").font(.system(size: 11)).foregroundStyle(.secondary); TextField("例如：使用 SwiftUI，优先使用中文回答。", text: $instructions, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder) }
            Picker("默认供应商", selection: $providerID) { Text("跟随全局").tag(nil as UUID?); ForEach(store.library.providers) { Text($0.name).tag(Optional($0.id)) } }
            Text("选择目录不会自动上传文件；项目指令会随项目内的聊天请求发送。").font(.system(size: 10)).foregroundStyle(.tertiary)
            HStack { Spacer(); Button("取消") { dismiss() }; Button(existing == nil ? "创建项目" : "保存修改") {
                var project = existing ?? Project(name: name)
                project.name = name.trimmingCharacters(in: .whitespacesAndNewlines); project.summary = summary; project.directory = directory; project.instructions = instructions; project.providerID = providerID; project.directoryBookmark = directoryBookmark
                store.saveProject(project); store.openProject(project.id); dismiss()
            }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(30).frame(width: 540).background(Theme.canvas)
    }
    func field(_ title: String, placeholder: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 11)).foregroundStyle(.secondary); TextField(placeholder, text: text).textFieldStyle(.roundedBorder) } }
}
