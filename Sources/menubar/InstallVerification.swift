import Foundation
import notify

struct InstallStatus: Equatable {
    let running: String
    let installed: String?
    let service: String?
    let serviceRunning: Bool
    var verified: Bool { running == installed && running == service && serviceRunning }
    var summary: String {
        if let installed, installed != running { return "Running and installed app versions differ" }
        if installed == nil { return "Installed app could not be verified" }
        if !serviceRunning { return "Background service offline" }
        if service == nil { return "Background service version unverified" }
        if service != running { return "App and background service versions differ" }
        return "\(running) verified · Service healthy"
    }
}
final class InstallVerification: ObservableObject {
    @Published private(set) var status: InstallStatus?
    @Published private(set) var updateConfirmed = false
    let runningVersion: String
    private let defaults: UserDefaults
    private var token: Int32 = -1
    private var busy = false
    private var lastProbe = -Double.infinity
    init(runningVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown", defaults: UserDefaults = .standard) {
        self.runningVersion = runningVersion; self.defaults = defaults
        if notify_register_check("com.lidlight.version-request",&token) != NOTIFY_STATUS_OK { token = -1 }
    }
    deinit { if token >= 0 { notify_cancel(token) } }
    func refresh(serviceRunning: Bool) {
        let uptime = ProcessInfo.processInfo.systemUptime
        guard !busy, uptime-lastProbe >= 5 else { return }
        lastProbe = uptime
        busy = true
        let nonce = UInt64.random(in: 1...UInt64.max)
        if token >= 0 && serviceRunning {
            notify_set_state(token,nonce)
            notify_post("com.lidlight.version-request")
        }
        let running = runningVersion
        // A fresh challenge prevents old receipts and PID reuse from confirming an update.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let disk = (try? Data(contentsOf: URL(fileURLWithPath: "/Applications/Lidlight.app/Contents/Info.plist")))
                .flatMap { try? PropertyListSerialization.propertyList(from: $0,format: nil) as? [String:Any] }?["CFBundleShortVersionString"] as? String
            let version = ServiceReceipt.verifiedVersion(nonce: nonce)
            DispatchQueue.main.async {
                self?.apply(InstallStatus(running: running,installed: disk,service: version,serviceRunning: serviceRunning))
                self?.busy = false
            }
        }
    }
    func apply(_ value: InstallStatus) {
        status = value
        if value.verified && defaults.string(forKey: "pendingUpdateVersion") == runningVersion {
            defaults.removeObject(forKey: "pendingUpdateVersion")
            defaults.set(runningVersion,forKey: "lastVerifiedUpdate")
        }
        updateConfirmed = value.verified && defaults.string(forKey: "lastVerifiedUpdate") == runningVersion
    }
}
