import Foundation

/// Observes sustained battery loss on AC; it cannot diagnose charger wattage.
struct SupplyAssessment {
    private var points: [(Date, Int)] = []
    private(set) var falling = false
    private(set) var summary = "Connect a power adapter to check supply."
    mutating func update(ac: Bool, percent: Int?, now: Date = Date()) {
        guard ac, let percent, (0...100).contains(percent) else {
            points.removeAll(); falling = false
            summary = ac ? "Battery data unavailable on this Mac." : "Connect a power adapter to check supply."
            return
        }
        if let last = points.last, now.timeIntervalSince(last.0) > 30 || now < last.0 || percent > last.1 {
            points.removeAll(); falling = false
        }
        if points.last.map({ now.timeIntervalSince($0.0) >= 5 }) ?? true { points.append((now,percent)) }
        points = Array(points.filter { now.timeIntervalSince($0.0) <= 300 }.suffix(61))
        falling = points.contains { now.timeIntervalSince($0.0) >= 180 && $0.1 - percent >= 2 }
        summary = falling ? "Battery falling on AC · Check adapter, cable or load."
            : "Monitoring battery on AC · No sustained drop detected."
    }
}
