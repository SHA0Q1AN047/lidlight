import Foundation

struct CatThermal {
    private(set) var since: Date?
    private(set) var sweating = false
    mutating func update(high: Bool, now: Date = Date()) {
        if !high { since = nil; sweating = false; return }
        if since == nil { since = now }
        sweating = now.timeIntervalSince(since!) >= 15
    }
}
