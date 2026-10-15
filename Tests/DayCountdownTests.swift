import Foundation

@main struct Tests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: year,month: month,day: day,hour: hour))!
        }
        let event = DayCountdown(name: "  Trip\n to Japan  ",date: date(2026,3,9),calendar: calendar)!
        precondition(event.name == "Trip to Japan")
        precondition(event.dayLabel(now: date(2026,3,7,23),calendar: calendar) == "2d", "Calendar days, not 48-hour intervals across DST")
        precondition(event.dayLabel(now: date(2026,3,9,1),calendar: calendar) == "Today")
        precondition(event.dayLabel(now: date(2026,3,10),calendar: calendar) == "1d ago")
        precondition(DayCountdown(name: " \n ",date: Date()) == nil)
        let leap = DayCountdown(name: "Leap day",date: date(2028,2,29),calendar: calendar)!
        precondition(leap.dayLabel(now: date(2028,2,28),calendar: calendar) == "1d")
        let long = DayCountdown(name: String(repeating: "貓",count: 100),date: Date())!
        precondition(long.name.count == 80 && long.label(compact: true).hasPrefix(String(repeating: "貓",count: 12) + "…"))
        let defaults = UserDefaults(suiteName: "com.lidlight.tests.countdown.\(UUID().uuidString)")!
        precondition(DayCountdown.load(defaults: defaults) == nil, "Fresh install has no event")
        defaults.set(try JSONEncoder().encode(event),forKey: "dayCountdown")
        precondition(DayCountdown.load(defaults: defaults) == event, "Event persists across restart")
        defaults.removeObject(forKey: "dayCountdown")
        precondition(DayCountdown.load(defaults: defaults) == nil, "Remove hides event")
        defaults.set(Data("broken".utf8),forKey: "dayCountdown")
        precondition(DayCountdown.load(defaults: defaults) == nil, "Invalid saved data never appears")
        defaults.removeObject(forKey: "dayCountdown")
        print("PASS: calendar-day countdown, DST, leap day, today/past, empty name, Unicode truncation, persistence and removal")
    }
}
