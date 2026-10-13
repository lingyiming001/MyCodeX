import SwiftUI
import AppKit

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<ChatMode> private var emptyMode = .chat
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if store.current?.messages.isEmpty != false { welcome.frame(maxWidth: 820).frame(maxWidth: .infinity).padding(.top, 100).padding(.bottom, 40) }
                    else {
                        LazyVStack(alignment: .leading, spacing: 32) {
                            ForEach(store.current?.messages ?? []) { MessageView(message: $0) }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(.horizontal, 32).padding(.vertical, 36).frame(maxWidth: CGFloat(store.library.preferences.chatWidth)).frame(maxWidth: .infinity)
                    }
                }.onChange(of: store.current?.messages.last?.text) { _, _ in if store.library.preferences.autoScroll { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.selected) { _, _ in proxy.scrollTo("bottom", anchor: .bottom); store.refreshWorkspace() }
            }
            composer.onAppear { emptyMode = store.library.preferences.defaultMode }.frame(maxWidth: 820).padding(.horizontal, 30).frame(maxWidth: .infinity)
            HStack(spacing: 6) { Text("⌘ ↵ 发送"); Text("·"); Text(store.current?.mode == .work || emptyMode == .work ? "选择文件加入上下文，代码可另存为文件" : "对话保存在本机") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 11).padding(.bottom, 18)
        }
    }
    var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) { Circle().fill(Theme.accent).frame(width: 6, height: 6); Text(store.project == nil ? "YOUR PERSONAL WORKSPACE" : "PROJECT WORKSPACE").font(.system(size: 10, design: .monospaced)).tracking(1.8).foregroundStyle(.secondary) }
            Text(store.project.map { "开始 \($0.name) 的下一项工作" } ?? "从一个想法开始。").font(.system(size: 31, weight: .medium)).padding(.top, 20)
            Text("讨论问题，打磨想法，或一起写出下一段代码。").font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 12)
            HStack(spacing: 12) {
                SuggestionCard(icon: "terminal", title: "分析代码", subtitle: "理解项目，找到改进方向") { useSuggestion("请帮我分析接下来提供的代码，指出设计和性能上的改进。", mode: .work) }
                SuggestionCard(icon: "checklist", title: "拆解任务", subtitle: "把目标变成可执行步骤") { useSuggestion("请帮我把接下来描述的目标拆解成可执行的任务。", mode: .chat) }
                SuggestionCard(icon: "pencil.and.outline", title: "创作与表达", subtitle: "让草稿更清晰、更有力量") { useSuggestion("请帮我打磨接下来提供的草稿。", mode: .chat) }
            }.padding(.top, 36)
            if store.project == nil {
                Button { store.section = "projects" } label: { HStack(spacing: 7) { Image(systemName: "folder.badge.plus"); Text("在 Project 中组织长期工作"); Image(systemName: "arrow.up.right").font(.system(size: 9)) }.font(.system(size: 11)).foregroundStyle(.secondary) }.buttonStyle(.plain).padding(.top, 28)
            }
        }.padding(.horizontal, 32)
    }
    func useSuggestion(_ text: String, mode: ChatMode) {
        emptyMode = mode
        if let id = store.selected { store.update(id) { $0.mode = mode } }
        store.draft = text
    }
    var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(store.attachments, id: \.self) { path in
                            HStack(spacing: 5) { Image(systemName: "doc.text"); Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1); Button { store.attachments.removeAll { $0 == path } } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain) }.font(.system(size: 10)).padding(7).background(Theme.elevated).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                if store.draft.isEmpty { Text("发送消息，或添加文件开始工作…").foregroundStyle(.tertiary).padding(.top, 6).padding(.leading, 4).allowsHitTesting(false) }
                TextEditor(text: $store.draft).font(.system(size: 14)).scrollContentBackground(.hidden).frame(height: 66).accessibilityLabel("消息输入")
            }
            HStack(spacing: 10) {
                IconButton(icon: "plus", help: "添加文本或源码文件") { store.attach() }
                HStack(spacing: 0) {
                    modeButton(.chat); modeButton(.work)
                }.padding(3).background(Theme.canvas).clipShape(RoundedRectangle(cornerRadius: 7))
                if let project = store.project { Label(project.name, systemImage: "folder").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1) }
                Spacer()
                if let id = store.selected, store.running.contains(id) {
                    Button { store.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 11)).frame(width: 31, height: 31).background(Theme.elevated).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).help("停止生成")
                } else {
                    Button {
                        if store.current == nil {
                            let draft = store.draft, attachments = store.attachments
                            store.newChat(mode: emptyMode, projectID: store.selectedProject)
                            store.draft = draft; store.attachments = attachments
                        }
                        store.send()
                    } label: { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(store.draft.isEmpty ? Color.secondary : Color.black).frame(width: 31, height: 31).background(store.draft.isEmpty ? Theme.elevated : Theme.accent).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command).disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("发送")
                }
            }
        }.padding(15).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.border, lineWidth: 1)).shadow(color: .black.opacity(0.08), radius: 18, y: 5)
    }
    func modeButton(_ mode: ChatMode) -> some View {
        let selected = (store.current?.mode ?? emptyMode) == mode
        return Button {
            emptyMode = mode
            if let id = store.selected { store.update(id) { $0.mode = mode } }
            if mode == .work { store.inspectorVisible = store.library.preferences.showWorkInspector; store.refreshWorkspace() }
        } label: { HStack(spacing: 4) { Image(systemName: mode == .work ? "terminal" : "bubble.left"); Text(mode.rawValue) }.font(.system(size: 10, weight: selected ? .medium : .regular)).foregroundStyle(selected ? .primary : .secondary).padding(.horizontal, 9).padding(.vertical, 5).background(selected ? Theme.elevated : .clear).clipShape(RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain).disabled(store.selected.map { store.running.contains($0) } ?? false)
    }
}
struct SuggestionCard: View {
    let icon: String; let title: String; let subtitle: String; let action: () -> Void
    @ViewState<Bool> private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.accent).frame(height: 24)
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(hovered ? Theme.elevated : Theme.panel).clipShape(RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 1))
        }.buttonStyle(.plain).onHover { hovered = $0 }
    }
}
struct MessageView: View {
    @EnvironmentObject var store: AppStore
    let message: Message
    var segments: [(isCode: Bool, language: String, text: String)] {
        message.text.components(separatedBy: "```").enumerated().map { index, part in
            if index % 2 == 0 { return (false, "", part) }
            guard let newline = part.firstIndex(of: "\n") else { return (true, "", part) }
            return (true, String(part[..<newline]), String(part[part.index(after: newline)...]))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: message.role == "user" ? "person.crop.circle" : "square.stack.3d.up.fill").foregroundStyle(message.role == "user" ? Color.secondary : Theme.accent).font(.system(size: 13))
                Text(message.role == "user" ? "你" : "DeskGPT").font(.system(size: 12, weight: .medium))
                if store.library.preferences.showTimestamps { Text(message.date, style: .time).font(.system(size: 10)).foregroundStyle(.tertiary) }
                Spacer(); IconButton(icon: "doc.on.doc", help: "复制消息") { copy(message.text) }
            }
            if message.text.isEmpty { HStack(spacing: 7) { ProgressView().controlSize(.mini); Text(store.selected.flatMap { store.responseStages[$0] } ?? "正在思考…").foregroundStyle(.secondary).font(.system(size: 12)) } }
            if let name = message.referenceFile, let url = store.referenceURL(name), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let ids = message.artworkIDs {
                ForEach(ids, id: \.self) { id in
                    if let artwork = store.library.artworks.first(where: { $0.id == id }) {
                        VStack(alignment: .leading, spacing: 10) {
                            ArtworkImage(artwork: artwork).frame(maxWidth: 520, maxHeight: 420)
                            HStack { Button("保存图片…") { store.exportArtwork(artwork) }; Button("复制图片") { store.copyArtwork(artwork) } }.buttonStyle(QuietButton())
                        }
                    } else { Text("图片已从图库删除").font(.caption).foregroundStyle(.secondary) }
                }
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.isCode {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack { Text(segment.language.isEmpty ? "code" : segment.language).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary); Spacer(); IconButton(icon: "doc.on.doc", help: "复制代码") { copy(segment.text) }; IconButton(icon: "square.and.arrow.down", help: "保存代码为文件") { store.saveCode(segment.text) } }.padding(.horizontal, 12).padding(.vertical, 4).background(Color.primary.opacity(0.04))
                        ScrollView(.horizontal) { Text(segment.text).font(.system(size: CGFloat(store.library.preferences.codeFontSize), design: .monospaced)).lineSpacing(5).textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                    }.background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
                } else if !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(.init(segment.text)).font(.system(size: CGFloat(store.library.preferences.chatFontSize))).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.padding(message.role == "user" ? 18 : 0).background(message.role == "user" ? Theme.panel : .clear).clipShape(RoundedRectangle(cornerRadius: 11))
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
struct WorkspaceInspector: View {
    @EnvironmentObject var store: AppStore
    @ViewState<String> private var search = ""
    @ViewState<String?> private var previewPath = nil
    @ViewState<String> private var preview = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("工作区").font(.system(size: 12, weight: .medium)); Spacer(); IconButton(icon: "arrow.clockwise", help: "刷新文件") { store.refreshWorkspace() } }.padding(18).frame(height: 56)
            Rectangle().fill(Theme.border).frame(height: 1)
            if let path = store.workspaceDirectory, !path.isEmpty {
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder").font(.system(size: 11, weight: .medium)).padding(.horizontal, 16).padding(.top, 18)
                Text(path).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(2).padding(.horizontal, 16).padding(.top, 6)
                TextField("筛选文件", text: $search).textFieldStyle(.plain).padding(9).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 6)).padding(14)
                if let error = store.workspaceError {
                    Text(error).font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16)
                }
                Button("重新选择目录…") {
                    if store.current == nil { store.newChat(mode: .work, projectID: store.selectedProject) }
                    store.chooseWorkspace()
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent).padding(.horizontal, 16).padding(.bottom, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.workspaceFiles.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { file in
                            HStack(spacing: 5) {
                                Button {
                                    previewPath = file
                                    do { preview = try store.readTextFile(file) } catch { preview = error.localizedDescription }
                                } label: { HStack(spacing: 7) { Image(systemName: "doc.text").foregroundStyle(.tertiary); Text(file.replacingOccurrences(of: path + "/", with: "")).lineLimit(1); Spacer(minLength: 0) }.font(.system(size: 10)).contentShape(Rectangle()) }.buttonStyle(.plain)
                                IconButton(icon: store.attachments.contains(file) ? "checkmark" : "plus", help: "加入文件上下文") { if !store.attachments.contains(file) { store.attachments.append(file) } }
                            }.padding(.leading, 14).padding(.trailing, 6)
                        }
                    }
                }
                Text("\(store.workspaceFiles.count) 个文件 · 点 + 加入上下文").font(.system(size: 9)).foregroundStyle(.tertiary).padding(16)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text("连接项目目录").font(.system(size: 12, weight: .medium))
                    Text("在项目设置中选择目录，或为当前 Work 对话选择目录。").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("选择目录") {
                        if store.current == nil { store.newChat(mode: .work, projectID: store.selectedProject) }
                        store.chooseWorkspace()
                    }.buttonStyle(QuietButton())
                }.padding(20)
                Spacer()
            }
        }.onAppear { store.refreshWorkspace() }
        .sheet(isPresented: Binding(get: { previewPath != nil }, set: { if !$0 { previewPath = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text(previewPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "").font(.headline); Spacer(); Button("完成") { previewPath = nil } }
                ScrollView([.vertical, .horizontal]) { Text(preview).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("加入消息上下文") { if let path = previewPath, !store.attachments.contains(path) { store.attachments.append(path) }; previewPath = nil }
            }.padding(24).frame(width: 720, height: 500)
        }
    }
}
