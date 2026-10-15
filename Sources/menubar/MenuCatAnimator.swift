import AppKit

final class MenuCatAnimator {
    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private(set) var frame = 0
    var isAnimating: Bool { timer != nil }
    private var fps: Double = 0
    private var warning = false
    private var thermal = CatThermal()
    private var status = "Lidlight"
    private(set) var usage: Double?
    deinit { timer?.invalidate() }
    func attach(_ button: NSStatusBarButton?) { self.button = button; render() }
    func update(usage newValue: Double?, enabled: Bool, reduceMotion: Bool) {
        if let value = newValue, value.isFinite, (0...1).contains(value) {
            usage = usage.map { $0 * 0.45 + value * 0.55 } ?? value
        } else { usage = nil }
        let speed = enabled && !reduceMotion ? usage.map(CatPace.framesPerSecond) ?? 0 : 0
        if speed != fps {
            timer?.invalidate(); timer = nil; fps = speed
            if speed > 0 {
                let tick = Timer(timeInterval: 1 / speed, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.frame = (self.frame + 1) % MenuBarIcon.frameCount
                    self.renderFrame()
                }
                tick.tolerance = min(0.02, 0.1 / speed)
                RunLoop.main.add(tick, forMode: .common)
                timer = tick
            } else { frame = 0 }
        }
        render()
    }
    func setStatus(_ value: String, lowBattery: Bool) { status = value; warning = lowBattery; render() }
    func updateThermal(high: Bool, now: Date = Date()) { thermal.update(high: high, now: now); render() }
    func pause() { update(usage: nil, enabled: false, reduceMotion: true) }
    private func renderFrame() {
        guard let button else { return }
        let image = MenuBarIcon.cat(frame: frame, lowBattery: warning, sweating: thermal.sweating)
        if button.image !== image { button.image = image }
    }
    private func render() {
        renderFrame()
        guard let button else { return }
        let gait = !isAnimating ? "Still" : (usage ?? 0) <= 0.1 ? "Walking" : "Running"
        let tooltip = status + " · " + gait + (thermal.sweating ? " · Sweating: sustained high thermal pressure" : "") + (usage.map { String(format: " · CPU %.0f%%", $0 * 100) } ?? " · CPU unavailable")
        if button.toolTip != tooltip {
            button.toolTip = tooltip
            button.setAccessibilityLabel(tooltip)
        }
    }
}
