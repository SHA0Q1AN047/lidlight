import Foundation

struct DayCountdown: Codable, Equatable {
    let name: String
    let year: Int
    let month: Int
    let day: Int
    init?(name: String, date: Date, calendar: Calendar = .current) {
        let clean = name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !clean.isEmpty else { return nil }
        self.name = String(clean.prefix(80))
        year = calendar.component(.year,from: date)
        month = calendar.component(.month,from: date)
        day = calendar.component(.day,from: date)
    }
    func targetDate(calendar: Calendar = .current) -> Date? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let date = calendar.date(from: DateComponents(year: year,month: month,day: day)),
              calendar.component(.year,from: date) == year,
              calendar.component(.month,from: date) == month,
              calendar.component(.day,from: date) == day else { return nil }
        return date
    }
    func dayLabel(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let target = targetDate(calendar: calendar),
              let days = calendar.dateComponents([.day],from: calendar.startOfDay(for: now),to: calendar.startOfDay(for: target)).day else { return nil }
        return days == 0 ? "Today" : days > 0 ? "\(days)d" : "\(-days)d ago"
    }
    func label(now: Date = Date(), calendar: Calendar = .current, compact: Bool = false) -> String {
        guard let days = dayLabel(now: now,calendar: calendar) else { return "" }
        let title = compact && name.count > 12 ? String(name.prefix(12)) + "…" : name
        return title + " · " + days
    }
    static func load(defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: "dayCountdown"),
              let event = try? JSONDecoder().decode(Self.self,from: data), event.targetDate() != nil else { return nil }
        return event
    }
}
