import AppKit
import SwiftUI

@main struct Preview {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        NSImage(contentsOfFile: "Resources/AppIcon.icns")?.setName(NSImage.Name("AppIcon"))
        let state = DashboardState()
        state.awake = true
        state.running = true
        state.mode = CommandLine.arguments.contains("--battery") ? 1 : 0
        if CommandLine.arguments.contains("--offline") { state.running = false; state.awake = nil; state.mode = nil }
        state.details = CommandLine.arguments.contains("--details")
        state.power = "Power Adapter · 100%"
        let view = NSHostingView(rootView: Dashboard(state: state, select: { _ in }, toggleDim: {}, copyDiagnostics: {}, quit: {}))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments.last.flatMap { $0.hasSuffix(".png") ? $0 : nil } ?? "docs/lidlight-preview.png"))
    }
}
