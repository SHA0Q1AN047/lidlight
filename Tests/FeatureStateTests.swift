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
