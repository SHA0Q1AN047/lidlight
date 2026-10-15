import Foundation
@main struct PowerPolicyTests {
    static func main() {
        for threshold in [10, 20, 50] {
            precondition(PowerPolicy.lowBattery(previous: false, percent: threshold, onAC: false, threshold: threshold))
            precondition(PowerPolicy.lowBattery(previous: true, percent: threshold + 4, onAC: false, threshold: threshold))
            precondition(!PowerPolicy.lowBattery(previous: true, percent: threshold + 5, onAC: false, threshold: threshold))
            precondition(!PowerPolicy.lowBattery(previous: true, percent: threshold, onAC: true, threshold: threshold))
        }
        for mode in UInt64(0)...2 {
            precondition(!PowerPolicy.awake(mode: mode, onAC: false, lowBattery: true, acOnly: true))
            precondition(!PowerPolicy.awake(mode: mode, onAC: false, lowBattery: true, acOnly: false))
        }
        precondition(PowerPolicy.awake(mode: 1, onAC: false, lowBattery: false, acOnly: false))
        precondition(!PowerPolicy.awake(mode: 2, onAC: true, lowBattery: false, acOnly: false))
        precondition(PowerPolicy.ruleMode(base: 0, apps: true, display: false, schedule: false, paused: false) == 1)
        precondition(PowerPolicy.ruleMode(base: 2, apps: true, display: true, schedule: true, paused: true) == 2)
        precondition(PowerPolicy.ruleMode(base: 0, apps: false, display: false, schedule: false, paused: false) == 0)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int, _ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        // Friday overnight includes Saturday morning; Sunday night does not start a weekday session.
        precondition(PowerPolicy.scheduled(now: date(17, 1), start: 22 * 60, end: 2 * 60, weekdays: true, calendar: calendar))
        precondition(!PowerPolicy.scheduled(now: date(19, 1), start: 22 * 60, end: 2 * 60, weekdays: true, calendar: calendar))
        precondition(!PowerPolicy.scheduled(now: date(16, 18), start: 1080, end: 1080, weekdays: false, calendar: calendar))
        precondition(PowerPolicy.scheduled(now: date(16, 18), start: 1080, end: 1200, weekdays: true, calendar: calendar))
        precondition(!PowerPolicy.scheduled(now: date(16, 20), start: 1080, end: 1200, weekdays: true, calendar: calendar))
        precondition(PowerPolicy.minutesLeft(deadline: 101, now: 100) == 1)
        precondition(PowerPolicy.minutesLeft(deadline: 100, now: 101) == 0)
        let config = DaemonOptions()
        precondition(try! JSONDecoder().decode(DaemonOptions.self, from: JSONEncoder().encode(config)).batteryLimit == 10)
        print("PASS: threshold hysteresis, AC-only, mode safety, rule priority, overnight weekdays, timer boundaries and settings persistence")
    }
}
