import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppStore {
    var imageProvider: ProviderProfile { library.providers.first { $0.id == library.imageSettings.providerID } ?? library.providers.first { $0.kind == .openAI } ?? library.providers[0] }
    var artworkDirectory: URL { storageURL.deletingLastPathComponent().appendingPathComponent("artworks", isDirectory: true) }
    func artworkURL(_ artwork: Artwork) -> URL? {
        guard artwork.fileName == URL(fileURLWithPath: artwork.fileName).lastPathComponent, artwork.fileName.hasSuffix(".png") else { return nil }
        return artworkDirectory.appendingPathComponent(artwork.fileName)
    }
    @discardableResult func saveArtworks(_ images: [Data], prompt: String, settings: ImageSettings, profile: ProviderProfile, projectID: UUID?, sourceID: UUID?) throws -> [Artwork] {
        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        var saved: [Artwork] = []
        do {
            for image in images {
                let fileName = UUID().uuidString + ".png"
                let item = Artwork(prompt: prompt, fileName: fileName, model: settings.model, providerName: profile.name, size: settings.size, projectID: projectID, sourceID: sourceID)
                try image.write(to: artworkDirectory.appendingPathComponent(fileName), options: .atomic); saved.append(item)
            }
            var updated = library; updated.artworks.insert(contentsOf: saved, at: 0)
            try DiskStore(url: storageURL).save(updated); library = updated
            return saved
        } catch {
            for item in saved { try? FileManager.default.removeItem(at: artworkDirectory.appendingPathComponent(item.fileName)) }
            throw error
        }
    }
    func exportArtwork(_ artwork: Artwork) {
        guard let source = artworkURL(artwork) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "DeskGPT-" + String(artwork.id.uuidString.prefix(8)) + ".png"
        if panel.runModal() == .OK, let url = panel.url { do { try Data(contentsOf: source).write(to: url, options: .atomic) } catch { self.error = error.localizedDescription } }
    }
    func copyArtwork(_ artwork: Artwork) {
        guard let url = artworkURL(artwork), let image = NSImage(contentsOf: url) else { creationStatus = "作品文件无法读取。"; return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]); creationStatus = "图片已复制。"
    }
    func removeArtwork(_ artwork: Artwork) {
        var updated = library; updated.artworks.removeAll { $0.id == artwork.id }
        do {
            try DiskStore(url: storageURL).save(updated); library = updated
            if let url = artworkURL(artwork) { try? FileManager.default.removeItem(at: url) }
        } catch { self.error = error.localizedDescription }
    }
}

extension AppStore {
    func loadReferenceImage(_ url: URL) throws -> Data {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else { throw AppFailure(message: "参考图不能超过 20 MB。") }
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)), let png = bitmap.representation(using: .png, properties: [:]), png.count <= 20_000_000 else { throw AppFailure(message: "参考图无法读取或过大。") }
        return png
    }
    func referenceURL(_ name: String) -> URL? {
        guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".png") else { return nil }
        return artworkDirectory.appendingPathComponent(name)
    }
    func createChatImage(chat: Conversation, responseID: UUID, route: RoutedRequest, referenceFile: String?, previousImage: Artwork?) async throws {
        var settings = library.imageSettings
        let configured = imageProvider
        let currentProfile = library.provider(for: chat)
        let profile: ProviderProfile
        if !credentialReader(configured.credentialAccount).isEmpty { profile = configured }
        else if [.openAI, .qwen].contains(currentProfile.kind), !credentialReader(currentProfile.credentialAccount).isEmpty { profile = currentProfile }
        else if let available = library.providers.first(where: { [.openAI, .qwen].contains($0.kind) && !credentialReader($0.credentialAccount).isEmpty }) { profile = available }
        else { throw AppFailure(message: "图片请求已识别，请先在设置中配置支持图片的供应商 API Key。") }
        if profile.id != configured.id {
            settings.api = profile.kind == .qwen ? .qwen : .openAI
            settings.model = profile.kind == .qwen ? "qwen-image-2.0-pro" : "gpt-image-1.5"
            if profile.kind == .qwen { settings.transparent = false }
        }
        if let size = route.size, size != "auto" { settings.size = size }
        var reference: Data?, sourceID: UUID?
        if route.action == .edit_image {
            if let referenceFile, let url = referenceURL(referenceFile) { reference = try Data(contentsOf: url) }
            else if let previousImage, let url = artworkURL(previousImage) { reference = try Data(contentsOf: url); sourceID = previousImage.id }
            else { throw AppFailure(message: "请先添加要修改的图片。") }
        }
        let prompt = route.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prompt, !prompt.isEmpty else { throw AppFailure(message: "未能理解画面描述，请补充具体需求。") }
        let results = try await ImageClient.generate(profile: profile, settings: settings, prompt: prompt, reference: reference, key: credentialReader(profile.credentialAccount), timeout: Double(library.preferences.requestTimeout), session: networkSession)
        try Task.checkCancellation()
        guard library.conversations.contains(where: { $0.id == chat.id && $0.messages.contains(where: { $0.id == responseID }) }) else { throw CancellationError() }
        let artworks = try saveArtworks(results, prompt: prompt, settings: settings, profile: profile, projectID: chat.projectID, sourceID: sourceID)
        update(chat.id) { conversation in
            if let i = conversation.messages.firstIndex(where: { $0.id == responseID }) {
                conversation.messages[i].text = route.action == .edit_image ? "图片已修改。" : "图片已生成。"
                conversation.messages[i].artworkIDs = artworks.map(\.id)
            }
        }
    }
    func editArtworkInChat(_ artwork: Artwork) {
        if current == nil || current?.projectID != artwork.projectID { newChat(projectID: artwork.projectID) }
        guard let id = selected else { return }
        if current?.messages.contains(where: { $0.artworkIDs?.contains(artwork.id) == true }) != true {
            update(id) { $0.messages.append(Message(role: "assistant", text: "可以继续修改这张图片。", artworkIDs: [artwork.id])) }
        }
        section = "chats"; draft = "请修改这张图片："
    }
}
