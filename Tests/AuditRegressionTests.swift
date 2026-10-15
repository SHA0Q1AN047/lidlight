import Foundation

@main struct Tests {
    static func expect(_ value: Bool, _ text: String) { precondition(value,text) }
    @MainActor static func settle(_ done: () -> Bool) async {
        for _ in 0..<300 { if done() { return }; try! await Task.sleep(nanoseconds: 10_000_000) }
        preconditionFailure("Async regression timed out")
    }
    @MainActor static func main() async throws {
        let suite = "com.lidlight.audit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let window = QuotaWindow(id: "primary",used: 15,minutes: 300,resetsAt: now.addingTimeInterval(3600))
        var clock = 100.0
        let blocked = DispatchSemaphore(value: 0)
        let firstStarted = DispatchSemaphore(value: 0)
        var calls = 0
        let quota = CodexQuota(history: QuotaHistory(defaults: defaults),defaults: defaults,fetch: {
            calls += 1
            if calls == 1 { firstStarted.signal(); blocked.wait() }
            return [window]
        },uptime: { clock })
        quota.refresh()
        let started: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: firstStarted.wait(timeout: .now()+2) == .success) }
        }
        expect(started,"Controlled fetch started")
        quota.enabled = false
        quota.enabled = true
        blocked.signal()
        await settle { !quota.busy && quota.updated != nil }
        expect(calls == 2,"Disable/re-enable discards old in-flight response and starts a new request")
        quota.refresh(); expect(!quota.busy,"Automatic checks stay throttled")
        clock += 300
        quota.refresh(); await settle { !quota.busy }
        expect(calls == 3,"Quota interval uses monotonic uptime")
        func payload(used: Any = 20, minutes: Any = 300, reset: Any = 2_000_000_000) -> [String: Any] {
            ["rateLimits": ["primary": ["usedPercent": used,"windowDurationMins": minutes,"resetsAt": reset]]]
        }
        for bad in [payload(used: true),payload(minutes: 1.5),payload(minutes: true),payload(reset: true),payload(reset: 1e200)] {
            do { _ = try CodexQuota.parse(bad); preconditionFailure("Invalid numeric quota accepted") } catch {}
        }
        var recovery = QuotaRecoveryTracker()
        _ = recovery.observe([QuotaWindow(id: "primary",used: 100,minutes: 300,resetsAt: now.addingTimeInterval(3600))],now: now)
        expect(!recovery.observe([QuotaWindow(id: "primary",used: 0,minutes: 60,resetsAt: now.addingTimeInterval(3600))],now: now),"A plan/window change is not a recovery")
        _ = recovery.observe([QuotaWindow(id: "primary",used: 100,minutes: 60,resetsAt: now.addingTimeInterval(3600))],now: now)
        expect(recovery.observe([QuotaWindow(id: "primary",used: 0,minutes: 60,resetsAt: now.addingTimeInterval(7200))],now: now),"Recovery keeps working after a window-duration change")
        var samples = 0
        let monitor = PerformanceMonitor(readSample: {
            samples += 1
            return SensorSample(date: now.addingTimeInterval(samples == 1 ? 0 : -3600),watts: 10,cpuCelsius: 40,cpuKey: "test",fans: [],fanCount: 0)
        })
        monitor.refresh(visible: true,now: now); await settle { !monitor.busy }
        monitor.refresh(visible: true,now: now.addingTimeInterval(-3600)); await settle { !monitor.busy }
        expect(samples == 2 && monitor.history.count == 1,"Clock moved backward: sample resumes and future history is discarded")
        let processMonitor = PerformanceMonitor(readSample: {
            SensorSample(date: Date(),watts: 10,cpuCelsius: 40,cpuKey: "test",fans: [],fanCount: 0)
        })
        processMonitor.refresh(visible: true,now: now,includeProcesses: true); await settle { !processMonitor.busy }
        processMonitor.refresh(visible: true,now: now.addingTimeInterval(2),includeProcesses: true); await settle { !processMonitor.busy }
        processMonitor.refresh(visible: false,now: now.addingTimeInterval(3))
        processMonitor.refresh(visible: true,now: now.addingTimeInterval(4),includeProcesses: true); await settle { !processMonitor.busy }
        expect(processMonitor.topProcesses.isEmpty,"Reopening primes process counters rather than including hidden time")
        var commands: [(String,UInt64)] = []
        var options = DaemonOptions()
        let features = Features(defaults: defaults,sendOption: { key, value in
            commands.append((key,value))
            if key == "one-shot" { options.oneShot = value == 1 }
        },readOptions: { options })
        features.oneShot(presentation: true)
        features.stopSession()
        try await Task.sleep(nanoseconds: 500_000_000)
        expect(!commands.contains { $0.0 == "presentation" && $0.1 == 1 },"Cancelled presentation cannot be re-enabled by a delayed callback")
        expect(features.pendingMode == nil,"Cancel clears pending session state immediately")
        commands = []
        features.oneShot(presentation: true)
        try await Task.sleep(nanoseconds: 500_000_000)
        expect(commands.contains { $0.0 == "presentation" && $0.1 == 1 },"An uncancelled presentation still starts normally")
        features.stopSession()
        commands = []
        features.pendingMode = 1
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["10"]
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        features.processInput = String(child.processIdentifier)
        features.watchProcess()
        expect(defaults.object(forKey: "watchedPID") == nil && commands.isEmpty,"Failed timer start cannot register a process watch")
        print("PASS: update-independent quota requests, malformed numbers, plan changes, clock correction, cancellation races and pending state")
    }
}
