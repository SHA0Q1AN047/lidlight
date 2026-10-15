import Foundation
@main struct CodexQuotaTests {
    static func main() throws {
        let legacy: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 65, "windowDurationMins": 300, "resetsAt": 2000000000], "secondary": NSNull()]]
        let windows = try CodexQuota.parse(legacy)
        precondition(windows.count == 1 && windows[0].remaining == 35 && windows[0].label == "5-hour quota")
        let multiple: [String: Any] = ["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 10.0, "windowDurationMins": 10080, "resetsAt": 2000000000.0]]], "rateLimits": ["primary": ["usedPercent": 99, "windowDurationMins": 300, "resetsAt": 2000000000]]]
        let selected = try CodexQuota.parse(multiple)
        precondition(selected[0].remaining == 90)
        precondition(selected[0].label == "Weekly quota")
        do { _ = try CodexQuota.parse([:]); preconditionFailure("Missing quota must not become zero usage") } catch {}
        do { _ = try CodexQuota.parse(["rateLimits": ["primary": NSNull()]]); preconditionFailure("Null quota must be unavailable") } catch {}
        do {
            _ = try CodexQuota.parse(["rateLimits": ["primary": ["usedPercent": -1,"windowDurationMins": 300,"resetsAt": 2000000000]]])
            preconditionFailure("Negative usage must not claim full quota or trigger recovery")
        } catch {}
        print("PASS: remaining percentages, multi-bucket priority, dynamic windows and missing quota")
        if CommandLine.arguments.contains("--live") {
            for window in try CodexQuota.fetch() { print("\(window.label): \(window.remaining)% remaining") }
        }
    }
}
