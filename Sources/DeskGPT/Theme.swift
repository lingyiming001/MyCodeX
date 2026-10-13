import SwiftUI
import AppKit

typealias ViewState<Value> = SwiftUI.State<Value>
enum Theme {
    static let accent = Color(red: 0.66, green: 0.63, blue: 0.96)
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let canvas = adaptive(NSColor(white: 0.98, alpha: 1), NSColor(white: 0.095, alpha: 1))
    static let sidebar = adaptive(NSColor(white: 0.945, alpha: 1), NSColor(white: 0.075, alpha: 1))
    static let panel = adaptive(.white, NSColor(white: 0.12, alpha: 1))
    static let elevated = adaptive(.white, NSColor(white: 0.15, alpha: 1))
    static let border = Color.primary.opacity(0.08)
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: SwiftUI.ButtonStyleConfiguration) -> some View {
        configuration.label.padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : 0.035)).clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
struct NavigationRow: View {
    let title: String; let icon: String; var selected = false; var count: Int? = nil; let action: () -> Void
    @ViewState<Bool> private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18).foregroundStyle(selected ? Theme.accent : .secondary)
                Text(title).font(.system(size: 13, weight: selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                if let count, count > 0 { Text("\(count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary) }
            }.padding(.horizontal, 10).padding(.vertical, 9).background(Color.primary.opacity(selected ? 0.075 : hovered ? 0.035 : 0)).clipShape(RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
    }
}
struct IconButton: View {
    let icon: String; let help: String; let action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: icon).font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(.secondary).help(help).accessibilityLabel(help) }
}
struct PageHeading: View {
    let eyebrow: String; let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 28, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}
