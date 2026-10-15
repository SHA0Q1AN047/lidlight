import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct PreviewMenuBar {
    static func bitmap(width: Int, height: Int, draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0,y: 0,width: width,height: height).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    static func gif(_ name: String, fps: Double) {
        let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "docs/" + name) as CFURL, UTType.gif.identifier as CFString, 6, nil)!
        CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<6 {
            let rep = bitmap(width: 192, height: 144) {
                MenuBarIcon.cat(frame: frame).draw(in: NSRect(x: 24,y: 18,width: 144,height: 108))
            }
            CGImageDestinationAddImage(destination,rep.cgImage!,[kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1/fps,kCGImagePropertyGIFUnclampedDelayTime: 1/fps]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
    }
    static func main() {
        let rep = bitmap(width: 720,height: 168) {
            for frame in 0..<6 {
                MenuBarIcon.cat(frame: frame).draw(in: NSRect(x: 12+frame*120,y: 60,width: 96,height: 72))
                ("Frame \(frame+1)" as NSString).draw(at: NSPoint(x: 22+frame*120,y: 24),withAttributes: [.font:NSFont.systemFont(ofSize: 13),.foregroundColor:NSColor.black])
            }
        }
        try! rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: "docs/menubar-pixels.png"))
        let heat = bitmap(width: 360,height: 150) {
            MenuBarIcon.cat(frame: 0).draw(in: NSRect(x: 25,y: 50,width: 120,height: 90))
            MenuBarIcon.cat(frame: 0,sweating: true).draw(in: NSRect(x: 205,y: 50,width: 120,height: 90))
            ("Normal" as NSString).draw(at: NSPoint(x: 50,y: 20),withAttributes: [.font:NSFont.systemFont(ofSize: 14),.foregroundColor:NSColor.black])
            ("Sustained heat" as NSString).draw(at: NSPoint(x: 210,y: 20),withAttributes: [.font:NSFont.systemFont(ofSize: 14),.foregroundColor:NSColor.black])
        }
        try! heat.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: "docs/cat-thermal.png"))
        gif("cat-walking.gif",fps: 2)
        gif("cat-running.gif",fps: 12)
        var unique = Set<Data>()
        for frame in 0..<6 {
            let image = MenuBarIcon.cat(frame: frame)
            precondition(image.isTemplate && image.size == NSSize(width: 24,height: 18))
            precondition(image === MenuBarIcon.cat(frame: frame))
            unique.insert(image.tiffRepresentation!)
            precondition(image.tiffRepresentation != MenuBarIcon.cat(frame: frame,lowBattery: true).tiffRepresentation)
        }
        precondition(unique.count == 6)
        print("PASS: six distinct cached template sprites, fixed dimensions, low-battery badge and walking/running GIF previews")
    }
}
