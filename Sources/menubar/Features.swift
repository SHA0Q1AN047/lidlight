import AppKit
import IOKit.ps
import Carbon
import UserNotifications
import notify
import UniformTypeIdentifiers

struct AppRule: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}
struct Preferences: Codable {
    var threshold = 10
    var acOnly = false
    var startupAuto = false
    var launchAtLogin = true
    var countdown = true
    var notifications = false
    var shortcut = false
    var shortcutKey = 0
    var displayRule = false
    var schedule = false
    var weekdays = true
    var start = 18 * 60
    var end = 23 * 60
    var apps: [AppRule] = []
    var baseMode = 0
    var rulesPaused = false
}
struct PowerSnapshot {
    var ac: Bool
    var percent: Int?
    static func read() -> Self {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let ac = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String == kIOPSACPowerValue
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let percent = sources.compactMap { source -> Int? in
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { return nil }
            return d[kIOPSCurrentCapacityKey] as? Int
        }.first
        return Self(ac: ac, percent: percent)
    }
}

final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: () -> Void = {}
    func configure(enabled: Bool, alternate: Bool) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        guard enabled else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &type, context, &handler) == noErr else { return false }
        return RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(cmdKey | optionKey | (alternate ? shiftKey : 0)),
            EventHotKeyID(signature: 0x4C49444C, id: 1), GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class Features: ObservableObject {
    @Published var preferences: Preferences
    @Published var page = "home"
    @Published var reason = "Reading system state…"
    @Published var nextAction = ""
    @Published var countdownText = ""
    @Published var sessionText = "No active session"
    @Published var batteryText = "Battery usage appears during an awake session."
    @Published var history: [String] = []
    @Published var message: String?
    @Published var pendingMode: Int?
    @Published var runningApps: [AppRule] = []
    @Published var processInput = ""
    @Published var duration = 60
    @Published var until = Date().addingTimeInterval(3600)
    @Published var low = false
    @Published var conflicts: UInt64 = 0
    @Published var busy = false
    private var tokens: [String: Int32] = [:]
    private var pendingSince = Date.distantPast
    private var lastPower: Bool?
    private var lastLid: Bool?
    private var lastAwake: Bool?
    private var lastMode: Int?
    private var lastRequested: Int?
    private var lastOverride: UInt64 = 0
    private var warned = false
    private var batteryStart: Int?
    private var priorBattery: Int?
    private var batteryUsed = 0
    private var taskPID: Int32?
    private var taskIdentity: String?
    private let defaults: UserDefaults
    private let hotKey = HotKey()
    var restoreScreen: () -> Bool = { false }
    var actualAwake: () -> Bool? = { nil }
    var lidClosed: () -> Bool? = { nil }
    var didChange: () -> Void = {}
    var mode: Int? {
        guard let value = read("state"), value < 3 else { return nil }
        return Int(value)
    }
    var options: DaemonOptions {
        (try? Data(contentsOf: URL(fileURLWithPath: "/var/db/lidlight-options.json"))).flatMap { try? JSONDecoder().decode(DaemonOptions.self, from: $0) } ?? DaemonOptions()
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: "preferences.v1").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        history = defaults.stringArray(forKey: "activity") ?? []
        taskPID = defaults.object(forKey: "watchedPID") as? Int32
        taskIdentity = defaults.string(forKey: "watchedIdentity")
    }
    func start() {
        let config = options
        if config.oneShot { send("one-shot", 0) }
        if (config.oneShot || config.deadline > 0), config.resumeMode < 3 {
            preferences.baseMode = Int(config.resumeMode)
        } else if let current = mode, !config.startupAuto && !defaults.bool(forKey: "ruleActive") {
            preferences.baseMode = current; preferences.rulesPaused = current == 2
        }
        if config.startupAuto { preferences.baseMode = 0 }
        hotKey.action = { [weak self] in
            guard let self else { return }
            self.select(self.actualAwake() == true ? 2 : 1)
        }
        applyPreferences()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.record("System sleep") }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.record("System wake"); self?.tick() }
        tick()
    }
    func read(_ key: String) -> UInt64? {
        let name = "com.lidlight.\(key)"
        if tokens[name] == nil {
            var token: Int32 = 0
            guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return nil }
            tokens[name] = token
        }
        var value: UInt64 = 0
        guard notify_get_state(tokens[name]!, &value) == NOTIFY_STATUS_OK else { return nil }
        return value
    }
    func send(_ key: String, _ value: UInt64) {
        let name = "com.lidlight.option-\(key)"
        if tokens[name] == nil {
            var token: Int32 = 0
            guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { message = "Could not connect to the service."; return }
            tokens[name] = token
        }
        guard notify_set_state(tokens[name]!, value) == NOTIFY_STATUS_OK, notify_post(name) == NOTIFY_STATUS_OK else {
            message = "The service did not accept the request."; return
        }
        didChange()
    }
    private func save() { defaults.set(try? JSONEncoder().encode(preferences), forKey: "preferences.v1") }
    func applyPreferences() {
        preferences.threshold = min(50, max(10, preferences.threshold))
        preferences.start = min(1439, max(0, preferences.start)); preferences.end = min(1439, max(0, preferences.end))
        save()
        send("battery-limit", UInt64(preferences.threshold))
        send("ac-only", preferences.acOnly ? 1 : 0)
        send("startup-auto", preferences.startupAuto ? 1 : 0)
        if !hotKey.configure(enabled: preferences.shortcut, alternate: preferences.shortcutKey == 1) {
            message = "Shortcut is already in use. Choose the alternate combination." 
        }
    }
    func setLogin(_ enabled: Bool) {
        let result = Self.run("/bin/launchctl", [enabled ? "enable" : "disable", "gui/\(getuid())/com.lidlight.menubar"])
        if result.status == 0 { preferences.launchAtLogin = enabled; save() }
        else { message = "Could not change login startup: \(result.output)" }
    }
    func setNotifications(_ enabled: Bool) {
        preferences.notifications = enabled; save()
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if !granted { self.preferences.notifications = false; self.save(); self.message = error?.localizedDescription ?? "Notifications are disabled in System Settings." }
            }
        }
    }
    func prepareQuit() {
        preferences.baseMode = 2; preferences.rulesPaused = true
        defaults.set(false, forKey: "ruleActive")
        clearTask(); save()
    }
    func select(_ index: Int, automatic: Bool = false) {
        guard (0...2).contains(index) else { return }
        if !automatic {
            preferences.baseMode = index; preferences.rulesPaused = index == 2; save()
            clearTask()
        }
        defaults.set(automatic && index != preferences.baseMode, forKey: "ruleActive")
        pendingMode = index; pendingSince = Date(); lastRequested = index
        notify_post("com.lidlight.set-\(["auto", "on", "off"][index])")
        didChange()
    }
    func begin(until deadline: Date) {
        guard pendingMode == nil else { message = "Wait for the current mode to apply."; return }
        if options.deadline == 0 && !defaults.bool(forKey: "ruleActive"), let current = mode {
            preferences.baseMode = current; save()
        }
        guard deadline > Date(), deadline.timeIntervalSinceNow <= 7 * 86400 else { message = "Choose a time within the next seven days."; return }
        guard !options.oneShot else { message = "End the one-shot or presentation session first."; return }
        clearTask()
        send("deadline", UInt64(deadline.timeIntervalSince1970))
        pendingMode = 1; pendingSince = Date(); lastRequested = 1
        record("Timed awake session started")
    }
    func stopSession() {
        clearTask()
        let config = options
        if config.oneShot { send("one-shot", 0) }
        if config.deadline > 0 { send("deadline", 0) }
        send("presentation", 0)
        record("Session ended; previous mode restored")
    }
    func oneShot(presentation: Bool = false) {
        guard pendingMode == nil else { message = "Wait for the current mode to apply."; return }
        if !defaults.bool(forKey: "ruleActive"), let current = mode { preferences.baseMode = current; save() }
        guard options.deadline == 0 && !options.oneShot else { message = "End the current session before starting another."; return }
        clearTask()
        send("one-shot", 1)
        if presentation {
            // Both notifications run on the daemon's main queue, preserving order.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.send("presentation", 1) }
        }
        pendingMode = 1; pendingSince = Date(); lastRequested = 1
        record(presentation ? "Presentation started" : "One-shot awake started")
    }
    func watchProcess() {
        guard let pid = Int32(processInput), pid > 1, pid != getpid(), let identity = Self.processIdentity(pid) else { message = "Enter the PID of a running process you own."; return }
        guard options.deadline == 0 && !options.oneShot else { message = "End the active session first."; return }
        begin(until: Date().addingTimeInterval(7 * 86400))
        taskPID = pid; taskIdentity = identity
        defaults.set(pid, forKey: "watchedPID"); defaults.set(identity, forKey: "watchedIdentity")
        record("Waiting for process \(pid)")
    }
    private func clearTask() {
        taskPID = nil; taskIdentity = nil
        defaults.removeObject(forKey: "watchedPID"); defaults.removeObject(forKey: "watchedIdentity")
    }
    private static func processIdentity(_ pid: Int32) -> String? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info), info.pbi_uid == getuid(), info.pbi_status != UInt32(SZOMB) else { return nil }
        return "\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
    }
    func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              id != "com.lidlight.menubar" else { return }
        if !preferences.apps.contains(where: { $0.id == id }) {
            preferences.apps.append(AppRule(id: id, name: url.deletingPathExtension().lastPathComponent)); save()
        }
    }
    func removeApp(_ id: String) { preferences.apps.removeAll { $0.id == id }; save(); tick() }
    func restore() { message = restoreScreen() ? "Backlight restored." : "Could not restore brightness. Press the brightness-up key." }
    func blankScreen(lock: Bool) {
        if actualAwake() != true { oneShot() }
        send("presentation", 0)
        func perform(attempt: Int) {
            guard actualAwake() == true else {
                if attempt < 25 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { perform(attempt: attempt + 1) } }
                else { message = "Could not confirm awake mode. Check AC-only and battery protection settings." }
                return
            }
            if lock {
                typealias Lock = @convention(c) () -> Void
                guard let library = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
                      let function = dlsym(library, "SACLockScreenImmediate") else { message = "Lock is unavailable on this macOS version."; return }
                unsafeBitCast(function, to: Lock.self)()
                dlclose(library)
            } else {
                let result = Self.run("/usr/bin/pmset", ["displaysleepnow"])
                if result.status != 0 { message = "Could not turn off the display." }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { perform(attempt: 0) }
    }
    func recover() {
        guard !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = "do shell script \"/bin/launchctl kickstart -k system/com.lidlight.daemon || /bin/launchctl bootstrap system /Library/LaunchDaemons/com.lidlight.daemon.plist\" with administrator privileges"
            let result = Self.run("/usr/bin/osascript", ["-e", script])
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false; self.message = result.status == 0 ? "Service restart requested. Refreshing…" : "Recovery failed or was cancelled: \(result.output)"
                self.tokens.values.forEach { notify_cancel($0) }; self.tokens.removeAll()
                self.applyPreferences(); self.didChange()
            }
        }
    }
    private func record(_ text: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm:ss"
        history.insert("\(formatter.string(from: Date()))  \(text)", at: 0)
        history = Array(history.prefix(40)); defaults.set(history, forKey: "activity")
    }
    func clearHistory() { history = []; defaults.removeObject(forKey: "activity") }
    private func notifyLowBattery(_ percent: Int) {
        guard preferences.notifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "Lidlight · Low battery"
        content.body = "Battery is at \(percent)%. Sleep protection begins at \(preferences.threshold)%. Connect power to continue."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
    }
    func tick() {
        let power = PowerSnapshot.read()
        let config = options
        let awake = actualAwake()
        let current = mode
        if let old = lastPower, old != power.ac { record(power.ac ? "Power adapter connected" : "Switched to battery"); warned = false }
        lastPower = power.ac
        if let lid = lidClosed(), lid != lastLid { if lastLid != nil { record(lid ? "Lid closed" : "Lid opened") }; lastLid = lid }
        if let current, current != lastMode { record("Mode: \(["Automatic", "Stay awake", "Allow sleep"][current])"); lastMode = current }
        if lastAwake != awake { if let awake { record(awake ? "Sleep prevention active" : "Sleep allowed") }; lastAwake = awake }
        low = !power.ac && (power.percent.map { $0 <= config.batteryLimit } ?? false)
        if !power.ac, current == 1, let percent = power.percent, percent <= config.batteryLimit + 5, !warned {
            warned = true; notifyLowBattery(percent)
        }
        if power.ac { warned = false }
        if awake == true && !power.ac, let percent = power.percent {
            if batteryStart == nil { batteryStart = percent; batteryUsed = 0 }
            if let previous = priorBattery, percent < previous { batteryUsed += previous - percent }
            priorBattery = percent
            batteryText = "Battery used while awake: \(batteryUsed) percentage points (estimate)."
        } else { batteryStart = nil; priorBattery = nil }
        conflicts = read("overrides") ?? 0
        if conflicts < lastOverride { lastOverride = 0 }
        if conflicts > lastOverride { record("Power setting overridden; service restored it (\(conflicts) total)"); lastOverride = conflicts }
        if let requested = pendingMode {
            let expected = PowerPolicy.awake(mode: UInt64(requested), onAC: power.ac, lowBattery: low, acOnly: config.acOnly)
            if current == requested && awake == expected { pendingMode = nil; message = nil }
            else if Date().timeIntervalSince(pendingSince) > 8 { pendingMode = nil; lastRequested = nil; message = "Mode could not be confirmed. Check Details or restart the service." }
        }
        if taskPID != nil && config.deadline == 0 { clearTask(); record("Process watch cancelled") }
        if let pid = taskPID, let identity = taskIdentity, Self.processIdentity(pid) != identity {
            record("Watched process finished"); stopSession()
        }
        let activeSession = config.deadline > Date().timeIntervalSince1970 || config.oneShot
        countdownText = config.deadline > 0 ? "\(PowerPolicy.minutesLeft(deadline: config.deadline, now: Date().timeIntervalSince1970))m" : ""
        sessionText = taskPID.map { "Waiting for PID \($0) · maximum 7 days" } ?? (config.deadline > 0 ? "\(countdownText) remaining · restores previous mode" : config.presentation ? "Presentation · end manually" : config.oneShot ? "One-shot · ends on unplug or next login" : "No active session")
        if !activeSession && pendingMode == nil {
            if let current, let sent = lastRequested, current != sent { preferences.baseMode = current; preferences.rulesPaused = current == 2; defaults.set(false, forKey: "ruleActive"); save() }
            let apps = preferences.apps.isEmpty ? Set<String>() : Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let appActive = preferences.apps.contains { apps.contains($0.id) }
            let display = preferences.displayRule && Self.hasExternalDisplay()
            let scheduled = preferences.schedule && PowerPolicy.scheduled(now: Date(), start: preferences.start, end: preferences.end, weekdays: preferences.weekdays)
            let target = PowerPolicy.ruleMode(base: preferences.baseMode, apps: appActive, display: display, schedule: scheduled, paused: preferences.rulesPaused)
            if current != target && lastRequested != target { select(target, automatic: true) }
            else { lastRequested = target }
            reason = preferences.rulesPaused ? "Manual sleep · automation paused" : target == 1 && appActive ? "An App rule is keeping this Mac awake" : target == 1 && display ? "An external display rule is active" : target == 1 && scheduled ? "An awake schedule is active" : current == 0 ? (power.ac ? "Automatic · power adapter connected" : "Automatic · running on battery") : current == 1 ? "Stay awake selected" : "Normal sleep selected"
        } else { reason = config.presentation ? "Presentation keeps system and display awake" : taskPID != nil ? "Waiting for your process to finish" : "A temporary awake session is active" }
        if low && current == 1 { reason = "Low-battery protection · sleep allowed" }
        if config.acOnly && !power.ac { reason = "AC-only protection · sleep allowed" }
        nextAction = !power.ac && config.acOnly ? "Connect power to resume." : current == 0 ? (power.ac ? "Unplugging allows normal sleep." : "Connecting power keeps this Mac awake.") : activeSession ? "Ending the session restores the previous mode." : current == 1 ? "Sleep is allowed at \(config.batteryLimit)% battery." : "Choose Automatic to resume power rules."
        didChange()
    }
    static func hasExternalDisplay() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let task = Process(); let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
        task.standardOutput = pipe; task.standardError = pipe
        do { try task.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
    deinit { tokens.values.forEach { notify_cancel($0) } }
}
