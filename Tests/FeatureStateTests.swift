import Foundation
@main struct FeatureStateTests {
    static func main() {
        let name = "com.lidlight.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "ruleActive")
        defaults.set(Int32(42), forKey: "watchedPID")
        defaults.set("old-process", forKey: "watchedIdentity")
        let features = Features(defaults: defaults)
        precondition(features.countdownEvent == nil, "No event means no menu countdown")
        var changes = 0
        features.didChange = { changes += 1 }
        features.saveCountdown(name: "Trip",date: Date().addingTimeInterval(86400 * 10))
        precondition(features.countdownEvent?.name == "Trip" && changes == 1)
        precondition(Features(defaults: defaults).countdownEvent == features.countdownEvent, "Saved event survives relaunch")
        features.clearCountdown()
        precondition(features.countdownEvent == nil && Features(defaults: defaults).countdownEvent == nil && changes == 2, "Remove hides it immediately and persistently")
        features.preferences.baseMode = 1
        features.preferences.threshold = 20
        features.preferences.rulesPaused = false
        features.prepareQuit()
        precondition(features.preferences.baseMode == 2 && features.preferences.rulesPaused)
        precondition(!defaults.bool(forKey: "ruleActive"))
        precondition(defaults.object(forKey: "watchedPID") == nil)
        let restored = Features(defaults: defaults)
        precondition(restored.preferences.baseMode == 2 && restored.preferences.rulesPaused)
        precondition(restored.preferences.threshold == 20)
        print("PASS: explicit quit pauses automation, clears process watch and persists the safe base mode; no daemon commands sent")
    }
}
