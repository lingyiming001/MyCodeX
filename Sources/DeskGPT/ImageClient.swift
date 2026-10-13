import Foundation
import AppKit

struct ImageClient {
    static func request(profile: ProviderProfile, settings: ImageSettings, prompt: String, reference: Data?, key: String, timeout: Double) throws -> URLRequest {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure(message: "请先描述想创作的画面。") }
        guard prompt.count <= 32000 else { throw AppFailure(message: "图片描述不能超过 32000 个字符。") }
        guard !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure(message: "请配置图片模型 ID。") }
        guard !key.isEmpty || profile.kind == .ollama else { throw AppFailure(message: "请先在供应商设置中保存 API Key。") }
        var config = profile.configuration(from: Configuration()); config.apiFormat = .responses
        let base = try CompatibleClient.endpoint(config).deletingLastPathComponent()
        if (settings.api ?? (profile.kind == .qwen ? .qwen : .openAI)) == .qwen {
            guard !settings.transparent else { throw AppFailure(message: "千问图片接口不支持透明背景参数，请关闭透明背景。") }
            if let reference, reference.count > 10_000_000 { throw AppFailure(message: "千问参考图不能超过 10 MB。") }
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            components.path = "/api/v1/services/aigc/multimodal-generation/generation"
            var request = URLRequest(url: components.url!); request.httpMethod = "POST"; request.timeoutInterval = max(60, min(1800, timeout))
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var content: [[String: String]] = []
            if let reference { content.append(["image": "data:image/png;base64," + reference.base64EncodedString()]) }
            content.append(["text": prompt])
            var parameters: [String: Any] = ["n": max(1, min(4, settings.count)), "watermark": false]
            if settings.size != "auto" { parameters["size"] = settings.size.replacingOccurrences(of: "x", with: "*") }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.model, "input": ["messages": [["role": "user", "content": content]]], "parameters": parameters])
            return request
        }
        var request = URLRequest(url: base.appendingPathComponent("images").appendingPathComponent(reference == nil ? "generations" : "edits"))
        request.httpMethod = "POST"; request.timeoutInterval = max(60, min(1800, timeout))
        if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        let fields: [String: Any] = ["model": settings.model, "prompt": prompt, "size": settings.size, "quality": settings.quality, "n": max(1, min(4, settings.count)), "output_format": "png", "background": settings.transparent ? "transparent" : "auto"]
        if let reference {
            guard reference.count <= 20_000_000, NSImage(data: reference) != nil else { throw AppFailure(message: "参考图无效或超过 20 MB。") }
            let boundary = "DeskGPT-" + UUID().uuidString
            request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
            var body = Data()
            func append(_ value: String) { body.append(Data(value.utf8)) }
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n") }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"reference.png\"\r\nContent-Type: image/png\r\n\r\n")
            body.append(reference); append("\r\n--\(boundary)--\r\n"); request.httpBody = body
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        }
        return request
    }
    static func generate(profile: ProviderProfile, settings: ImageSettings, prompt: String, reference: Data?, key: String, timeout: Double, session: URLSession = .shared) async throws -> [Data] {
        let request = try request(profile: profile, settings: settings, prompt: prompt, reference: reference, key: key, timeout: timeout)
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data(), chunk = [UInt8](); chunk.reserveCapacity(16384)
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count == 16384 {
                try Task.checkCancellation(); data.append(contentsOf: chunk); chunk.removeAll(keepingCapacity: true)
                guard data.count <= 100_000_000 else { throw AppFailure(message: "图片响应过大，请减少生成数量。") }
            }
        }
        data.append(contentsOf: chunk)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AppFailure(message: "没有收到图片服务响应。") }
        guard data.count <= 100_000_000 else { throw AppFailure(message: "图片响应过大，请减少生成数量。") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            let detail = (json?["error"] as? [String: Any])?["message"] as? String ?? json?["message"] as? String ?? "图片接口请求失败，请确认供应商与所选模型。"
            throw AppFailure(message: "HTTP \(http.statusCode)：\(detail)")
        }
        if (settings.api ?? (profile.kind == .qwen ? .qwen : .openAI)) == .qwen {
            guard json?["code"] as? String == nil || json?["code"] as? String == "" else { throw AppFailure(message: json?["message"] as? String ?? "千问图片生成失败。") }
            let output = json?["output"] as? [String: Any]
            let choices = output?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let urls = (message?["content"] as? [[String: Any]] ?? []).compactMap { $0["image"] as? String }
            guard !urls.isEmpty, urls.count <= 4 else { throw AppFailure(message: "千问没有返回图片，请确认选择 qwen-image-2.0 系列模型。") }
            var results: [Data] = []
            for value in urls {
                guard let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw AppFailure(message: "图片下载地址无效。") }
                var download = URLRequest(url: url); download.timeoutInterval = 120
                // Result URLs are signed by the provider; never forward the API credential.
                let (bytes, response) = try await session.bytes(for: download)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.url?.scheme == "https" else { throw AppFailure(message: "生成成功，但图片下载失败，请重试。") }
                var image = Data(), chunk: [UInt8] = []
                for try await byte in bytes {
                    chunk.append(byte)
                    if chunk.count == 16384 { try Task.checkCancellation(); image.append(contentsOf: chunk); chunk.removeAll(keepingCapacity: true); guard image.count <= 25_000_000 else { throw AppFailure(message: "返回的图片过大。") } }
                }
                image.append(contentsOf: chunk)
                guard let bitmap = NSBitmapImageRep(data: image), let png = bitmap.representation(using: .png, properties: [:]) else { throw AppFailure(message: "返回的图片无法读取。") }
                results.append(png)
            }
            return results
        }
        guard let items = json?["data"] as? [[String: Any]], !items.isEmpty, items.count <= 4 else { throw AppFailure(message: "供应商没有返回可用图片。当前图片接口需要返回 b64_json。") }
        return try items.map { item in
            guard let value = item["b64_json"] as? String, let image = Data(base64Encoded: value), image.count <= 25_000_000, let decoded = NSBitmapImageRep(data: image), let png = decoded.representation(using: .png, properties: [:]) else { throw AppFailure(message: "图片数据无效或过大。") }
            return png
        }
    }
}
