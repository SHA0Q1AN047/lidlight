import Foundation

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

final class CodexQuota: ObservableObject {
    @Published var windows: [QuotaWindow] = []
    @Published var updated: Date?
    @Published var busy = false
    @Published var message: String?
    @Published var enabled = UserDefaults.standard.object(forKey: "showCodexQuota") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "showCodexQuota"); if enabled { refresh(force: true) } }
    }
    private var lastAttempt = Date.distantPast
    var summary: String {
        if !windows.isEmpty {
            return windows.map { "\($0.compact) \($0.resetsAt <= Date() ? "reset pending" : "\($0.remaining)%")" }.joined(separator: " · ")
        }
        return busy ? "Checking…" : "Open usage details"
    }
    func refresh(force: Bool = false) {
        guard enabled, !busy, force || Date().timeIntervalSince(lastAttempt) >= 300 else { return }
        busy = true; lastAttempt = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try Self.fetch() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let windows): self.windows = windows; self.updated = Date(); self.message = nil
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
    static func parse(_ result: [String: Any]) throws -> [QuotaWindow] {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        guard let bucket = (buckets?["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]) else {
            throw CodexQuotaError.unavailable("Codex quota is not available for this account.")
        }
        let windows = ["primary", "secondary"].compactMap { key -> QuotaWindow? in
            guard let window = bucket[key] as? [String: Any],
                  let used = (window["usedPercent"] as? NSNumber)?.doubleValue, used.isFinite,
                  let duration = (window["windowDurationMins"] as? NSNumber)?.intValue, duration > 0,
                  let reset = (window["resetsAt"] as? NSNumber)?.doubleValue, reset.isFinite, reset > 0 else { return nil }
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
        try send(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "lidlight", "title": "Lidlight", "version": "1.1.1"]]])
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
