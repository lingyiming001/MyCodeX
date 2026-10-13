import SwiftUI

struct ImageRoutingSettings: View {
    @EnvironmentObject var store: AppStore
    var qwen: Bool { (store.library.imageSettings.api ?? (store.imageProvider.kind == .qwen ? .qwen : .openAI)) == .qwen }
    func setting<T>(_ path: WritableKeyPath<ImageSettings, T>) -> Binding<T> { Binding(get: { store.library.imageSettings[keyPath: path] }, set: { store.library.imageSettings[keyPath: path] = $0; store.persist() }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("直接在聊天中描述需求，后台自动选择文字回答、图片生成或图片编辑。续聊修改会沿用聊天中的上一张图片。").foregroundStyle(.secondary)
            Picker("后台图片供应商", selection: Binding(get: { store.imageProvider.id }, set: { id in
                store.library.imageSettings.providerID = id
                let qwen = store.imageProvider.kind == .qwen
                store.library.imageSettings.api = qwen ? .qwen : .openAI
                store.library.imageSettings.model = qwen ? "qwen-image-2.0-pro" : "gpt-image-1.5"
                store.library.imageSettings.transparent = false; store.persist()
            })) { ForEach(store.library.providers.filter { [.openAI, .qwen, .custom].contains($0.kind) }) { Text($0.name).tag($0.id) } }
            DisclosureGroup("高级图片配置") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("图片接口", selection: Binding(get: { store.library.imageSettings.api ?? (store.imageProvider.kind == .qwen ? .qwen : .openAI) }, set: { store.library.imageSettings.api = $0; store.library.imageSettings.model = $0 == .qwen ? "qwen-image-2.0-pro" : "gpt-image-1.5"; store.library.imageSettings.transparent = false; store.persist() })) { ForEach(ImageAPI.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    TextField("图片模型 ID", text: setting(\.model)).textFieldStyle(.roundedBorder)
                    Picker("默认尺寸", selection: setting(\.size)) { Text("正方形").tag("1024x1024"); Text("横向").tag("1536x1024"); Text("纵向").tag("1024x1536"); Text("自动").tag("auto") }
                    Picker("质量", selection: setting(\.quality)) { Text("自动").tag("auto"); Text("低").tag("low"); Text("中").tag("medium"); Text("高").tag("high") }.disabled(qwen)
                    Toggle("透明背景", isOn: setting(\.transparent)).disabled(qwen)
                    Stepper("每次生成 \(store.library.imageSettings.count) 张", value: setting(\.count), in: 1...4)
                }.padding(.top, 12)
            }
            Text("需要供应商图片模型权限。图片生成可能产生 API 费用。千问不支持透明背景与质量档位；缺少默认图片凭据时，会尝试已有配置的 OpenAI 或千问供应商。").font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 12)).padding(24).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
