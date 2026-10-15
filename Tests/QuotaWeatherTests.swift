import Foundation

@main struct Tests {
    static func main() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func window(_ left: Double, reset: Date? = nil) -> QuotaWindow {
            QuotaWindow(id: "test", used: 100-left, minutes: 300, resetsAt: reset ?? now.addingTimeInterval(3600))
        }
        func expect(_ value: Bool, _ label: String) { precondition(value, label) }
        for (left, sky): (Double, QuotaSky) in [(100,.sunny),(50,.sunny),(49,.cloudy),(49.6,.sunny),(20,.cloudy),(19,.sunset),(19.6,.cloudy),(0.1,.sunset),(0,.sleeping)] {
            expect(QuotaSky.window(window(left), now: now) == sky, "Threshold \(left)")
        }
        expect(QuotaSky.window(window(0, reset: now), now: now) == .resetting, "Expired zero must not imply a refreshed balance")
        func overview(_ windows: [QuotaWindow], enabled: Bool = true, busy: Bool = false, failed: Bool = false, updated: Date? = now) -> QuotaSky {
            QuotaSky.overview(windows: windows, enabled: enabled, busy: busy, failed: failed, updated: updated, now: now)
        }
        expect(overview([window(80),window(5)]) == .sunset, "Tightest window controls overview")
        expect(overview([window(80),window(0)]) == .sleeping, "Weekly exhaustion cannot be hidden by a sunny 5h window")
        expect(overview([window(80),window(80,reset: now)]) == .resetting, "Expired window has unknown new balance")
        expect(overview([], busy: true) == .checking, "Initial loading")
        expect(overview([]) == .unavailable, "Missing data is not zero")
        expect(overview([window(80)], failed: true) == .unavailable, "Cached readings cannot claim sunny weather")
        expect(overview([window(80)], updated: nil) == .unavailable, "Undated data")
        expect(overview([window(80)], updated: now.addingTimeInterval(-901)) == .unavailable, "Stale data")
        expect(overview([window(80)], enabled: false, busy: true) == .off, "Disabled overrides cached data and loading")
        expect(overview([window(80)], busy: true) == .sunny, "Refresh retains a recent known reading")
        expect(QuotaResetCountdown.label(reset: now, now: now) == "Reset pending", "Expired reset stays pending")
        expect(QuotaResetCountdown.label(reset: now.addingTimeInterval(1), now: now) == "Resets in 1m", "Never display zero before reset")
        expect(QuotaResetCountdown.label(reset: now.addingTimeInterval(3660), now: now) == "Resets in 1h 1m", "Hour countdown")
        expect(QuotaResetCountdown.label(reset: now.addingTimeInterval(90000), now: now) == "Resets in 1d 1h", "Day countdown")
        var sprites = Set<String>()
        for sky in QuotaSky.allCases {
            let pixels = QuotaWeatherSprite.pixels(sky)
            expect(pixels.count == 16 && pixels.allSatisfy { $0.count == 16 }, "Sprite bounds")
            expect(pixels.flatMap { $0 }.allSatisfy { (0...7).contains($0) }, "Palette bounds")
            expect(pixels.flatMap { $0 }.contains { $0 != 0 }, "Nonempty icon")
            sprites.insert(pixels.flatMap { $0 }.map(String.init).joined())
        }
        expect(sprites.count == QuotaSky.allCases.count, "Every status has a distinct sprite")
        print("PASS: quota weather thresholds, multi-window limits, reset, loading, cached/stale/off states and eight distinct pixel sprites")
    }
}
