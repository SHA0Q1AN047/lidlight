import Foundation

struct DaemonOptions: Codable {
    var batteryLimit = 10
    var acOnly = false
    var startupAuto = false
    var presentation = false
    var deadline: Double = 0
    var resumeMode: UInt64 = 0
    var oneShot = false
}

enum PowerPolicy {
    static func lowBattery(previous: Bool, percent: Int?, onAC: Bool, threshold: Int) -> Bool {
        guard !onAC, let percent else { return false }
        if percent <= threshold { return true }
        if percent >= min(100, threshold + 5) { return false }
        return previous
    }
    static func awake(mode: UInt64, onAC: Bool, lowBattery: Bool, acOnly: Bool) -> Bool {
        if mode == 2 { return false }
        if mode == 0 || acOnly { return onAC }
        return mode == 1 && !lowBattery
    }
    static func scheduled(now: Date, start: Int, end: Int, weekdays: Bool, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let overnight = start > end
        let anchor = overnight && minute < end ? calendar.date(byAdding: .day, value: -1, to: now)! : now
        let day = calendar.component(.weekday, from: anchor)
        guard !weekdays || (2...6).contains(day), start != end else { return false }
        return overnight ? minute >= start || minute < end : minute >= start && minute < end
    }
    static func ruleMode(base: Int, apps: Bool, display: Bool, schedule: Bool, paused: Bool) -> Int {
        !paused && (apps || display || schedule) ? 1 : base
    }
    static func minutesLeft(deadline: Double, now: Double) -> Int {
        max(0, Int(ceil((deadline - now) / 60)))
    }
}
