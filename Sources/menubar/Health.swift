import Foundation
import notify

enum Health {
    static func report() -> String {
        var token: Int32 = 0
        var mode = UInt64.max
        var setting = "Unknown"
        if notify_register_check("com.lidlight.state", &token) == NOTIFY_STATUS_OK {
            defer { notify_cancel(token) }
            if notify_get_state(token, &mode) == NOTIFY_STATUS_OK {
                setting = [0: "Automatic", 1: "Stay awake", 2: "Allow sleep"][mode] ?? "Unknown"
            }
        }
        let awake = rootDomainFlag("SleepDisabled").map { $0 ? "Awake" : "Sleep allowed" } ?? "Unknown"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "Hot"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unknown"
        }
        let options = (try? Data(contentsOf: URL(fileURLWithPath: "/var/db/lidlight-options.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) }
            .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? "Unavailable"
        return """
        Lidlight \(version)
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        Service: \(daemonRunning() ? "Running" : "Offline")
        Sleep: \(awake)
        Mode: \(setting)
        Power: \(powerDescription())
        Thermal: \(thermal)
        Options: \(options)
        """
    }
}
