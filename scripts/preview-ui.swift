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
        let features = Features(defaults: UserDefaults(suiteName: "com.lidlight.preview")!)
        features.reason = "Automatic · power adapter connected"
        features.nextAction = "Unplugging allows normal sleep."
        if let index = CommandLine.arguments.firstIndex(of: "--page"), CommandLine.arguments.count > index + 1 { features.page = CommandLine.arguments[index + 1] }
        let quota = CodexQuota()
        quota.windows = [QuotaWindow(id: "primary", used: 25, minutes: 300, resetsAt: Date().addingTimeInterval(3600)), QuotaWindow(id: "secondary", used: 10, minutes: 10080, resetsAt: Date().addingTimeInterval(86400))]
        quota.updated = Date()
        let view = NSHostingView(rootView: Dashboard(state: state, features: features, quota: quota, select: { _ in }, toggleDim: {}, copyDiagnostics: {}, quit: {}))
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
