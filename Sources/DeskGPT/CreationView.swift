import SwiftUI
import AppKit

struct CreationView: View {
    @EnvironmentObject var store: AppStore
    @ViewState<Artwork?> private var preview = nil
    @ViewState<String> private var search = ""
    @ViewState<Bool> private var projectOnly = false
    var qwenAPI: Bool { (store.library.imageSettings.api ?? (store.imageProvider.kind == .qwen ? .qwen : .openAI)) == .qwen }
    var visibleArtworks: [Artwork] {
        store.library.artworks.filter { (!projectOnly || $0.projectID == store.selectedProject) && (search.isEmpty || $0.prompt.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeading(eyebrow: "Creative studio", title: "你的作品。", subtitle: "直接在聊天中生成或修改图片，作品会自动保存在这里。")
                Button("在聊天中开始创作") { store.newChat(projectID: store.selectedProject) }.buttonStyle(QuietButton())
                gallery
            }.padding(32).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.sheet(item: $preview) { artwork in
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("作品预览").font(.headline); Spacer(); Button("完成") { preview = nil } }
                ArtworkImage(artwork: artwork).frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView { Text(artwork.prompt).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                HStack { Button("保存图片…") { store.exportArtwork(artwork) }; Button("复制图片") { store.copyArtwork(artwork) }; Button("继续编辑") { store.editArtworkInChat(artwork); preview = nil }.disabled(store.selected.map { store.running.contains($0) } ?? false) }.buttonStyle(QuietButton())
            }.padding(24).frame(width: 780, height: 680)
        }
    }
    var gallery: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("作品图库").font(.system(size: 18, weight: .semibold)); Text("\(visibleArtworks.count)").foregroundStyle(.tertiary); Spacer(); if store.selectedProject != nil { Toggle("仅当前项目", isOn: $projectOnly).toggleStyle(.checkbox) }; TextField("搜索作品描述", text: $search).textFieldStyle(.roundedBorder).frame(width: 180) }
            if visibleArtworks.isEmpty {
                VStack(spacing: 12) { Image(systemName: "photo.stack").font(.system(size: 34)).foregroundStyle(Theme.accent); Text("你的下一件作品，从这里开始。").foregroundStyle(.secondary); Text("生成的图片会保留提示词和模型信息，可随时继续编辑。").font(.caption).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity).padding(42).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 18) {
                ForEach(visibleArtworks) { artwork in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { preview = artwork } label: { ArtworkImage(artwork: artwork).frame(height: 200).frame(maxWidth: .infinity).contentShape(Rectangle()) }.buttonStyle(.plain)
                        Text(artwork.prompt).font(.system(size: 12)).lineLimit(2)
                        Text(artwork.model + " · " + artwork.size).font(.system(size: 10)).foregroundStyle(.tertiary)
                        HStack { IconButton(icon: "square.and.arrow.down", help: "保存图片") { store.exportArtwork(artwork) }; IconButton(icon: "doc.on.doc", help: "复制图片") { store.copyArtwork(artwork) }; Spacer(); Button("继续编辑") { store.editArtworkInChat(artwork) }.font(.caption).buttonStyle(.plain).foregroundStyle(Theme.accent).disabled(store.selected.map { store.running.contains($0) } ?? false) }
                    }.padding(14).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12)).contextMenu { Button("删除作品", role: .destructive) { store.removeArtwork(artwork) } }
                }
            }
        }
    }
}
struct ArtworkImage: View {
    @EnvironmentObject var store: AppStore
    let artwork: Artwork
    var body: some View {
        Group { if let url = store.artworkURL(artwork), let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit() } else { ContentUnavailableView("图片文件不可用", systemImage: "photo") } }.background(Theme.elevated).clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
