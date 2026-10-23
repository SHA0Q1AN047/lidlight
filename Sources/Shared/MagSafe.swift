import Foundation

enum MagSafePolicy {
    static func night(minute: Int, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        return start < end ? (start..<end).contains(minute) : minute >= start || minute < end
    }
    // 0 system, 1 off, 2 running (daemon alternates amber/off), 3 idle green.
    static func mode(enabled: Bool, nightEnabled: Bool, minute: Int, start: Int, end: Int, running: Bool?, dark: Bool) -> UInt64 {
        if dark || nightEnabled && night(minute: minute, start: start, end: end) { return 1 }
        guard enabled, let running else { return 0 }
        return running ? 2 : 3
    }
}
struct MagSafeStatus: Codable {
    static let path = "/var/run/lidlight-magsafe.json"
    var updated = Date()
    var supported = false
    var message = "MagSafe LED unavailable"
}
