// 生成应用图标和安装器背景图。用法：swift scripts/make-assets.swift
// 输出：Resources/AppIcon.icns、Installer/Resources/background.png、docs/social-preview.png

import AppKit

func render(pixels: Int, points: CGFloat, _ draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    render(pixelsWide: pixels, pixelsHigh: pixels, pointSize: NSSize(width: points, height: points)) { draw(points) }
}

func render(pixelsWide: Int, pixelsHigh: Int, pointSize: NSSize, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = pointSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r, green: g, blue: b, alpha: a)
}

// 闪电：在 unit × unit 的方框内，原点为左下角。
func boltPath(in rect: NSRect) -> NSBezierPath {
    let points: [(CGFloat, CGFloat)] = [
        (0.58, 1.00), (0.12, 0.44), (0.44, 0.44), (0.36, 0.00), (0.88, 0.60), (0.54, 0.60),
    ]
    let path = NSBezierPath()
    for (index, point) in points.enumerated() {
        let p = NSPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
        index == 0 ? path.move(to: p) : path.line(to: p)
    }
    path.close()
    path.lineJoinStyle = .round
    return path
}

// 机身：一块圆角扁盒，Lidlight 的正面。
func slabPath(in rect: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.height * 0.27, yRadius: rect.height * 0.27)
}

func drawIcon(_ s: CGFloat) {
    let u = s / 1024
    let plate = NSBezierPath(roundedRect: NSRect(x: 100*u, y: 100*u, width: 824*u, height: 824*u), xRadius: 185*u, yRadius: 185*u)
    NSGradient(colors: [rgb(0.025, 0.05, 0.075), rgb(0.12, 0.23, 0.25)])!.draw(in: plate, angle: 60)
    let ring = NSBezierPath(ovalIn: NSRect(x: 302*u, y: 365*u, width: 420*u, height: 420*u))
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = rgb(0.42, 0.95, 0.78, 0.7)
    glow.shadowBlurRadius = 38*u
    glow.set()
    rgb(0.5, 0.96, 0.8).setStroke()
    ring.lineWidth = 34*u
    ring.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let laptop = NSBezierPath(roundedRect: NSRect(x: 245*u, y: 245*u, width: 534*u, height: 150*u), xRadius: 28*u, yRadius: 28*u)
    rgb(0.035, 0.075, 0.09).setFill()
    laptop.fill()
    rgb(0.80, 0.92, 0.9).setStroke()
    laptop.lineWidth = 22*u
    laptop.stroke()
    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: 225*u, y: 280*u))
    seam.line(to: NSPoint(x: 799*u, y: 280*u))
    seam.lineWidth = 18*u
    seam.lineCapStyle = .round
    seam.stroke()
}

// 安装器背景：左侧步骤列表下方放一个应用图标，其余透明。
func drawBackground() {
    let transform = NSAffineTransform()
    transform.translateX(by: 30, yBy: 26)
    transform.concat()
    drawIcon(120)
}

// GitHub 社交预览图，1280×640。重要内容离边缘至少 80px，避免被各平台裁掉。
func drawSocialPreview() {
    let canvas = NSRect(x: 0, y: 0, width: 1280, height: 640)
    NSGradient(colors: [rgb(0.04, 0.05, 0.12), rgb(0.09, 0.13, 0.28), rgb(0.17, 0.24, 0.48)])!
        .draw(in: canvas, angle: 35)
    // 图标背后的一团光，把它从同色系的背景里托出来。
    NSGradient(colors: [rgb(0.42, 0.55, 1.0, 0.38), rgb(0.42, 0.55, 1.0, 0)])!
        .draw(fromCenter: NSPoint(x: 290, y: 320), radius: 0, toCenter: NSPoint(x: 290, y: 320), radius: 380, options: [])

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 96, yBy: 126)
    transform.concat()
    drawIcon(388)
    NSGraphicsContext.restoreGraphicsState()

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: rgb(1, 1, 1, alpha),
            .kern: kern,
        ])
    }

    let left: CGFloat = 540
    text("Lidlight", size: 88, weight: .bold, alpha: 1, kern: -1.5).draw(at: NSPoint(x: left - 4, y: 356))
    text("Keep a plugged-in MacBook running", size: 34, weight: .regular, alpha: 0.82).draw(at: NSPoint(x: left, y: 292))
    text("with the lid closed.", size: 34, weight: .regular, alpha: 0.82).draw(at: NSPoint(x: left, y: 248))

    var x = left
    for label in ["No external display", "Auto-off on battery", "Menu bar app"] {
        let chip = text(label, size: 20, weight: .medium, alpha: 0.92)
        let size = chip.size()
        let rect = NSRect(x: x, y: 158, width: size.width + 32, height: 42)
        rgb(1, 1, 1, 0.13).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 21, yRadius: 21).fill()
        chip.draw(at: NSPoint(x: rect.minX + 16, y: rect.midY - size.height / 2))
        x = rect.maxX + 12
    }
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = render(pixels: points * scale, points: CGFloat(points), drawIcon)
        let suffix = scale == 2 ? "@2x" : ""
        write(rep, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png").path)
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)

let paneSize = NSSize(width: 620, height: 418)
write(render(pixelsWide: 1240, pixelsHigh: 836, pointSize: paneSize, drawBackground),
      to: "Installer/Resources/background.png")
write(render(pixelsWide: 1280, pixelsHigh: 640, pointSize: NSSize(width: 1280, height: 640), drawSocialPreview),
      to: "docs/social-preview.png")

// 预览用的大图，不入库。
if CommandLine.arguments.contains("--preview") {
    try? fm.createDirectory(atPath: "build", withIntermediateDirectories: true)
    write(render(pixels: 512, points: 512, drawIcon), to: "build/icon-preview.png")
}
print("assets written")
