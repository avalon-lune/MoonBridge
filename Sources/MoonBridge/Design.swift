import SwiftUI
import AppKit
import MoonBridgeCore

enum Palette {
    static let ink = Color(red: 0.20, green: 0.27, blue: 0.39)
    static let muted = Color(red: 0.49, green: 0.55, blue: 0.66)
    static let blue = Color(red: 0.44, green: 0.60, blue: 0.83)
    static let pink = Color(red: 0.87, green: 0.64, blue: 0.74)
    static let line = Color(red: 0.86, green: 0.90, blue: 0.95)
    static let wash = Color(red: 0.96, green: 0.98, blue: 1.0)
}
struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white).padding(.horizontal, 17).padding(.vertical, 12)
            .background(LinearGradient(colors: [Palette.blue, Color(red: 0.51, green: 0.60, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Palette.blue.opacity(0.20), radius: 9, y: 4)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct SoftStyle: ButtonStyle {
    var pink = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(pink ? Palette.pink : Palette.ink)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(.white.opacity(configuration.isPressed ? 0.6 : 0.93), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
    }
}
struct Tag: View {
    let text: String
    var tint: Color = Palette.blue
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint).padding(.horizontal, 9).padding(.vertical, 5).background(tint.opacity(0.09), in: Capsule()) }
}
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.padding(22).background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line.opacity(0.65), lineWidth: 1)) }
}
struct ArtView: View {
    @EnvironmentObject var model: AppModel
    var cover: String? = nil
    var alignment: Alignment = .center
    var body: some View {
        let image: NSImage? = {
            if let cover, let url = try? model.paths.url(cover), let image = NSImage(contentsOf: url) { return image }
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("Art/spring-bridge.png")
            return bundled.flatMap { NSImage(contentsOf: $0) } ?? NSImage(contentsOf: model.paths.root.appendingPathComponent("Resources/Art/spring-bridge.png"))
        }()
        GeometryReader { geometry in
            if let image { Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment).clipped() }
            else { LinearGradient(colors: [Palette.blue.opacity(0.2), Palette.pink.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing) }
        }
    }
}
struct SectionTitle: View {
    let eyebrow: String; let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow).font(.system(size: 10, weight: .bold)).tracking(2.1).foregroundStyle(Palette.blue)
            Text(title).font(.system(size: 27, weight: .bold)).foregroundStyle(Palette.ink)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }
}
