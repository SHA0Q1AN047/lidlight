import Foundation

/// Charge limiting is independent of the low-battery sleep protection setting.
struct ChargeLimitStatus: Codable {
    var updated = Date()
    var hasBattery = false
    var supported = false
    var systemManaged = false
    var enabled = false
    var fullOnce = false
    var paused = false
    var charging = false
    var message = "Checking charging support…"
    static let path = "/var/run/lidlight-charge.json"
}

enum ChargeLimitPolicy {
    static func pause(enabled: Bool, fullOnce: Bool, ac: Bool, percent: Int?, previouslyPaused: Bool) -> Bool {
        guard enabled, !fullOnce, ac, let percent, (0...100).contains(percent) else { return false }
        if percent >= 80 { return true }
        if percent <= 75 { return false }
        return previouslyPaused
    }
}
