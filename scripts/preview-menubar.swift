import AppKit
@main struct PreviewMenuBar {
    static func main() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 240,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 600, height: 240).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        for (index, state) in [true, false, nil].enumerated() {
            let image = MenuBarIcon.image(awake: state)
            image.draw(in: NSRect(x: 40 + index * 200, y: 65, width: 120, height: 108))
            let label = ["Awake", "Sleep", "Unknown"][index]
            (label as NSString).draw(at: NSPoint(x: 55 + index * 200, y: 28), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/menubar-pixels.png"))
        precondition(MenuBarIcon.awake.isTemplate && MenuBarIcon.asleep.isTemplate && MenuBarIcon.unknown.isTemplate)
        precondition(MenuBarIcon.awake.size == NSSize(width: 20, height: 18))
        precondition(MenuBarIcon.awake.tiffRepresentation != MenuBarIcon.asleep.tiffRepresentation)
        print("PASS: template icons, fixed size and distinct awake/sleep states")
    }
}
