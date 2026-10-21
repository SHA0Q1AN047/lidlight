import SwiftUI
import AppKit
import IOKit.ps
import notify

final class ChargeLimitModel: ObservableObject {
    @Published var status: ChargeLimitStatus?
    @Published var pending = false
    @Published var error: String?
    private var requestedAt = Date.distantPast
    private var token: Int32 = 0
    private var registered = false
    var hasBattery: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        return (IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]).contains {
            let d = IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
            return d?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
    func refresh() {
        let new = (try? Data(contentsOf: URL(fileURLWithPath: ChargeLimitStatus.path))).flatMap { try? JSONDecoder().decode(ChargeLimitStatus.self, from: $0) }
        status = new.flatMap { Date().timeIntervalSince($0.updated) >= 0 && Date().timeIntervalSince($0.updated) < 15 ? $0 : nil }
        if pending, let status, status.updated > requestedAt { pending = false }
        if pending && Date().timeIntervalSince(requestedAt) > 10 {
            pending = false; error = "The service did not confirm the request."
        }
    }
    func send(_ value: UInt64) {
        guard !pending else { return }
        if !registered {
            registered = notify_register_check("com.lidlight.option-charge-limit", &token) == NOTIFY_STATUS_OK
        }
        requestedAt = Date(); error = nil
        guard registered, notify_set_state(token, value) == NOTIFY_STATUS_OK,
              notify_post("com.lidlight.option-charge-limit") == NOTIFY_STATUS_OK else {
            error = "Could not contact the charging service."; return
        }
        pending = true
    }
    deinit { if registered { notify_cancel(token) } }
}

struct ChargeLimitView: View {
    @StateObject private var model = ChargeLimitModel()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        Group {
            if model.hasBattery {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Battery charging", systemImage: "battery.75").font(.system(size: 13, weight: .semibold))
                    if let status = model.status {
                        if status.systemManaged {
                            Button("Set charge limit in macOS…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!)
                            }.buttonStyle(GlassActionStyle())
                            Text("Choose 80% under Charging. Use the battery menu to charge to full once.")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        } else {
                            Toggle("Limit charging to 80%", isOn: Binding(get: { status.enabled }, set: { model.send($0 ? 1 : 0) }))
                                .disabled(model.pending || (!status.supported && !status.enabled))
                            if status.enabled {
                                Button(status.fullOnce ? "Resume 80% limit" : "Charge to 100% once") { model.send(status.fullOnce ? 1 : 2) }
                                    .buttonStyle(GlassActionStyle()).disabled(model.pending || !status.supported)
                            }
                        }
                        Text(model.pending ? "Applying…" : status.message).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(status.charging ? "Battery is charging" : "Battery is not charging")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    } else {
                        Text("Charging service unavailable. Install the matching app and service version.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    if let error = model.error { Text(error).font(.system(size: 11)).foregroundColor(.orange) }
                }.padding(14).lidlightCard()
            }
        }.onAppear { model.refresh() }.onReceive(timer) { _ in model.refresh() }
    }
}
