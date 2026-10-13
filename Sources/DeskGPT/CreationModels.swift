import Foundation

enum ImageAPI: String, Codable, CaseIterable { case openAI = "Images API", qwen = "千问原生图片 API" }

struct ImageSettings: Codable {
    var api: ImageAPI?
    var providerID: UUID?
    var model = "gpt-image-1.5"
    var size = "1024x1024"
    var quality = "auto"
    var transparent = false
    var count = 1
    init() {}
    enum CodingKeys: String, CodingKey { case api, providerID, model, size, quality, transparent, count }
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        api = try c.decodeIfPresent(ImageAPI.self, forKey: .api)
        providerID = try c.decodeIfPresent(UUID.self, forKey: .providerID)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? model
        size = try c.decodeIfPresent(String.self, forKey: .size) ?? size
        quality = try c.decodeIfPresent(String.self, forKey: .quality) ?? quality
        transparent = try c.decodeIfPresent(Bool.self, forKey: .transparent) ?? transparent
        count = max(1, min(4, try c.decodeIfPresent(Int.self, forKey: .count) ?? count))
    }
}
struct Artwork: Identifiable, Codable {
    var id = UUID()
    var prompt: String
    var fileName: String
    var model: String
    var providerName: String
    var size: String
    var created = Date()
    var projectID: UUID?
    var sourceID: UUID?
}
