import Foundation

struct CompatibleClient {
    static func endpoint(_ config: Configuration) throws -> URL {
        let base = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/" + config.format.path), let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw AppFailure(message: "API 地址格式不正确，请填写不含认证信息或查询参数的基础地址。") }
        let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard url.scheme == "https" || (url.scheme == "http" && loopback) else { throw AppFailure(message: "远程服务必须使用 HTTPS；HTTP 仅支持本机服务。") }
        return url
    }
    static func requestBody(conversation: Conversation, config: Configuration, context: String) -> [String: Any] {
        var system = config.instructions
        if conversation.mode == .work { system += "\n你是编程助手。分析任务并提供代码或补丁；没有本地执行权限，不要声称已运行命令或修改文件。" }
        if !context.isEmpty { system += "\n用户附加的文件数据：\n" + context }
        let messages = config.history(conversation).map { ["role": $0.role, "content": $0.text] }
        if config.format == .anthropic {
            return ["model": config.model, "system": system, "messages": messages, "max_tokens": config.maxTokens ?? 4096, "stream": true]
        }
        return ["model": config.model, "messages": [["role": "system", "content": system]] + messages, "stream": true]
    }
    static func stream(conversation: Conversation, config: Configuration, context: String, key: String, session: URLSession, delta: @escaping @MainActor (String) -> Void) async throws {
        var request = URLRequest(url: try endpoint(config)); request.httpMethod = "POST"; request.timeoutInterval = config.requestTimeout ?? 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if config.format == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if request.url?.host == "generativelanguage.googleapis.com" { request.setValue("deskgpt/0.2.0", forHTTPHeaderField: "x-goog-api-client") }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(conversation: conversation, config: config, context: context))
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppFailure(message: "没有收到 HTTP 响应。") }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data(); for try await byte in bytes { if data.count >= 32768 { break }; data.append(byte) }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = (json?["error"] as? [String: Any])?["message"] as? String ?? "请求失败"
            throw AppFailure(message: "HTTP \(http.statusCode)：\(detail)")
        }
        var completed = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { completed = true; continue }
            guard let data = payload.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = event["error"] as? [String: Any] { throw AppFailure(message: error["message"] as? String ?? "供应商返回错误。") }
            if config.format == .anthropic {
                if event["type"] as? String == "content_block_delta", let change = event["delta"] as? [String: Any], change["type"] as? String == "text_delta", let text = change["text"] as? String { await delta(text) }
                if event["type"] as? String == "message_stop" { completed = true }
                if let change = event["delta"] as? [String: Any], change["stop_reason"] as? String == "max_tokens" { throw AppFailure(message: "达到输出长度上限，可提高最大输出 Token 后重试。") }
            } else if let choice = (event["choices"] as? [[String: Any]])?.first {
                if let text = (choice["delta"] as? [String: Any])?["content"] as? String { await delta(text) }
                if let reason = choice["finish_reason"] as? String {
                    if reason == "length" { throw AppFailure(message: "达到输出长度上限，回复未完成。") }
                    if reason == "content_filter" { throw AppFailure(message: "供应商过滤了此次回复。") }
                    if reason == "tool_calls" { throw AppFailure(message: "当前兼容协议尚未支持供应商工具调用。") }
                    completed = true
                }
            }
        }
        guard completed else { throw AppFailure(message: "连接中断，响应尚未完成。") }
    }
}
