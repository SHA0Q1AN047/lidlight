import Foundation
import UserNotifications

struct QuotaWindow: Identifiable, Equatable {
    let id: String
    let used: Double
    let minutes: Int
    let resetsAt: Date
    var remaining: Int { Int(max(0, min(100, 100 - used)).rounded()) }
    var label: String {
        if minutes == 300 { return "5-hour quota" }
        if minutes == 10080 { return "Weekly quota" }
        return minutes % 60 == 0 ? "\(minutes / 60)-hour quota" : "\(minutes)-minute quota"
    }
    var compact: String { minutes == 300 ? "5h" : minutes == 10080 ? "7d" : "\(minutes)m" }
}

enum CodexQuotaError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

struct QuotaRecoveryTracker: Codable {
    struct Exhausted: Codable { let minutes: Int; let reset: Date }
    private(set) var exhausted: [String: Exhausted] = [:]
    private(set) var expected: [String: Int] = [:]
    mutating func observe(_ windows: [QuotaWindow], now: Date = Date()) -> Bool {
        // Never infer recovery from a reset clock or from a failed/partial response.
        if windows.contains(where: { window in expected[window.id].map { $0 != window.minutes } ?? false }) {
            // Changed quota windows invalidate old exhaustion evidence (for example after a plan change).
            exhausted.removeAll(); expected.removeAll()
        }
        for window in windows { expected[window.id] = window.minutes }
        let recovery = !exhausted.isEmpty && !windows.isEmpty
            && expected.allSatisfy { id, minutes in windows.contains { $0.id == id && $0.minutes == minutes } }
            && exhausted.allSatisfy { id, old in
                windows.contains { $0.id == id && $0.minutes == old.minutes && $0.resetsAt >= old.reset && $0.resetsAt > now && $0.used < 100 }
            } && windows.allSatisfy { $0.used < 100 && $0.resetsAt > now }
        if recovery { exhausted.removeAll(); expected.removeAll() }
        for window in windows where window.used >= 100 {
            exhausted[window.id] = Exhausted(minutes: window.minutes,reset: window.resetsAt)
        }
        return recovery
    }
}

