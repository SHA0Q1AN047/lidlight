import Foundation
func daemonRunning() -> Bool { false }
func rootDomainFlag(_ key: String) -> Bool? { nil }
func powerDescription() -> String { "Battery · 9%" }
@main struct HealthTests {
    static func main() {
        let report = Health.report()
        precondition(report.contains("Service: Offline"))
        precondition(report.contains("Sleep: Unknown"))
        precondition(report.contains("Power: Battery · 9%"))
        precondition(!report.contains("SSH") && !report.contains("FileVault"))
        print("PASS: concise diagnostics preserve unknown state and offline service")
    }
}
