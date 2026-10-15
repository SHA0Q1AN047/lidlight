import Foundation

struct QuotaPoint: Codable, Equatable {
    let date: Date
    let id: String
    let minutes: Int
    let reset: Date
    let used: Double
}
struct QuotaTrend: Equatable {
    let drop: Double
    let minutes: Double
    var perHour: Double { drop * 60 / minutes }
    var label: String { String(format: "%.1f points used in %.0f min · %.1f points/hour", drop, minutes, perHour) }
    var shortLabel: String { String(format: "%.1f quota points used / %.0f min",drop,minutes) }
}
/// Only quota readings are retained locally; no conversation or account identifiers.
final class QuotaHistory {
    private(set) var points: [QuotaPoint]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        points = defaults.data(forKey: "quotaHistory").flatMap { try? JSONDecoder().decode([QuotaPoint].self, from: $0) } ?? []
        points = Array(points.filter { $0.used.isFinite && (0...100).contains($0.used) }.suffix(600))
    }
    func record(_ windows: [QuotaWindow], now: Date = Date()) {
        points.removeAll { now.timeIntervalSince($0.date) > 86400 || $0.date > now }
        for window in windows where window.used.isFinite && (0...100).contains(window.used) && window.resetsAt > now {
            // Manual refresh spam must not inflate sample count or evidence.
            if let last = points.last(where: { $0.id == window.id }), now.timeIntervalSince(last.date) < 60 { continue }
            points.append(QuotaPoint(date: now, id: window.id, minutes: window.minutes, reset: window.resetsAt, used: window.used))
        }
        points = Array(points.suffix(600))
        if let data = try? JSONEncoder().encode(points) { defaults.set(data, forKey: "quotaHistory") }
    }
    func trend(for window: QuotaWindow, now: Date = Date()) -> QuotaTrend? {
        let recent = points.filter { $0.id == window.id && $0.minutes == window.minutes && $0.date <= now && now.timeIntervalSince($0.date) <= 3600 }
        var segment: [QuotaPoint] = []
        for point in recent {
            guard abs(point.reset.timeIntervalSince(window.resetsAt)) <= 1 else { segment = []; continue }
            if let last = segment.last, point.used < last.used || point.date.timeIntervalSince(last.date) > 15 * 60 { segment = [] }
            segment.append(point)
        }
        guard segment.count >= 3, let first = segment.first, let last = segment.last,
              now.timeIntervalSince(last.date) <= 10 * 60, last.used <= window.used, window.resetsAt > now else { return nil }
        let duration = last.date.timeIntervalSince(first.date) / 60
        guard duration >= 10 else { return nil }
        return QuotaTrend(drop: max(0,last.used-first.used), minutes: duration)
    }
    func clear() { points = []; defaults.removeObject(forKey: "quotaHistory") }
}
