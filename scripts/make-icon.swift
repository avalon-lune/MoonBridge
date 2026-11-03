import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("build/MoonBridge.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = AffineTransform(scale: CGFloat(size)/1024); (transform as NSAffineTransform).concat()
    let bg = NSBezierPath(roundedRect: NSRect(x: 36,y: 36,width: 952,height: 952), xRadius: 215, yRadius: 215)
    NSGradient(starting: NSColor(calibratedRed: 0.47,green: 0.64,blue: 0.91,alpha: 1), ending: NSColor(calibratedRed: 0.90,green: 0.66,blue: 0.80,alpha: 1))!.draw(in: bg, angle: -42)
    let moon = NSBezierPath(); moon.windingRule = .evenOdd
    moon.appendOval(in: NSRect(x: 245,y: 280,width: 480,height: 480))
    moon.appendOval(in: NSRect(x: 365,y: 405,width: 400,height: 400))
    NSGraphicsContext.saveGraphicsState(); NSBezierPath(ovalIn: NSRect(x: 245,y: 280,width: 480,height: 480)).addClip(); NSColor.white.withAlphaComponent(0.96).setFill();moon.fill();NSGraphicsContext.restoreGraphicsState()
    func star(_ x: CGFloat,_ y: CGFloat,_ radius: CGFloat) {
        let p=NSBezierPath();p.move(to:NSPoint(x:x,y:y+radius));p.curve(to:NSPoint(x:x+radius,y:y),controlPoint1:NSPoint(x:x+radius*0.15,y:y+radius*0.15),controlPoint2:NSPoint(x:x+radius*0.15,y:y+radius*0.15));p.curve(to:NSPoint(x:x,y:y-radius),controlPoint1:NSPoint(x:x+radius*0.15,y:y-radius*0.15),controlPoint2:NSPoint(x:x+radius*0.15,y:y-radius*0.15));p.curve(to:NSPoint(x:x-radius,y:y),controlPoint1:NSPoint(x:x-radius*0.15,y:y-radius*0.15),controlPoint2:NSPoint(x:x-radius*0.15,y:y-radius*0.15));p.curve(to:NSPoint(x:x,y:y+radius),controlPoint1:NSPoint(x:x-radius*0.15,y:y+radius*0.15),controlPoint2:NSPoint(x:x-radius*0.15,y:y+radius*0.15));p.close();NSColor.white.withAlphaComponent(0.9).setFill();p.fill()
    }
    star(720,700,70);star(590,835,31);star(800,480,27)
    let bridge = NSBezierPath();bridge.move(to:NSPoint(x:230,y:220));bridge.curve(to:NSPoint(x:795,y:220),controlPoint1:NSPoint(x:365,y:335),controlPoint2:NSPoint(x:650,y:335));bridge.lineWidth=15;bridge.lineCapStyle = .round;NSColor.white.withAlphaComponent(0.45).setStroke();bridge.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let names: [String]
    switch size { case 16:names=["icon_16x16.png"];case 32:names=["icon_16x16@2x.png","icon_32x32.png"];case 64:names=["icon_32x32@2x.png"];case 128:names=["icon_128x128.png"];case 256:names=["icon_128x128@2x.png","icon_256x256.png"];case 512:names=["icon_256x256@2x.png","icon_512x512.png"];default:names=["icon_512x512@2x.png"] }
    for name in names { try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name)) }
}
