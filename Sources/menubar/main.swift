import AppKit
import SwiftUI
import IOKit
import IOKit.ps
import notify
import UserNotifications

let notifyPrefix = "com.lidlight"

func rootDomainFlag(_ key: String) -> Bool? {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return nil }
    defer { IOObjectRelease(root) }
    let value = IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
    return value as? Bool
}

func powerDescription() -> String {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
    var text = type == kIOPSACPowerValue ? "Power Adapter" : "Battery"
    let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
    for source in sources {
        guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let percent = desc[kIOPSCurrentCapacityKey] as? Int else { continue }
        text += " · \(percent)%"
        break
    }
    return text
}

func daemonRunning() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "lidlightd"]
    task.standardOutput = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return false
    }
    return task.terminationStatus == 0
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let dashboard = DashboardState()
    let features = Features()
    let popover = NSPopover()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let lidScreen = LidScreen()
    var stateToken: Int32 = 0
    var timer: Timer?
    var lidTimer: Timer?
    private var refreshPending = false
    private var refreshing = false
    private var userRequestedQuit = false
    let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    @MainActor private lazy var quitController = QuitController(
        requestStop: { notify_post("\(notifyPrefix).set-off") },
        hasStopped: { QuitPolicy.isStopped(prefix: notifyPrefix) })

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 600)
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: Dashboard(
            state: dashboard, features: features,
            select: { [weak self] index in
                self?.features.select(index)
                self?.refreshSoon()
            },
            toggleDim: { [weak self] in
                guard let self else { return }
                self.lidScreen.enabled.toggle()
                self.dashboard.dim = self.lidScreen.enabled
                if !self.lidScreen.enabled { self.lidScreen.restore() }
            },
            copyDiagnostics: { [weak self] in
                guard let self, !self.dashboard.copying else { return }
                self.dashboard.copying = true
                self.dashboard.copyLabel = "Preparing…"
                DispatchQueue.global(qos: .utility).async {
                    let report = Health.report()
                    DispatchQueue.main.async {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report, forType: .string)
                        self.dashboard.copying = false
                        self.dashboard.copyLabel = "Copied"
                    }
                }
            },
            quit: { [weak self] in
                self?.features.prepareQuit()
                self?.userRequestedQuit = true
                NSApp.terminate(nil)
            }))
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleDashboard)
        notify_register_dispatch("\(notifyPrefix).state", &stateToken, .main) { [weak self] _ in self?.refreshSoon() }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().refreshSoon()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in guard let self else { return }; if !self.userRequestedQuit { self.features.tick() }; self.refresh() }
        lidTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let modeOn = rootDomainFlag("SleepDisabled"),
                  let lidClosed = rootDomainFlag("AppleClamshellState") else { return }
            self?.lidScreen.tick(modeOn: modeOn, lidClosed: lidClosed)
        }
        if rootDomainFlag("AppleClamshellState") == false { lidScreen.restore() }
        signal(SIGTERM, SIG_IGN)
        termSource.setEventHandler { [weak self] in
            self?.lidScreen.restore()
            exit(0)
        }
        termSource.resume()
        features.actualAwake = { rootDomainFlag("SleepDisabled") }
        features.lidClosed = { rootDomainFlag("AppleClamshellState") }
        features.restoreScreen = { [weak self] in self?.lidScreen.forceOn() ?? false }
        features.didChange = { [weak self] in self?.refresh() }
        features.start()
        refresh()
        if CommandLine.arguments.contains("--health-check") { toggleDashboard(); dashboard.details = true }
    }

    @objc func toggleDashboard() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.close() } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            refresh()
        }
    }

    func refreshSoon() {
        refresh()
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshPending = false
            if self?.userRequestedQuit == false { self?.features.tick() }
            self?.refresh()
        }
    }

    func refresh() {
        let enabled = rootDomainFlag("SleepDisabled")
        statusItem.button?.image = features.low ? MenuBarIcon.lowBattery : MenuBarIcon.image(awake: enabled)
        statusItem.button?.title = features.preferences.countdown ? features.countdownText : ""
        statusItem.button?.toolTip = "Lidlight · " + features.reason + (features.countdownText.isEmpty ? "" : " · " + features.countdownText)
        // Hidden panels do not need process scans or power-source snapshots.
        guard popover.isShown, !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let running = daemonRunning()
            let power = powerDescription()
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                var mode = UInt64.max
                let known = notify_get_state(self.stateToken, &mode) == NOTIFY_STATUS_OK
                self.dashboard.awake = rootDomainFlag("SleepDisabled")
                self.dashboard.running = running
                self.dashboard.mode = running && known && mode < 3 ? Int(mode) : nil
                self.dashboard.power = power
                self.dashboard.dim = self.lidScreen.enabled
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { lidScreen.restore() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard userRequestedQuit,
              !QuitPolicy.isSystemQuit(NSAppleEventManager.shared().currentAppleEvent) else { return .terminateNow }
        quitController.begin { [weak self] stopped in
            sender.reply(toApplicationShouldTerminate: stopped)
            guard !stopped else { return }
            self?.userRequestedQuit = false
            self?.dashboard.message = "Could not confirm sleep is allowed. Lidlight is still running. Check diagnostics and try again."
            self?.refresh()
        }
        return .terminateLater
    }
}

if CommandLine.arguments.contains("--screen-on") { exit(LidScreen().forceOn() ? 0 : 1) }
if CommandLine.arguments.contains("--print-diagnostics") {
    print(Health.report())
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
