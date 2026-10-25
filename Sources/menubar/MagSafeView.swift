import SwiftUI
import AppKit
import notify

final class MagSafeModel: ObservableObject {
    static let shared = MagSafeModel()
    @Published var status = "LED managed by macOS"
    @Published var supported = false
    private let queue = DispatchQueue(label: "com.lidlight.codex-activity", qos: .utility)
    private let reader = CodexActivityReader()
    private var busy = false
    private var watcher: CodexActivityWatcher?
    private var pending = Set<URL>()
    private var rescan = false
    private var dirty = true
    private var stopped = false
    private var lastRead = Date.distantPast
    private var cachedRunning: Bool?
    private var wasEnabled = false
    private var token: Int32 = 0
    private var registered = false
    func stop() {
        stopped = true
        watcher?.stop(); watcher = nil
        if registered { notify_set_state(token, 0); notify_post("com.lidlight.option-magsafe") }
    }
    func tick() {
        guard !stopped, !busy else { return }
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "magSafeCodex")
        if enabled && watcher == nil {
            watcher = CodexActivityWatcher(root: CodexActivityReader.root) { [weak self] urls, rescan in
                guard let self, !self.stopped else { return }
                if self.pending.count + urls.count > 256 { self.pending.removeAll(); self.rescan = true }
                else { self.pending.formUnion(urls) }
                self.rescan = self.rescan || rescan
                self.dirty = true
                self.tick()
            }
        } else if !enabled { watcher?.stop(); watcher = nil }
        let read = enabled && (dirty || !wasEnabled || Date().timeIntervalSince(lastRead) >= 30)
        wasEnabled = enabled
        let urls = Array(pending), needsRescan = rescan, cached = cachedRunning
        pending.removeAll(); rescan = false; dirty = false
        if read { lastRead = Date() }
        busy = true
        queue.async {
            if read { self.reader.changed(urls, rescan: needsRescan) }
            let running = enabled ? (read ? self.reader.running() : cached) : nil
            DispatchQueue.main.async {
                self.busy = false
                guard !self.stopped else { return }
                self.cachedRunning = running
                let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
                let mode = MagSafePolicy.mode(enabled: defaults.bool(forKey: "magSafeCodex"), nightEnabled: defaults.bool(forKey: "magSafeNight"), minute: (now.hour ?? 0)*60+(now.minute ?? 0), start: defaults.object(forKey: "magSafeNightStart") as? Int ?? 1380, end: defaults.object(forKey: "magSafeNightEnd") as? Int ?? 420, running: running, dark: defaults.bool(forKey: "magSafeDark"))
                if !self.registered { self.registered = notify_register_check("com.lidlight.option-magsafe", &self.token) == NOTIFY_STATUS_OK }
                if self.registered { notify_set_state(self.token, mode); notify_post("com.lidlight.option-magsafe") }
                let result = (try? Data(contentsOf: URL(fileURLWithPath: MagSafeStatus.path))).flatMap { try? JSONDecoder().decode(MagSafeStatus.self, from: $0) }
                self.supported = result?.supported ?? false
                self.status = result.flatMap { Date().timeIntervalSince($0.updated) < 15 ? $0.message : nil } ?? "Install the matching MagSafe service to enable LED control."
                if enabled && running == nil && mode == 0 { self.status = "Codex activity unknown · LED handed back to macOS" }
                if self.dirty { self.tick() }
            }
        }
    }
}

struct MagSafeView: View {
    @ObservedObject private var model = MagSafeModel.shared
    @AppStorage("magSafeCodex") private var enabled = false
    @AppStorage("magSafeNight") private var night = false
    @AppStorage("magSafeDark") private var dark = false
    @AppStorage("magSafeNightStart") private var start = 1380
    @AppStorage("magSafeNightEnd") private var end = 420
    private func time(_ value: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(value.wrappedValue)*60) }, set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            value.wrappedValue = (c.hour ?? 0)*60+(c.minute ?? 0); model.tick()
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MagSafe status light", systemImage: "lightbulb").font(.system(size: 13, weight: .semibold))
            Toggle("Show Codex activity", isOn: $enabled).onChange(of: enabled) { _ in model.tick() }
            Text("Running: amber 2s on / 2s off · Idle: green, or off when idle/night lights off is enabled. Based on local Codex session events, not quota or CPU usage.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            Toggle("Keep light off when idle", isOn: $dark).onChange(of: dark) { _ in model.tick() }
            Toggle("Night lights off", isOn: $night).onChange(of: night) { _ in model.tick() }
            if night {
                DatePicker("From", selection: time($start), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: time($end), displayedComponents: .hourAndMinute)
                Text(start == end ? "Choose different times to enable the schedule." : "Codex activity still pulses at night; the light turns off when finished. Uses this Mac’s local time.").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text(model.status).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Compatible MagSafe 3 Macs only. LED colors no longer indicate charging while enabled. Keep Lidlight running; sleep and app exit restore system control.")
                .font(.system(size: 10)).foregroundColor(.secondary)
        }.padding(14).lidlightCard().onAppear { model.tick() }
    }
}