final class CodexQuota: ObservableObject {
    let history: QuotaHistory
    private let defaults: UserDefaults
    private let fetchQuota: () throws -> [QuotaWindow]
    private let uptime: () -> TimeInterval
    private var requestGeneration: UInt64 = 0
    private var authorizationRequest: UInt64 = 0
    private var recovery: QuotaRecoveryTracker
    @Published private(set) var recoveryNotifications: Bool
    @Published var notificationMessage: String?
    init(history: QuotaHistory = QuotaHistory(), defaults: UserDefaults = .standard, fetch: @escaping () throws -> [QuotaWindow] = CodexQuota.fetch, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.history = history; self.defaults = defaults; self.fetchQuota = fetch; self.uptime = uptime
        enabled = defaults.object(forKey: "showCodexQuota") as? Bool ?? true
        recoveryNotifications = defaults.bool(forKey: "quotaRecoveryNotifications")
        recovery = defaults.data(forKey: "quotaRecoveryTracker").flatMap { try? JSONDecoder().decode(QuotaRecoveryTracker.self,from: $0) } ?? QuotaRecoveryTracker()
    }
    func setRecoveryNotifications(_ enabled: Bool) {
        authorizationRequest &+= 1
        let request = authorizationRequest
        if !enabled {
            recoveryNotifications = false; defaults.set(false,forKey: "quotaRecoveryNotifications")
            recovery = QuotaRecoveryTracker(); defaults.removeObject(forKey: "quotaRecoveryTracker")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self, self.authorizationRequest == request else { return }
                self.recoveryNotifications = granted
                self.defaults.set(granted,forKey: "quotaRecoveryNotifications")
                self.notificationMessage = granted ? nil : (error?.localizedDescription ?? "Allow Lidlight notifications in System Settings.")
                if granted { self.refresh(force: true) }
            }
        }
    }
    func accept(_ windows: [QuotaWindow], now: Date = Date()) {
        history.record(windows,now: now); self.windows = windows; updated = now; message = nil
        guard recoveryNotifications else { return }
        let recovered = recovery.observe(windows,now: now)
        defaults.set(try? JSONEncoder().encode(recovery),forKey: "quotaRecoveryTracker")
        guard recovered else { return }
        let content = UNMutableNotificationContent()
        content.title = "Lidlight · Codex quota is available"
        content.body = "A fresh check confirms quota is available again. Open Lidlight to see your remaining limits."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "quota-recovered",content: content,trigger: nil)) { [weak self] error in
            if let error { DispatchQueue.main.async { self?.notificationMessage = error.localizedDescription } }
        }
    }
    @Published var windows: [QuotaWindow] = []
    @Published var updated: Date?
    @Published var busy = false
    @Published var message: String?
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "showCodexQuota")
            guard enabled != oldValue else { return }
            requestGeneration &+= 1
            if enabled { refresh(force: true) }
        }
    }
    private var lastAttempt = -Double.infinity
    var summary: String {
        if !windows.isEmpty {
            return windows.map { "\($0.compact) \($0.resetsAt <= Date() ? "reset pending" : "\($0.remaining)%")" }.joined(separator: " · ")
        }
        return busy ? "Checking…" : "Open usage details"
    }
    func refresh(force: Bool = false) {
        let now = uptime()
        guard enabled, !busy, force || now - lastAttempt >= 300 else { return }
        busy = true; lastAttempt = now
        let generation = requestGeneration
        let fetch = fetchQuota
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try fetch() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.requestGeneration == generation else {
                    if self.enabled { self.refresh(force: true) }
                    return
                }
                switch result {
                case .success(let windows): if self.enabled { self.accept(windows) }
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    static func parse(_ result: [String: Any]) throws -> [QuotaWindow] {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        guard let bucket = (buckets?["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]) else {
            throw CodexQuotaError.unavailable("Codex quota is not available for this account.")
        }
        let windows = ["primary", "secondary"].compactMap { key -> QuotaWindow? in
            guard let window = bucket[key] as? [String: Any],
                  let used = Self.number(window["usedPercent"]), used >= 0,
                  let durationValue = Self.number(window["windowDurationMins"]), let duration = Int(exactly: durationValue), duration > 0,
                  let reset = Self.number(window["resetsAt"]), reset > 0, reset <= Date.distantFuture.timeIntervalSince1970 else { return nil }
            return QuotaWindow(id: key, used: used, minutes: duration, resetsAt: Date(timeIntervalSince1970: reset))
        }
        guard !windows.isEmpty else { throw CodexQuotaError.unavailable("No quota windows were returned. Sign in to Codex with your ChatGPT account.") }
        return windows
    }
    static func executable() -> String? {
        let paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", NSHomeDirectory() + "/.local/bin/codex", NSHomeDirectory() + "/.cargo/bin/codex", "/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func fetch() throws -> [QuotaWindow] {
        guard let executable = executable() else { throw CodexQuotaError.unavailable("Install Codex CLI or the Codex desktop app, then sign in with ChatGPT.") }
        let process = Process(); let input = Pipe(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio", "-c", "analytics.enabled=false"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let timeout = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ message: [String: Any]) throws {
            guard process.isRunning else { throw CodexQuotaError.unavailable("Codex connection ended. Retry the usage check.") }
            var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "lidlight", "title": "Lidlight", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"]]])
        var buffer = Data()
        while process.isRunning {
            let data = output.fileHandleForReading.availableData
            if data.isEmpty { break }
            buffer.append(data)
            guard buffer.count < 2_000_000 else { throw CodexQuotaError.unavailable("Unexpected Codex response size.") }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], object["method"] == nil, let id = object["id"] as? Int else { continue }
                if object["error"] != nil { throw CodexQuotaError.unavailable("Codex could not read quota. Check your Codex sign-in and network connection.") }
                if id == 0 {
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 1, "method": "account/rateLimits/read"])
                } else if id == 1, let result = object["result"] as? [String: Any] { return try parse(result) }
            }
        }
        throw CodexQuotaError.unavailable("Codex did not return quota before the connection ended. Retry after checking your sign-in and network.")
    }
}
