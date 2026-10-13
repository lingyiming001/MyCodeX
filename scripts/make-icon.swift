import AppKit
import Foundation
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let extent = CGFloat(pixels)
        let rect = NSRect(x: extent * 0.04, y: extent * 0.04, width: extent * 0.92, height: extent * 0.92)
        let path = NSBezierPath(roundedRect: rect, xRadius: extent * 0.22, yRadius: extent * 0.22)
        NSGradient(starting: NSColor(red: 0.1, green: 0.22, blue: 0.24, alpha: 1), ending: NSColor(red: 0.03, green: 0.1, blue: 0.12, alpha: 1))!.draw(in: path, angle: 45)
        let star = NSBezierPath()
        let center = CGPoint(x: extent * 0.5, y: extent * 0.51)
        for i in 0..<8 {
            let angle = Double(i) * Double.pi / 4
            let radius = extent * (i % 2 == 0 ? 0.32 : 0.11)
            let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if i == 0 { star.move(to: point) } else { star.line(to: point) }
        }
        star.close()
        NSColor(red: 0.58, green: 0.94, blue: 0.81, alpha: 1).setFill(); star.fill()
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name))
    }
}
