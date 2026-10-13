import Foundation

enum ChatMode: String, Codable, CaseIterable { case chat = "Chat", work = "Work" }
enum APIFormat: String, Codable, CaseIterable {
    case responses = "Responses", chatCompletions = "Chat Completions", anthropic = "Claude Messages"
    var path: String { switch self { case .responses: return "responses"; case .chatCompletions: return "chat/completions"; case .anthropic: return "messages" } }
}
enum ProviderKind: String, Codable, CaseIterable {
    case openAI, anthropic, gemini, deepSeek, qwen, ollama, custom
    var name: String { switch self { case .openAI: return "OpenAI"; case .anthropic: return "Anthropic"; case .gemini: return "Google Gemini"; case .deepSeek: return "DeepSeek"; case .qwen: return "通义千问"; case .ollama: return "Ollama"; case .custom: return "自定义服务" } }
    var monogram: String { switch self { case .openAI: return "O"; case .anthropic: return "A"; case .gemini: return "G"; case .deepSeek: return "D"; case .qwen: return "Q"; case .ollama: return "L"; case .custom: return "+" } }
    var endpoint: String { switch self {
    case .openAI: return "https://api.openai.com/v1"
    case .anthropic: return "https://api.anthropic.com/v1"
    case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
    case .deepSeek: return "https://api.deepseek.com"
    case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
    case .ollama: return "http://localhost:11434/v1"
    case .custom: return "https://"
    } }
    var model: String { switch self {
    case .openAI: return "gpt-4.1"
    case .anthropic: return "claude-opus-5-5"
    case .gemini: return "gemini-3.8-flash"
    case .deepSeek: return "deepseek-flash"
    case .qwen: return "qwen-plus"
    case .ollama: return "qwen3:8b"
    case .custom: return ""
    } }
    var format: APIFormat { self == .openAI ? .responses : self == .anthropic ? .anthropic : .chatCompletions }
}
struct ProviderProfile: Identifiable, Codable {
    var id = UUID()
    var kind: ProviderKind
    var name: String
    var endpoint: String
    var model: String
    var format: APIFormat
    var credentialAccount: String
    var maxTokens = 4096
    init(kind: ProviderKind) {
        self.kind = kind; name = kind.name; endpoint = kind.endpoint; model = kind.model; format = kind.format
        credentialAccount = kind == .openAI ? "default" : "provider-" + id.uuidString
    }
    func configuration(from base: Configuration) -> Configuration {
        var result = base; result.endpoint = endpoint; result.model = model
        result.apiFormat = format; result.providerName = name; result.localWithoutKey = kind == .ollama; result.maxTokens = maxTokens
        if format != .responses { result.webSearch = false; result.codeInterpreter = false }
        return result
    }
}
struct Message: Identifiable, Codable {
    var id = UUID(); var role: String; var text: String; var date = Date()
    var artworkIDs: [UUID]?; var referenceFile: String?
}
struct Conversation: Identifiable, Codable {
    var id = UUID(); var title = "新对话"; var mode: ChatMode = .chat; var workspace = ""
    var messages: [Message] = []; var updated = Date()
    var projectID: UUID?; var providerID: UUID?; var workspaceBookmark: Data?
}
struct Project: Identifiable, Codable {
    var id = UUID(); var name: String; var directory = ""; var summary = ""; var instructions = ""
    var providerID: UUID?; var directoryBookmark: Data?; var archived = false; var created = Date()
}
struct Automation: Identifiable, Codable {
    var id = UUID(); var title: String; var prompt: String; var mode: ChatMode = .chat; var nextRun: Date
    var interval: Double = 0; var enabled = true; var lastResult = "尚未运行"
    var projectID: UUID?; var providerID: UUID?
    mutating func advance(after date: Date) {
        if interval > 0 {
            let steps = max(1, floor(date.timeIntervalSince(nextRun) / interval) + 1)
            nextRun = nextRun.addingTimeInterval(steps * interval)
        } else { enabled = false }
    }
}
struct Plugin: Identifiable, Codable {
    var id = UUID(); var name: String; var serverURL: String; var enabled = false
}
struct Configuration: Codable {
    var endpoint = "https://api.openai.com/v1"; var model = "gpt-4.1"
    var instructions = "请用中文回答，准确、清晰，并说明不确定性。"
    var webSearch = false; var codeInterpreter = false
    var apiFormat: APIFormat?; var providerName: String?; var localWithoutKey: Bool?; var maxTokens: Int?; var appearance: String?
    var requestTimeout: Double?; var historyLimit: Int?; var pluginRounds: Int?
    var format: APIFormat { apiFormat ?? .responses }
    func history(_ conversation: Conversation) -> [Message] {
        var messages = conversation.messages.filter { ["user", "assistant"].contains($0.role) && !$0.text.isEmpty }
        let limit = historyLimit ?? 0
        if limit > 0 && messages.count > limit { messages = Array(messages.suffix(limit)); while messages.first?.role == "assistant" { messages.removeFirst() } }
        return messages
    }
}
struct Library: Codable {
    var conversations: [Conversation] = []; var automations: [Automation] = []; var plugins: [Plugin] = []
    var configuration = Configuration()
    var projects: [Project] = []
    var providers: [ProviderProfile] = ProviderKind.allCases.map { ProviderProfile(kind: $0) }
    var activeProviderID: UUID?
    var preferences = AppPreferences()
    var imageSettings = ImageSettings()
    var artworks: [Artwork] = []
    init() { activeProviderID = providers.first?.id }
    enum CodingKeys: String, CodingKey { case conversations, automations, plugins, configuration, projects, providers, activeProviderID, preferences, imageSettings, artworks }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preferences = try c.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? AppPreferences()
        imageSettings = try c.decodeIfPresent(ImageSettings.self, forKey: .imageSettings) ?? ImageSettings()
        artworks = try c.decodeIfPresent([Artwork].self, forKey: .artworks) ?? []
        conversations = try c.decodeIfPresent([Conversation].self, forKey: .conversations) ?? []
        automations = try c.decodeIfPresent([Automation].self, forKey: .automations) ?? []
        plugins = try c.decodeIfPresent([Plugin].self, forKey: .plugins) ?? []
        configuration = try c.decodeIfPresent(Configuration.self, forKey: .configuration) ?? Configuration()
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        if let saved = try c.decodeIfPresent([ProviderProfile].self, forKey: .providers), !saved.isEmpty { providers = saved }
        else {
            providers = ProviderKind.allCases.map { ProviderProfile(kind: $0) }
            providers[0].endpoint = configuration.endpoint; providers[0].model = configuration.model
        }
        activeProviderID = try c.decodeIfPresent(UUID.self, forKey: .activeProviderID) ?? providers.first?.id
    }
    func provider(for chat: Conversation? = nil) -> ProviderProfile {
        let projectProvider = projects.first { $0.id == chat?.projectID }?.providerID
        let id = chat?.providerID ?? projectProvider ?? activeProviderID
        return providers.first { $0.id == id } ?? providers[0]
    }
}
struct AppFailure: LocalizedError { var message: String; var errorDescription: String? { message } }

