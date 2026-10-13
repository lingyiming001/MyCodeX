import Foundation
import AppKit

final class MockProtocol: URLProtocol {
    static var responses: [(Int, String)] = []
    static var requests: [URLRequest] = []
    static var imageData: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        Self.requests.append(captured)
        let (status, text) = Self.responses.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: text == "__IMAGE__" ? Self.imageData! : Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct CoreTests {
    @MainActor static func main() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var repeating = Automation(title: "repeat", prompt: "test", nextRun: Date(timeIntervalSince1970: 1_000), interval: 3600)
        repeating.advance(after: now)
        precondition(repeating.nextRun.timeIntervalSince1970 == 11_800 && repeating.enabled)
        var once = Automation(title: "once", prompt: "test", nextRun: now)
        once.advance(after: now); precondition(!once.enabled)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskStore(url: directory.appendingPathComponent("library.json"))
        let empty = try disk.load(); precondition(empty.conversations.isEmpty)
        var library = Library()
        library.conversations = [Conversation(title: "中文", mode: .work, messages: [Message(role: "user", text: "源码")])]
        library.plugins = [Plugin(name: "test", serverURL: "https://example.com/mcp", enabled: true)]
        try disk.save(library)
        let loaded = try disk.load()
        precondition(loaded.conversations[0].messages[0].text == "源码" && loaded.conversations[0].mode == .work && loaded.plugins[0].enabled)
        let chat = Conversation(mode: .work, messages: [Message(role: "user", text: "hello"), Message(role: "assistant", text: "hi")])
        var config = Configuration(); config.webSearch = true
        let body = ResponseClient.requestBody(conversation: chat, config: config, plugins: library.plugins, context: "source")
        precondition((body["input"] as? [[String: String]])?.count == 2)
        precondition(body["store"] as? Bool == false)
        let tools = body["tools"] as! [[String: Any]]
        precondition(tools.last?["require_approval"] as? String == "always" && tools.first?["type"] as? String == "web_search")
        precondition((body["instructions"] as! String).contains("source"))
        do {
            try await ResponseClient.stream(conversation: chat, config: config, plugins: [], context: "", key: "", delta: { _ in }, approve: { _, _ in false })
            preconditionFailure("Empty keys must fail before a network request")
        } catch let error as AppFailure { precondition(error.message.contains("API Key")) }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        func event(_ value: [String: Any]) throws -> String {
            "data: " + String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)! + "\n\n"
        }
        var streamed = ""
        MockProtocol.responses = [(200, try event(["type": "response.output_text.delta", "delta": "你好"]) + event(["type": "response.completed", "response": ["output": []]]))]
        try await ResponseClient.stream(conversation: chat, config: config, plugins: [], context: "", key: "test-key", session: session, delta: { streamed += $0 }, approve: { _, _ in false })
        precondition(streamed == "你好")
        let approval: [String: Any] = ["type": "mcp_approval_request", "id": "approval-1", "server_label": "test", "name": "read", "arguments": "{}"]
        MockProtocol.responses = [
            (200, try event(["type": "response.completed", "response": ["output": [approval]]])),
            (200, try event(["type": "response.output_text.delta", "delta": "approved"]) + event(["type": "response.completed", "response": ["output": []]]))
        ]
        var approvalCount = 0
        try await ResponseClient.stream(conversation: chat, config: config, plugins: [], context: "", key: "test-key", session: session, delta: { streamed += $0 }, approve: { _, detail in approvalCount += 1; precondition(detail.contains("read")); return true })
        precondition(approvalCount == 1 && streamed == "你好approved")
        let approvalBody = try JSONSerialization.jsonObject(with: MockProtocol.requests.last!.httpBody!) as! [String: Any]
        let approvalInput = approvalBody["input"] as! [[String: Any]]
        precondition(approvalInput.last?["approval_request_id"] as? String == "approval-1" && approvalInput.last?["approve"] as? Bool == true)
        MockProtocol.responses = [
            (200, try event(["type": "response.completed", "response": ["output": [approval]]])),
            (200, try event(["type": "response.completed", "response": ["output": []]]))
        ]
        try await ResponseClient.stream(conversation: chat, config: config, plugins: [], context: "", key: "test-key", session: session, delta: { _ in }, approve: { _, _ in false })
        let deniedBody = try JSONSerialization.jsonObject(with: MockProtocol.requests.last!.httpBody!) as! [String: Any]
        precondition((deniedBody["input"] as! [[String: Any]]).last?["approve"] as? Bool == false)
        MockProtocol.responses = [(401, "{\"error\":{\"message\":\"invalid key\"}}")]
        do {
            try await ResponseClient.stream(conversation: chat, config: config, plugins: [], context: "", key: "test-key", session: session, delta: { _ in }, approve: { _, _ in false })
            preconditionFailure("HTTP failures must surface")
        } catch let error as AppFailure { precondition(error.message.contains("401") && error.message.contains("invalid key")) }
        MockProtocol.responses = [(200, try event(["type": "response.output_text.delta", "delta": "partial"]))]
        do {
            try await ResponseClient.stream(conversation: chat, config: config, plugins: [], context: "", key: "test-key", session: session, delta: { _ in }, approve: { _, _ in false })
            preconditionFailure("Interrupted SSE must fail")
        } catch let error as AppFailure { precondition(error.message.contains("中断")) }
        var compatibleConfig = Configuration(); compatibleConfig.apiFormat = .chatCompletions; compatibleConfig.endpoint = "https://api.deepseek.com"; compatibleConfig.model = "deepseek-flash"
        MockProtocol.responses = [(200, try event(["choices": [["delta": ["content": "兼容回复"], "finish_reason": NSNull()]]]) + event(["choices": [["delta": [:], "finish_reason": "stop"]]]) + "data: [DONE]\n\n")]
        var compatibleText = ""
        try await ResponseClient.stream(conversation: chat, config: compatibleConfig, plugins: [], context: "", key: "provider-test", session: session, delta: { compatibleText += $0 }, approve: { _, _ in false })
        precondition(compatibleText == "兼容回复")
        precondition(MockProtocol.requests.last?.url?.path == "/chat/completions")
        precondition(MockProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer provider-test")
        let compatibleBody = try JSONSerialization.jsonObject(with: MockProtocol.requests.last!.httpBody!) as! [String: Any]
        precondition((compatibleBody["messages"] as! [[String: Any]]).first?["role"] as? String == "system")
        compatibleConfig.apiFormat = .anthropic; compatibleConfig.endpoint = "https://api.anthropic.com/v1"; compatibleConfig.maxTokens = 2048
        MockProtocol.responses = [(200, try event(["type": "content_block_delta", "delta": ["type": "text_delta", "text": "Claude 回复"]]) + event(["type": "message_stop"]))]
        compatibleText = ""
        try await ResponseClient.stream(conversation: chat, config: compatibleConfig, plugins: [], context: "", key: "claude-test", session: session, delta: { compatibleText += $0 }, approve: { _, _ in false })
        precondition(compatibleText == "Claude 回复")
        precondition(MockProtocol.requests.last?.value(forHTTPHeaderField: "x-api-key") == "claude-test")
        precondition(MockProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
        let claudeBody = try JSONSerialization.jsonObject(with: MockProtocol.requests.last!.httpBody!) as! [String: Any]
        precondition(claudeBody["system"] is String && claudeBody["max_tokens"] as? Int == 2048)
        compatibleConfig.apiFormat = .chatCompletions; compatibleConfig.endpoint = "http://localhost:11434/v1"; compatibleConfig.localWithoutKey = true
        MockProtocol.responses = [(200, "data: [DONE]\n\n")]
        try await ResponseClient.stream(conversation: chat, config: compatibleConfig, plugins: [], context: "", key: "", session: session, delta: { _ in }, approve: { _, _ in false })
        precondition(MockProtocol.requests.last?.url?.host == "localhost")
        compatibleConfig.endpoint = "http://example.com/v1"
        do { _ = try CompatibleClient.endpoint(compatibleConfig); preconditionFailure("Remote HTTP must be rejected") } catch {}
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as! [String: Any]
        legacy.removeValue(forKey: "projects"); legacy.removeValue(forKey: "providers"); legacy.removeValue(forKey: "activeProviderID")
        legacy["configuration"] = ["endpoint": "https://legacy.example.com/v1", "model": "legacy-model", "instructions": "old", "webSearch": false, "codeInterpreter": false]
        let migrated = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(migrated.providers.count == 7 && migrated.providers[0].endpoint == "https://legacy.example.com/v1" && migrated.providers[0].credentialAccount == "default")
        precondition(migrated.conversations[0].messages[0].text == "源码")
        let sourceFile = directory.appendingPathComponent("source.swift")
        try "print(1)".write(to: sourceFile, atomically: true, encoding: .utf8)
        let projectDisk = DiskStore(url: directory.appendingPathComponent("projects.json"))
        let store = AppStore(disk: projectDisk)
        let provider = store.library.providers.first { $0.kind == .deepSeek }!
        var project = Project(name: "DeskGPT Test", directory: directory.path, instructions: "项目测试专属指令", providerID: provider.id)
        store.saveProject(project)
        let projectChat = store.newChat(mode: .work, projectID: project.id)
        precondition(store.current?.workspace == directory.path && store.current?.projectID == project.id)
        store.refreshWorkspace()
        precondition(store.workspaceError == nil && store.workspaceFiles.contains { URL(fileURLWithPath: $0).lastPathComponent == "source.swift" })
        let source = try store.readTextFile(sourceFile.path); precondition(source == "print(1)")
        precondition(store.activeProvider.id == provider.id)
        precondition(store.configuration(for: store.current!).instructions.contains("项目测试专属指令"))
        project.name = "Renamed"; store.saveProject(project); precondition(store.project?.name == "Renamed")
        store.archiveProject(project.id, archived: true); precondition(store.library.projects[0].archived)
        store.moveChat(projectChat, to: nil); precondition(store.current?.projectID == nil)
        let projectReload = try projectDisk.load(); precondition(projectReload.projects[0].archived && projectReload.providers.count == 7)
        precondition(Set(projectReload.providers.map(\.credentialAccount)).count == 7)
        store.moveChat(projectChat, to: project.id)
        store.removeProject(project.id)
        precondition(store.library.projects.isEmpty && store.library.conversations.count == 1 && store.current?.projectID == nil)
        // Partial preferences migrate and hostile numeric values are bounded.
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"chatFontSize":1000,"requestTimeout":-1}"#.utf8))
        precondition(prefs.chatFontSize == 24 && prefs.requestTimeout == 30 && prefs.pluginsEnabled)
        var historyConfig = Configuration(); historyConfig.historyLimit = 2
        let historyChat = Conversation(messages: [Message(role: "user", text: "old"), Message(role: "assistant", text: "old reply"), Message(role: "user", text: "latest")])
        precondition(historyConfig.history(historyChat).map(\.text) == ["latest"])
        store.library.preferences.defaultMode = .work
        _ = store.newChat(); precondition(store.current?.mode == .work)
        store.library.preferences.requestTimeout = 90; store.library.preferences.replyLanguage = "英语"
        precondition(store.configuration(for: store.current!).requestTimeout == 90 && store.configuration(for: store.current!).instructions.contains("英语"))
        let scheduled = Automation(title: "paused", prompt: "test", nextRun: Date(timeIntervalSince1970: 1))
        store.library.automations = [scheduled]; store.library.preferences.schedulingEnabled = false
        store.tick(); precondition(store.library.automations[0].lastResult == "尚未运行")
        store.library.preferences.schedulingEnabled = true; store.library.preferences.catchUpMissedTasks = false
        store.tick(); precondition(!store.library.automations[0].enabled && store.running.isEmpty)
        store.library.preferences.fileLimitKB = 10
        let oversized = directory.appendingPathComponent("oversized.txt")
        try Data(repeating: 65, count: 11000).write(to: oversized)
        do { _ = try store.readTextFile(oversized.path); preconditionFailure("File limit must apply") } catch {}
        store.persist(); let settingsReload = try projectDisk.load(); precondition(settingsReload.preferences.defaultMode == .work)
        // Image generation, reference editing, credential isolation and media persistence.
        var imageSettings = ImageSettings(); imageSettings.transparent = true; imageSettings.count = 2
        let imageProfile = ProviderProfile(kind: .openAI)
        let imageRequest = try ImageClient.request(profile: imageProfile, settings: imageSettings, prompt: "海报", reference: nil, key: "image-test-key", timeout: 120)
        precondition(imageRequest.url?.path == "/v1/images/generations" && imageRequest.value(forHTTPHeaderField: "Authorization") == "Bearer image-test-key")
        let imageBody = try JSONSerialization.jsonObject(with: imageRequest.httpBody!) as! [String: Any]
        precondition(imageBody["model"] as? String == "gpt-image-1.5" && imageBody["background"] as? String == "transparent" && imageBody["n"] as? Int == 2 && imageBody["response_format"] == nil)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(.red, atX: 0, y: 0)
        let png = bitmap.representation(using: .png, properties: [:])!
        let editRequest = try ImageClient.request(profile: imageProfile, settings: imageSettings, prompt: "修改背景", reference: png, key: "image-test-key", timeout: 120)
        let multipart = String(decoding: editRequest.httpBody!, as: UTF8.self)
        precondition(editRequest.url?.path == "/v1/images/edits" && multipart.contains("name=\"image\"; filename=\"reference.png\"") && multipart.contains("修改背景") && multipart.contains("Content-Type: image/png"))
        do { _ = try ImageClient.request(profile: imageProfile, settings: imageSettings, prompt: "x", reference: nil, key: "", timeout: 120); preconditionFailure("Images require a key") } catch {}
        MockProtocol.responses = [(200, String(data: try JSONSerialization.data(withJSONObject: ["data": [["b64_json": png.base64EncodedString()]]]), encoding: .utf8)!)]
        let results = try await ImageClient.generate(profile: imageProfile, settings: imageSettings, prompt: "test", reference: nil, key: "test", timeout: 120, session: session)
        precondition(results.count == 1 && NSImage(data: results[0]) != nil)
        MockProtocol.responses = [(200, #"{"data":[{"b64_json":"broken"}]}"#)]
        do { _ = try await ImageClient.generate(profile: imageProfile, settings: imageSettings, prompt: "test", reference: nil, key: "test", timeout: 120, session: session); preconditionFailure("Invalid media must fail") } catch {}
        MockProtocol.responses = [(403, #"{"error":{"message":"model access denied"}}"#)]
        do { _ = try await ImageClient.generate(profile: imageProfile, settings: imageSettings, prompt: "test", reference: nil, key: "test", timeout: 120, session: session); preconditionFailure("Image API errors must fail") } catch let e as AppFailure { precondition(e.message.contains("403")) }
        let qwenProfile = ProviderProfile(kind: .qwen)
        var qwenSettings = ImageSettings(); qwenSettings.api = .qwen; qwenSettings.model = "qwen-image-2.0-pro"
        let qwenRequest = try ImageClient.request(profile: qwenProfile, settings: qwenSettings, prompt: "poster", reference: png, key: "test", timeout: 120)
        precondition(qwenRequest.url?.host == "dashscope.aliyuncs.com" && qwenRequest.url?.path == "/api/v1/services/aigc/multimodal-generation/generation")
        let qwenBody = try JSONSerialization.jsonObject(with: qwenRequest.httpBody!) as! [String: Any]
        precondition((qwenBody["parameters"] as? [String: Any])?["size"] as? String == "1024*1024")
        let qwenInput = qwenBody["input"] as! [String: Any], qwenMessages = qwenInput["messages"] as! [[String: Any]], qwenContent = qwenMessages[0]["content"] as! [[String: String]]
        precondition(qwenContent[0]["image"]!.hasPrefix("data:image/png;base64,") && qwenContent[1]["text"] == "poster")
        let qwenResponse: [String: Any] = ["output": ["choices": [["message": ["content": [["image": "https://images.example.com/result.png?signature=test"]]]]]]]
        MockProtocol.imageData = png
        MockProtocol.responses = [(200, String(data: try JSONSerialization.data(withJSONObject: qwenResponse), encoding: .utf8)!), (200, "__IMAGE__")]
        let qwenResults = try await ImageClient.generate(profile: qwenProfile, settings: qwenSettings, prompt: "test", reference: nil, key: "secret", timeout: 120, session: session)
        precondition(qwenResults.count == 1 && MockProtocol.requests.last!.value(forHTTPHeaderField: "Authorization") == nil)
        qwenSettings.transparent = true
        do { _ = try ImageClient.request(profile: qwenProfile, settings: qwenSettings, prompt: "test", reference: nil, key: "test", timeout: 120); preconditionFailure("Unsupported transparency must be explicit") } catch {}
        try store.saveArtworks(results, prompt: "persisted artwork", settings: imageSettings, profile: imageProfile, projectID: nil, sourceID: nil)
        let artwork = store.library.artworks[0]
        precondition(FileManager.default.fileExists(atPath: store.artworkURL(artwork)!.path))
        let artworkReload = try projectDisk.load(); precondition(artworkReload.artworks[0].prompt == "persisted artwork")
        store.editArtworkInChat(artwork); precondition(store.current?.messages.last?.artworkIDs == [artwork.id] && store.section == "chats")
        store.removeArtwork(artwork); precondition(store.library.artworks.isEmpty && !FileManager.default.fileExists(atPath: store.artworkURL(artwork)!.path))
        let migratedImageSettings = try JSONDecoder().decode(ImageSettings.self, from: Data(#"{"count":99}"#.utf8)); precondition(migratedImageSettings.count == 4 && migratedImageSettings.model == "gpt-image-1.5")
        // Automatic routing runs through the real AppStore send pipeline.
        let routeDisk = DiskStore(url: directory.appendingPathComponent("routing/library.json"))
        let routeStore = AppStore(disk: routeDisk)
        routeStore.networkSession = session; routeStore.credentialReader = { _ in "mock-credential" }
        let routedChat = routeStore.newChat()
        func routingEvent(_ action: String, prompt: String = "image prompt") throws -> String {
            let json = String(data: try JSONSerialization.data(withJSONObject: ["action": action, "prompt": prompt, "size": "auto"]), encoding: .utf8)!
            return try event(["type": "response.output_text.delta", "delta": json]) + event(["type": "response.completed", "response": ["output": []]])
        }
        func finish(_ store: AppStore, id: UUID) async throws {
            for _ in 0..<500 { if !store.running.contains(id) { return }; try await Task.sleep(nanoseconds: 10_000_000) }
            preconditionFailure("Routing task did not finish")
        }
        let imageJSON = String(data: try JSONSerialization.data(withJSONObject: ["data": [["b64_json": png.base64EncodedString()]]]), encoding: .utf8)!
        MockProtocol.responses = [(200, try routingEvent("generate_image")), (200, imageJSON)]
        routeStore.draft = "画一只猫"; routeStore.send(); try await finish(routeStore, id: routedChat)
        precondition(routeStore.current!.messages.last!.artworkIDs?.count == 1 && routeStore.library.artworks.count == 1)
        let generatedID = routeStore.library.artworks[0].id
        precondition(MockProtocol.requests.last!.url?.path == "/v1/images/generations")
        MockProtocol.responses = [(200, try routingEvent("edit_image", prompt: "把背景改成海边")), (200, imageJSON)]
        routeStore.draft = "把上一张背景换成海边"; routeStore.send(); try await finish(routeStore, id: routedChat)
        precondition(routeStore.library.artworks.count == 2 && routeStore.library.artworks[0].sourceID == generatedID)
        precondition(MockProtocol.requests.last!.url?.path == "/v1/images/edits")
        MockProtocol.responses = [(200, try routingEvent("chat")), (200, try event(["type": "response.output_text.delta", "delta": "普通回答"]) + event(["type": "response.completed", "response": ["output": []]]))]
        routeStore.draft = "介绍一下图片模型，不要生成"; routeStore.send(); try await finish(routeStore, id: routedChat)
        precondition(routeStore.current!.messages.last!.text == "普通回答" && routeStore.library.artworks.count == 2)
        let routedReload = try routeDisk.load(); precondition(routedReload.conversations[0].messages.contains { $0.artworkIDs?.contains(generatedID) == true })
        MockProtocol.responses = [(200, try event(["type": "response.output_text.delta", "delta": "invalid routing"]) + event(["type": "response.completed", "response": ["output": []]]))]
        routeStore.draft = "请求"; routeStore.send(); try await finish(routeStore, id: routedChat)
        precondition(routeStore.current!.messages.last!.text.contains("无法识别请求类型") && routeStore.responseStages.isEmpty)
        try Data("broken".utf8).write(to: disk.url)
        do { _ = try disk.load(); preconditionFailure("Corrupt state must not silently reset") } catch {}
        print("PASS: scheduling, persistence, history, tool approvals, key validation, corruption handling, SSE streaming, MCP approval continuation, HTTP errors, interrupted streams, multi-provider protocols, local endpoint validation, legacy migration, projects and inherited settings, image generation/editing, media validation and gallery persistence, automatic chat/image routing and follow-up editing")
    }
}
