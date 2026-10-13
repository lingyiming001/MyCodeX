import SwiftUI
import AppKit

@MainActor final class AppStore: ObservableObject {
    @Published var library = Library()
    @Published var selected: UUID?
    @Published var section = "chats"
    @Published var selectedProject: UUID?
    @Published var inspectorVisible = false
    var project: Project? { library.projects.first { $0.id == (current?.projectID ?? selectedProject) } }
    var activeProvider: ProviderProfile { library.provider(for: current) }
    func provider(_ id: UUID) -> ProviderProfile? { library.providers.first { $0.id == id } }
    func setProvider(_ id: UUID) {
        if let chat = current { update(chat.id) { $0.providerID = id } }
        else { library.activeProviderID = id; persist() }
    }
    func configuration(for chat: Conversation) -> Configuration {
        var config = library.provider(for: chat).configuration(from: library.configuration)
        config.instructions += "\n本应用已支持在聊天中自动生成和编辑图片，用户直接描述画面或要求修改上一张图即可；作品显示在当前对话，也保存在作品图库。用户询问图片能力或操作方式时，请按这些实际能力回答，不要沿用旧聊天中‘只能文字、需要外部生图工具’的说明。不要声称已生成图片，实际图片任务由应用后台执行。"
        config.requestTimeout = Double(max(15, min(1800, library.preferences.requestTimeout)))
        config.historyLimit = max(0, library.preferences.historyLimit)
        config.pluginRounds = max(1, min(30, library.preferences.pluginRounds))
        if library.preferences.replyLanguage != "auto" { config.instructions += "\n请优先使用" + library.preferences.replyLanguage + "回答。" }
        if let project = library.projects.first(where: { $0.id == chat.projectID }), !project.instructions.isEmpty {
            config.instructions += "\n项目专属指令：\n" + project.instructions
        }
        return config
    }
    func openProject(_ id: UUID) { if let selected { savedDrafts[selected] = (draft, attachments) }; selectedProject = id; selected = nil; section = "project"; attachments = []; draft = ""; refreshWorkspace() }
    func saveProject(_ project: Project) {
        if let index = library.projects.firstIndex(where: { $0.id == project.id }) { library.projects[index] = project }
        else { library.projects.append(project) }
        for index in library.conversations.indices where library.conversations[index].projectID == project.id {
            library.conversations[index].workspace = project.directory
            library.conversations[index].workspaceBookmark = project.directoryBookmark
        }
        persist(); refreshWorkspace()
    }
    func archiveProject(_ id: UUID, archived: Bool) {
        if let index = library.projects.firstIndex(where: { $0.id == id }) { library.projects[index].archived = archived; persist() }
    }
    func removeProject(_ id: UUID) {
        library.projects.removeAll { $0.id == id }
        for index in library.conversations.indices where library.conversations[index].projectID == id { library.conversations[index].projectID = nil }
        for index in library.automations.indices where library.automations[index].projectID == id { library.automations[index].projectID = nil }
        if selectedProject == id { selectedProject = nil; if section == "project" { section = "projects" } }
        persist(); refreshWorkspace()
    }
    func moveChat(_ id: UUID, to projectID: UUID?) {
        let project = library.projects.first { $0.id == projectID }
        update(id) { $0.projectID = projectID; if let project { $0.workspace = project.directory; $0.workspaceBookmark = project.directoryBookmark } }
        if selected == id { selectedProject = projectID; refreshWorkspace() }
    }
    @Published var error: String?
    @Published var running: Set<UUID> = []
    struct Approval: Identifiable {
        var id = UUID()
        var name: String
        var detail: String
        var continuation: CheckedContinuation<Bool, Never>
    }
    @Published var approvals: [Approval] = []
    func resolveApproval(_ allowed: Bool) {
        guard !approvals.isEmpty else { return }
        approvals.removeFirst().continuation.resume(returning: allowed)
    }
    func requestApproval(name: String, detail: String) async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) }
                else { approvals.append(Approval(id: id, name: name, detail: detail, continuation: continuation)) }
            }
        } onCancel: {
            Task { @MainActor in
                if let index = self.approvals.firstIndex(where: { $0.id == id }) {
                    self.approvals.remove(at: index).continuation.resume(returning: false)
                }
            }
        }
    }
    @Published var creationStatus = ""
    @Published var draft = ""
    @Published var attachments: [String] = []
    private var jobs: [UUID: Task<Void, Never>] = [:]
    var networkSession: URLSession = .shared
    var credentialReader: (String) -> String = { Keychain.read(account: $0) }
    @Published var responseStages: [UUID: String] = [:]
    var storageURL: URL { disk.url }
    private let disk: DiskStore
    private var timer: Timer?
    init(disk: DiskStore = DiskStore()) {
        self.disk = disk
        do { library = try disk.load() } catch { let backup = disk.url.deletingLastPathComponent().appendingPathComponent("library-unreadable-" + UUID().uuidString + ".json")
            try? FileManager.default.copyItem(at: disk.url, to: backup)
            self.error = "会话库读取失败，已尝试备份至 \(backup.path)：\(error.localizedDescription)" }
        for index in library.automations.indices where library.automations[index].lastResult == "运行中" { library.automations[index].lastResult = "上次运行因应用退出而中断" }
        selected = library.conversations.first?.id
        selectedProject = current?.projectID
        if library.imageSettings.providerID == nil {
            let candidate = library.provider(for: current)
            let imageProfile = [.openAI, .qwen].contains(candidate.kind) ? candidate : library.providers.first { $0.kind == .openAI } ?? candidate
            library.imageSettings.providerID = imageProfile.id
            if imageProfile.kind == .qwen { library.imageSettings.api = .qwen; library.imageSettings.model = "qwen-image-2.0-pro" }
        }
        switch library.preferences.startupPage {
        case "projects": section = "projects"
        case "new": selected = nil
        default: break
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    var current: Conversation? { library.conversations.first { $0.id == selected } }
    func persist() { do { try disk.save(library) } catch { self.error = error.localizedDescription } }
    @discardableResult func newChat(mode: ChatMode? = nil, projectID: UUID? = nil) -> UUID {
        if let selected { savedDrafts[selected] = (draft, attachments) }
        workspaceFiles = []
        let project = library.projects.first { $0.id == projectID }
        var chat = Conversation(mode: mode ?? library.preferences.defaultMode, workspace: project?.directory ?? "", projectID: projectID)
        chat.providerID = library.provider(for: chat).id
        chat.workspaceBookmark = project?.directoryBookmark
        selectedProject = projectID
        library.conversations.insert(chat, at: 0); selected = chat.id; section = "chats"; draft = ""; attachments = []; persist(); return chat.id
    }
    func update(_ id: UUID, _ body: (inout Conversation) -> Void) {
        guard let i = library.conversations.firstIndex(where: { $0.id == id }) else { return }
        body(&library.conversations[i]); library.conversations[i].updated = Date(); persist()
    }
    private var savedDrafts: [UUID: (String, [String])] = [:]
    func selectChat(_ id: UUID) {
        if let selected { savedDrafts[selected] = (draft, attachments) }
        selected = id; selectedProject = current?.projectID; section = "chats"
        let saved = savedDrafts[id] ?? ("", [])
        draft = saved.0; attachments = saved.1; refreshWorkspace()
    }
    func retry() {
        guard let chat = current, !running.contains(chat.id), let user = chat.messages.lastIndex(where: { $0.role == "user" }) else { return }
        let prompt = chat.messages[user].text, referenceFile = chat.messages[user].referenceFile
        update(chat.id) { $0.messages.removeSubrange(user...) }
        start(id: chat.id, prompt: prompt, referenceFile: referenceFile)
    }
    func delete(_ id: UUID) {
        jobs[id]?.cancel(); library.conversations.removeAll { $0.id == id }
        if selected == id { selected = library.conversations.first?.id; draft = ""; attachments = []; refreshWorkspace() }; savedDrafts[id] = nil; persist()
    }
    func chooseWorkspace() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url, let id = selected { update(id) { $0.workspace = url.path; $0.workspaceBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }; refreshWorkspace() }
    }
    func attach() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { attachments.append(contentsOf: panel.urls.map(\.path)) }
    }
    var workspaceDirectory: String? { current?.workspace.isEmpty == false ? current?.workspace : project?.directory }
    @Published var workspaceFiles: [String] = []
    @Published var workspaceError: String?
    func workspaceURL() -> URL? {
        guard let path = workspaceDirectory, !path.isEmpty else { return nil }
        if let bookmark = current?.workspaceBookmark ?? project?.directoryBookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale), resolved.path == path { return resolved }
        }
        return URL(fileURLWithPath: path)
    }
    func readTextFile(_ path: String) throws -> String {
        let root = workspaceURL()
        let scoped = root?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { root?.stopAccessingSecurityScopedResource() } }
        let file = URL(fileURLWithPath: path)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= max(1, library.preferences.fileLimitKB) * 1000 else { throw AppFailure(message: "文件超过 \(library.preferences.fileLimitKB) KB：\(file.lastPathComponent)") }
        return try String(contentsOf: file, encoding: .utf8)
    }
    func refreshWorkspace() {
        workspaceError = nil
        guard let root = workspaceURL() else { workspaceFiles = []; return }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        do { _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
        catch { workspaceFiles = []; workspaceError = "无法读取目录：\(error.localizedDescription)\n请通过选择目录重新授权。"; return }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: library.preferences.showHiddenFiles ? [] : [.skipsHiddenFiles], errorHandler: { [weak self] _, error in
            self?.workspaceError = "部分文件无法读取：\(error.localizedDescription)"; return true
        }) else { workspaceFiles = []; workspaceError = "无法列出工作目录。"; return }
        var files: [String] = []
        for case let url as URL in enumerator {
            if library.preferences.excludedDirectories.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains(url.lastPathComponent) { enumerator.skipDescendants(); continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values?.isRegularFile == true { files.append(url.path) }
            if files.count >= max(10, library.preferences.workspaceFileLimit) { break }
        }
        workspaceFiles = files.sorted()
    }
    func saveCode(_ code: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "generated.txt"
        if let path = workspaceDirectory, !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path) }
        if panel.runModal() == .OK, let url = panel.url {
            do { try code.write(to: url, atomically: true, encoding: .utf8); refreshWorkspace() }
            catch { self.error = error.localizedDescription }
        }
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let files = attachments
        let id = selected ?? newChat(projectID: selectedProject)
        guard !running.contains(id) else { return }
        var referenceFile: String?
        do {
            var content = text
            for path in files {
                let url = URL(fileURLWithPath: path)
                if ["png", "jpg", "jpeg", "webp"].contains(url.pathExtension.lowercased()) {
                    guard referenceFile == nil else { throw AppFailure(message: "当前每条消息支持一张参考图片。") }
                    let data = try loadReferenceImage(url)
                    try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
                    let name = UUID().uuidString + ".png"
                    try data.write(to: artworkDirectory.appendingPathComponent(name), options: .atomic)
                    referenceFile = name
                    continue
                }
                content += "\n\n文件：\(url.lastPathComponent)\n" + (try readTextFile(path))
            }
            guard content.utf8.count <= max(1, library.preferences.messageLimitKB) * 1000 else { throw AppFailure(message: "消息与附件总大小不能超过 \(library.preferences.messageLimitKB) KB。") }
            draft = ""; attachments = []; start(id: id, prompt: content, referenceFile: referenceFile)
        } catch {
            if let referenceFile, let url = referenceURL(referenceFile) { try? FileManager.default.removeItem(at: url) }
            self.error = "附件读取失败：\(error.localizedDescription)"
        }
    }
    func start(id: UUID, prompt: String, automation: UUID? = nil, referenceFile: String? = nil) {
        guard !running.contains(id) else { return }
        update(id) { chat in
            if chat.messages.isEmpty { chat.title = String(prompt.prefix(32)) }
            chat.messages.append(Message(role: "user", text: prompt, referenceFile: referenceFile))
        }
        guard let chat = library.conversations.first(where: { $0.id == id }) else { return }
        let responseID = UUID()
        update(id) { $0.messages.append(Message(id: responseID, role: "assistant", text: "")) }
        running.insert(id)
        let config = configuration(for: chat)
        let profile = library.provider(for: chat)
        responseStages[id] = "正在理解你的需求…"
        let plugins = config.format == .responses && library.preferences.pluginsEnabled ? library.plugins : []
        jobs[id] = Task { [self] in
            var result = "已完成"
            do {
                let credential = credentialReader(profile.credentialAccount)
                let previousImage = chat.messages.reversed().compactMap { $0.artworkIDs?.last }.first.flatMap { imageID in library.artworks.first { $0.id == imageID } }
                let route = try await ModelRouter.classify(chat: chat, config: config, hasReference: referenceFile != nil, hasPreviousImage: previousImage != nil, key: credential, session: networkSession)
                if route.action != .chat {
                    responseStages[id] = route.action == .edit_image ? "正在修改图片…" : "正在创作图片…"
                    try await createChatImage(chat: chat, responseID: responseID, route: route, referenceFile: referenceFile, previousImage: previousImage)
                } else {
                if referenceFile != nil { throw AppFailure(message: "已收到参考图。当前支持图片生成与编辑；请描述要修改的内容，图片内容问答尚未接入。") }
                responseStages[id] = "正在回答…"
                try await ResponseClient.stream(conversation: chat, config: config, plugins: plugins, context: "", key: credential, session: networkSession, delta: { [weak self] text in
                    guard let self, let index = self.library.conversations.firstIndex(where: { $0.id == id }), let message = self.library.conversations[index].messages.firstIndex(where: { $0.id == responseID }) else { return }
                    self.library.conversations[index].messages[message].text += text
                }, approve: { [weak self] name, detail in
                    guard let self else { return false }
                    return await self.requestApproval(name: name, detail: detail)
                })
                }
            } catch {
                result = Task.isCancelled ? "已停止" : "失败：\(error.localizedDescription)"
                self.update(id) { chat in
                    if let index = chat.messages.firstIndex(where: { $0.id == responseID }) { chat.messages[index].text += "\n\n[\(result)]" }
                }
            }
            self.running.remove(id); self.jobs[id] = nil; self.responseStages[id] = nil
            if result == "已完成" && self.library.preferences.completionSound { NSSound(named: "Glass")?.play() }
            if let automation, let index = self.library.automations.firstIndex(where: { $0.id == automation }) { self.library.automations[index].lastResult = result }
            self.persist()
        }
    }
    func stop() { if let id = selected { jobs[id]?.cancel() } }
    func tick(now: Date = Date()) {
        guard library.preferences.schedulingEnabled else { return }
        let due = library.automations.filter { $0.enabled && $0.nextRun <= now }
        for item in due {
            if !library.preferences.catchUpMissedTasks && now.timeIntervalSince(item.nextRun) > 60 {
                if let i = library.automations.firstIndex(where: { $0.id == item.id }) { library.automations[i].advance(after: now); library.automations[i].lastResult = "已跳过错过的执行时间"; persist() }
                continue
            }
            guard library.automations.filter({ $0.lastResult == "运行中" }).count < max(1, library.preferences.maximumConcurrentTasks) else { break }
            runAutomation(item.id, scheduled: true, now: now)
        }
    }
    func runAutomation(_ id: UUID, scheduled: Bool = false, now: Date = Date()) {
        guard let index = library.automations.firstIndex(where: { $0.id == id }), library.automations[index].lastResult != "运行中" else { return }
        let item = library.automations[index]
        if scheduled { library.automations[index].advance(after: now) }
        library.automations[index].lastResult = "运行中"
        let project = library.projects.first { $0.id == item.projectID }
        let chat = Conversation(title: "定时 · " + item.title, mode: item.mode, workspace: project?.directory ?? "", projectID: item.projectID, providerID: item.providerID)
        library.conversations.insert(chat, at: 0); persist()
        start(id: chat.id, prompt: item.prompt, automation: id)
    }
    func exportChat() {
        guard let chat = current else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "conversation.md"
        if panel.runModal() == .OK, let url = panel.url {
            do { try ("# \(chat.title)\n\n" + chat.messages.map { "## \($0.role)\n\n\($0.text)" }.joined(separator: "\n\n")).write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
        }
    }
}
