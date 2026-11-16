import SwiftUI
import AppKit
import MoonBridgeCore

enum Palette {
    static let ink = Color(red: 0.20, green: 0.27, blue: 0.39)
    static let muted = Color(red: 0.43, green: 0.49, blue: 0.60)
    static let blue = Color(red: 0.42, green: 0.58, blue: 0.80)
    static let pink = Color(red: 0.83, green: 0.58, blue: 0.71)
    static let lavender = Color(red: 0.61, green: 0.59, blue: 0.80)
    static let vermilion = pink
    static let success = Color(red: 0.24, green: 0.55, blue: 0.45)
    static let line = Color(red: 0.86, green: 0.90, blue: 0.95)
    static let wash = Color(red: 0.96, green: 0.98, blue: 1.0)
    static let surface = Color.white
    static let canvas = LinearGradient(colors: [Color(red: 0.975, green: 0.986, blue: 1.0), Color(red: 0.995, green: 0.978, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing)
}
struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 12)
            .background(LinearGradient(colors: [Palette.blue, Palette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
            .shadow(color: Palette.blue.opacity(0.16), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct SoftStyle: ButtonStyle {
    var pink = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(pink ? Palette.pink : Palette.ink)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(configuration.isPressed ? Palette.wash : .white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
    }
}
struct Tag: View {
    let text: String
    var tint: Color = Palette.blue
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.16), lineWidth: 0.6))
    }
}
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(22).background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line.opacity(0.85), lineWidth: 1))
    }
}

private enum ArtworkCache {
    static let images: NSCache<NSString, NSImage> = {
        let value = NSCache<NSString, NSImage>()
        value.countLimit = 50
        return value
    }()
    static func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let image = images.object(forKey: key) { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
    static func bundled(_ asset: String, root: URL) -> NSImage? {
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("Art/" + asset), let image = image(at: bundleURL) { return image }
        return image(at: root.appendingPathComponent("Resources/Art/" + asset))
    }
}

/// Complete composition, including headroom: decorative art is letterboxed rather than cropped.
struct BundledArtView: View {
    @EnvironmentObject var model: AppModel
    let asset: String
    var alignment: Alignment = .center
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Palette.wash, Color(red: 0.995, green: 0.97, blue: 0.985)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image = ArtworkCache.bundled(asset, root: model.paths.root) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
                } else {
                    Rectangle().stroke(Palette.line.opacity(0.7), lineWidth: 1).padding(8)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }
}

/// General artwork helper retained for existing views. Only the guide explicitly requests spring-bridge.
struct ArtView: View {
    @EnvironmentObject var model: AppModel
    var cover: String? = nil
    var alignment: Alignment = .center
    var asset: String = "cover-eva-asuka.png"
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.wash
                if let cover, let url = try? model.paths.url(cover), let image = ArtworkCache.image(at: url) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
                } else {
                    BundledArtView(asset: asset, alignment: alignment)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// A real jacket is shown in full. Missing jackets use three separate, stable illustrations.
struct GameCoverArtwork: View {
    @EnvironmentObject var model: AppModel
    let cover: String?
    let title: String
    var gameID: UUID? = nil
    private var image: NSImage? {
        guard let cover, let url = try? model.paths.url(cover) else { return nil }
        return ArtworkCache.image(at: url)
    }
    private var defaultAsset: String {
        let index: Int
        if let gameID, let position = model.document.games.firstIndex(where: { $0.id == gameID }) { index = position }
        else if let position = model.document.games.firstIndex(where: { $0.title == title }) { index = position }
        else { index = 0 }
        let assets = ["cover-eva-asuka.png", "cover-eva-rei.png", "cover-eva-mari.png"]
        return assets[index % assets.count]
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).blur(radius: 22).opacity(0.27)
                    Color.white.opacity(0.16)
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .shadow(color: Palette.ink.opacity(0.10), radius: 10)
                } else {
                    BundledArtView(asset: defaultAsset)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
                .background(Palette.wash).clipped()
        }.accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let eyebrow: String; let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !eyebrow.isEmpty {
                HStack(spacing: 8) {
                    Rectangle().fill(Palette.pink).frame(width: 14, height: 2)
                    Text(eyebrow).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.7).foregroundStyle(Palette.muted)
                }
            }
            Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.ink)
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4) }
        }
    }
}