struct AppPreferences: Codable {
    var startupPage = "recent"
    var defaultMode: ChatMode = .chat
    var showWorkInspector = true
    var completionSound = false
    var showTimestamps = true
    var autoScroll = true
    var chatFontSize = 14
    var codeFontSize = 12
    var chatWidth = 870
    var historyLimit = 40
    var requestTimeout = 300
    var replyLanguage = "auto"
    var fileLimitKB = 100
    var messageLimitKB = 500
    var workspaceFileLimit = 500
    var excludedDirectories = "node_modules, build, dist, vendor, .git"
    var showHiddenFiles = false
    var schedulingEnabled = true
    var catchUpMissedTasks = true
    var maximumConcurrentTasks = 2
    var pluginsEnabled = true
    var pluginRounds = 12

    init() {}
    enum CodingKeys: String, CodingKey { case startupPage, defaultMode, showWorkInspector, completionSound, showTimestamps, autoScroll, chatFontSize, codeFontSize, chatWidth, historyLimit, requestTimeout, replyLanguage, fileLimitKB, messageLimitKB, workspaceFileLimit, excludedDirectories, showHiddenFiles, schedulingEnabled, catchUpMissedTasks, maximumConcurrentTasks, pluginsEnabled, pluginRounds }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startupPage = try c.decodeIfPresent(String.self, forKey: .startupPage) ?? startupPage
        defaultMode = try c.decodeIfPresent(ChatMode.self, forKey: .defaultMode) ?? defaultMode
        showWorkInspector = try c.decodeIfPresent(Bool.self, forKey: .showWorkInspector) ?? showWorkInspector
        completionSound = try c.decodeIfPresent(Bool.self, forKey: .completionSound) ?? completionSound
        showTimestamps = try c.decodeIfPresent(Bool.self, forKey: .showTimestamps) ?? showTimestamps
        autoScroll = try c.decodeIfPresent(Bool.self, forKey: .autoScroll) ?? autoScroll
        chatFontSize = try c.decodeIfPresent(Int.self, forKey: .chatFontSize) ?? chatFontSize
        codeFontSize = try c.decodeIfPresent(Int.self, forKey: .codeFontSize) ?? codeFontSize
        chatWidth = try c.decodeIfPresent(Int.self, forKey: .chatWidth) ?? chatWidth
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? historyLimit
        requestTimeout = try c.decodeIfPresent(Int.self, forKey: .requestTimeout) ?? requestTimeout
        replyLanguage = try c.decodeIfPresent(String.self, forKey: .replyLanguage) ?? replyLanguage
        fileLimitKB = try c.decodeIfPresent(Int.self, forKey: .fileLimitKB) ?? fileLimitKB
        messageLimitKB = try c.decodeIfPresent(Int.self, forKey: .messageLimitKB) ?? messageLimitKB
        workspaceFileLimit = try c.decodeIfPresent(Int.self, forKey: .workspaceFileLimit) ?? workspaceFileLimit
        excludedDirectories = try c.decodeIfPresent(String.self, forKey: .excludedDirectories) ?? excludedDirectories
        showHiddenFiles = try c.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? showHiddenFiles
        schedulingEnabled = try c.decodeIfPresent(Bool.self, forKey: .schedulingEnabled) ?? schedulingEnabled
        catchUpMissedTasks = try c.decodeIfPresent(Bool.self, forKey: .catchUpMissedTasks) ?? catchUpMissedTasks
        maximumConcurrentTasks = try c.decodeIfPresent(Int.self, forKey: .maximumConcurrentTasks) ?? maximumConcurrentTasks
        pluginsEnabled = try c.decodeIfPresent(Bool.self, forKey: .pluginsEnabled) ?? pluginsEnabled
        pluginRounds = try c.decodeIfPresent(Int.self, forKey: .pluginRounds) ?? pluginRounds
        chatFontSize = max(12, min(24, chatFontSize))
        codeFontSize = max(10, min(20, codeFontSize))
        chatWidth = max(640, min(1200, chatWidth))
        historyLimit = max(0, min(200, historyLimit))
        requestTimeout = max(30, min(1800, requestTimeout))
        fileLimitKB = max(10, min(2000, fileLimitKB))
        messageLimitKB = max(100, min(10000, messageLimitKB))
        workspaceFileLimit = max(100, min(5000, workspaceFileLimit))
        maximumConcurrentTasks = max(1, min(8, maximumConcurrentTasks))
        pluginRounds = max(1, min(30, pluginRounds))
    }
}
