import AppKit
import SwiftUI

private final class PreviewReleaseProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: [[String: Any]] = [["tag_name": "v1.10.0", "prerelease": false, "draft": false,
            "body": "A sample release showing the update layout. Improved reliability and refreshed controls.",
            "assets": [["name": "Lidlight.pkg", "state": "uploaded", "size": 2_000_000,
                        "digest": "sha256:" + String(repeating: "0", count: 64),
                        "browser_download_url": "https://github.com/SHA0Q1AN047/lidlight/releases/download/v1.10.0/Lidlight.pkg"]]]]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Preview {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(CommandLine.arguments.contains("--interactive") ? .regular : .prohibited)
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
        features.supply.update(ac: true,percent: 80)
        if CommandLine.arguments.contains("--supply-warning") {
            for second in stride(from: 0,through: 180,by: 5) {
                features.supply.update(ac: true,percent: second == 180 ? 78 : 80,now: Date().addingTimeInterval(Double(second-180)))
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--page"), CommandLine.arguments.count > index + 1 { features.page = CommandLine.arguments[index + 1] }
        let quota = CodexQuota(history: QuotaHistory(defaults: UserDefaults(suiteName: "com.lidlight.preview.quota")!))
        quota.history.clear()
        quota.windows = [QuotaWindow(id: "primary", used: 25, minutes: 300, resetsAt: Date().addingTimeInterval(3600)), QuotaWindow(id: "secondary", used: 10, minutes: 10080, resetsAt: Date().addingTimeInterval(86400))]
        quota.updated = Date()
        if CommandLine.arguments.contains("--weather-low") { quota.windows = [QuotaWindow(id: "primary", used: 88, minutes: 300, resetsAt: Date().addingTimeInterval(3600)), QuotaWindow(id: "secondary", used: 65, minutes: 10080, resetsAt: Date().addingTimeInterval(86400))] }
        if CommandLine.arguments.contains("--weather-empty") { quota.windows[0] = QuotaWindow(id: "primary", used: 100, minutes: 300, resetsAt: Date().addingTimeInterval(3600)) }
        if CommandLine.arguments.contains("--weather-error") { quota.message = "Sample connection failure" }
        if CommandLine.arguments.contains("--weather-reset") { quota.windows[0] = QuotaWindow(id: "primary", used: 100, minutes: 300, resetsAt: Date().addingTimeInterval(-1)) }
        if CommandLine.arguments.contains("--weather-loading") { quota.windows = []; quota.busy = true }

        if CommandLine.arguments.contains("--quota-trend") {
            for step in 0..<4 {
                let windows = quota.windows.map { QuotaWindow(id: $0.id,used: max(0,$0.used-Double(3-step)*2),minutes: $0.minutes,resetsAt: $0.resetsAt) }
                quota.history.record(windows,now: Date().addingTimeInterval(Double(step-3)*300))
            }
        }
        app.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewReleaseProtocol.self]
        let updater = AppUpdater(currentVersion: "1.9.3", defaults: UserDefaults(suiteName: "com.lidlight.preview.updater")!, session: URLSession(configuration: configuration), openInstaller: { _ in false })
        if CommandLine.arguments.contains("--available") { updater.check(force: true) }
        let monitor = CommandLine.arguments.contains("--live-performance") ? PerformanceMonitor() : PerformanceMonitor(readSample: {
            SensorSample(date: Date(), watts: 18.4, cpuCelsius: CommandLine.arguments.contains("--wide-values") ? 108.8 : 48.2, cpuKey: "Sample", fans: CommandLine.arguments.contains("--fanless") ? [] : [FanReading(index: 0, rpm: 2320), FanReading(index: 1, rpm: 2340)], fanCount: CommandLine.arguments.contains("--fanless") ? 0 : 2)
        })
        monitor.refresh(visible: true, includeProcesses: features.page == "performance")
        let verification = InstallVerification(runningVersion: "1.9.3",defaults: UserDefaults(suiteName: "com.lidlight.preview.install")!)
        verification.apply(InstallStatus(running: "1.9.3",installed: "1.9.3",service: "1.9.3",serviceRunning: true))
        let view = NSHostingView(rootView: Dashboard(state: state, features: features, quota: quota, updater: updater, monitor: monitor, verification: verification, select: { _ in }, toggleDim: {}, copyDiagnostics: {}, quit: {}).environment(\.lidlightOpaquePreview, CommandLine.arguments.contains("--opaque")))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        if CommandLine.arguments.contains("--interactive") {
            window.title = "Lidlight · Liquid Glass Preview"
            window.styleMask = [.titled, .closable]
            window.center()
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            app.run()
            return
        }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if CommandLine.arguments.contains("--trend") {
            for _ in 0..<6 {
                monitor.refresh(visible: true, includeProcesses: features.page == "performance")
                RunLoop.main.run(until: Date().addingTimeInterval(2.05))
            }
        }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments.last.flatMap { $0.hasSuffix(".png") ? $0 : nil } ?? "docs/lidlight-preview.png"))
    }
}
