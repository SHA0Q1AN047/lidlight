import SwiftUI

final class DashboardState: ObservableObject {
    @Published var awake: Bool?
    @Published var running = false
    @Published var mode: Int?
    @Published var power = "Checking power…"
    @Published var dim = true
    @Published var details = false
    @Published var message: String?
    @Published var copying = false
    @Published var copyLabel = "Copy diagnostics"
}

struct Dashboard: View {
    @ObservedObject var state: DashboardState
    @ObservedObject var features: Features
    @ObservedObject var quota: CodexQuota
    @ObservedObject var updater: AppUpdater
    @ObservedObject var monitor: PerformanceMonitor
    @ObservedObject var verification: InstallVerification
    let select: (Int) -> Void
    let toggleDim: () -> Void
    let copyDiagnostics: () -> Void
    let quit: () -> Void
    private let mint = LidlightPalette.iris
    var body: some View {
        VStack(spacing: 0) {
        if features.page != "home" || state.details {
            HStack {
                Button { features.page = "home"; state.details = false } label: { Label("Back to Lidlight", systemImage: "chevron.left") }
                    .buttonStyle(GlassActionStyle()).font(.system(size: 12)).foregroundColor(mint)
                Spacer()
            }.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 8)
        }
        ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 12) {
            if features.page == "controls" {
                controlsContent
            } else if features.page == "performance" {
                PerformanceView(monitor: monitor, now: Date())
            } else if features.page == "updates" {
                UpdatesView(updater: updater, verification: verification)
            } else if features.page == "codex" {
                CodexQuotaView(quota: quota)
            } else if features.page != "home" {
                FeaturePages(features: features)
            } else if state.details {
                diagnosticsContent
            } else {
            HStack(alignment: .top, spacing: 12) {
                Button { features.page = "codex"; quota.refresh(force: quota.message != nil) } label: {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        CodexWeatherHeader(quota: quota, now: context.date)
                    }
                }.buttonStyle(.plain)
                Button { features.page = "settings" } label: { Image(systemName: "slider.horizontal.3").padding(10).lidlightGlass(radius: 20) }
                    .buttonStyle(.plain).accessibilityLabel("Preferences")
            }
            if let release = updater.available {
                Button { features.page = "updates" } label: {
                    Label("\(release.tag) available · Update", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(mint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(GlassActionStyle())
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(!state.running ? "Service offline" : (state.awake == true ? "Keeping Mac awake" : (state.awake == false ? "Sleep allowed" : "Checking status…")))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Spacer(minLength: 4)
                    Circle().fill(state.running && state.awake != nil ? (state.awake == true ? mint : Color.secondary) : Color.orange).frame(width: 7, height: 7)
                }
                Text(state.power).font(.system(size: 11)).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    homeMode(0, "Automatic", "bolt")
                    homeMode(1, "Stay awake", "sun.max")
                    homeMode(2, "Allow sleep", "moon")
                }
                Text(features.pendingMode != nil ? "Applying mode…" : features.reason)
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if features.supply.falling {
                    Text(features.supply.summary).font(.system(size: 11)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(16).lidlightCard()
            Button { features.page = "performance" } label: {
                PerformanceSummary(monitor: monitor, now: Date())
                    .padding(16).lidlightCard()
            }.buttonStyle(.plain)
            if features.sessionText != "No active session" {
                Button { features.page = "sessions" } label: {
                    Label(features.sessionText, systemImage: "timer")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(mint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(GlassActionStyle())
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    nav("Sessions", "Timers & focus", "timer", "sessions")
                    nav("Countdown", "Your next event", "calendar", "countdown")
                }
                Divider().padding(.vertical, 3)
                HStack(spacing: 12) {
                    nav("Rules", "Automations", "arrow.triangle.branch", "rules")
                    nav("Activity", "Recent changes", "clock", "activity")
                }
            }
            if let status = verification.status, !status.verified || verification.updateConfirmed {
                Button { features.page = "updates" } label: {
                    Label(verification.updateConfirmed ? "Update confirmed · " + status.running : status.summary, systemImage: status.verified ? "checkmark.seal" : "exclamationmark.circle")
                        .font(.system(size: 10)).foregroundColor(status.verified ? .secondary : .orange)
                }.buttonStyle(.plain)
            }
            if features.conflicts > 0 { Text("Power setting conflicts: \(features.conflicts). See More → Diagnostics.").font(.system(size: 11)).foregroundColor(.orange) }
            if let message = features.message { Text(message).font(.system(size: 11)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Menu {
                    Button("Power & display") { features.page = "controls" }
                    Button("Preferences") { features.page = "settings" }
                    Button("Updates") { features.page = "updates" }
                    Button("Diagnostics") { state.details = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button("Quit & allow sleep", action: quit).buttonStyle(.plain).foregroundColor(.secondary)
            }.font(.system(size: 11))
            if let message = state.message {
                Text(message).font(.system(size: 12)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
        }.padding(.horizontal, 22).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        }
        }.frame(width: 380, height: 600)
            .background(PanelBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .foregroundColor(.primary).accentColor(LidlightPalette.iris).tint(LidlightPalette.iris).environment(\.locale, Locale(identifier: "en_US"))
    }
    private var controlsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Power controls").font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(features.nextAction).font(.system(size: 12)).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text("POWER MODE").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    modeButton(0, "Automatic", "On AC power", "bolt.circle")
                    modeButton(1, "Stay awake", "Even on battery", "sun.max")
                    modeButton(2, "Allow sleep", "Normal behavior", "moon")
                }
                if let pending = features.pendingMode { Text("Applying \(["Automatic", "Stay awake", "Allow sleep"][pending])…").font(.system(size: 11)).foregroundColor(mint) }
                if state.mode == 1 { Text("Battery protection allows sleep at \(features.preferences.threshold)%.").font(.system(size: 10)).foregroundColor(.secondary) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Power adapter check", systemImage: "powerplug").font(.system(size: 12, weight: .semibold))
                Text(features.supply.summary).font(.system(size: 11)).foregroundColor(features.supply.falling ? .orange : .secondary)
                Text("Warns after a drop of 2+ battery points across 3–5 minutes on AC. Charging limits or a full battery alone do not trigger it. This is a supply warning, not a wattage measurement.").font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(14).lidlightCard()
            ChargeLimitView()
            Toggle(isOn: Binding(get: { state.dim }, set: { _ in toggleDim() })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dim on lid close").font(.system(size: 12, weight: .medium))
                    Text("Backlight only. Your session stays active.").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }.toggleStyle(SwitchToggleStyle(tint: mint)).accentColor(mint)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var diagnosticsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Details").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Just the essentials.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Background service"); Spacer(); Text(state.running ? "Running" : "Offline").foregroundColor(state.running ? mint : .orange) }
                Divider()
                HStack { Text("Sleep"); Spacer(); Text(state.awake.map { $0 ? "Prevented" : "Allowed" } ?? "Unknown").foregroundColor(.secondary) }
                Divider()
                HStack { Text("Version"); Spacer(); Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Preview").foregroundColor(.secondary) }
            }.font(.system(size: 12)).padding(18).lidlightCard(radius: 16)
            Text(state.running ? "The background service applies your selected mode." : "Reinstall Lidlight to restore the background service.")
                .font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(action: copyDiagnostics) { Label(state.copyLabel, systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(14) }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundColor(mint)
                .lidlightGlass().disabled(state.copying)
            Button { features.recover() } label: { Label(features.busy ? "Restarting…" : "Restart background service", systemImage: "arrow.clockwise") }
                .buttonStyle(GlassActionStyle()).foregroundColor(mint).disabled(features.busy)
            Text("Recovery requests administrator authorization.").font(.system(size: 10)).foregroundColor(.secondary)
            if features.conflicts > 0 { Text("Another tool changed sleep settings \(features.conflicts) times. Lidlight restored them. The source cannot be identified reliably.").font(.system(size: 11)).foregroundColor(.orange) }
            Text("Copies app, power and thermal status to your clipboard.")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let message = state.message { Text(message).font(.system(size: 12)).foregroundColor(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nav(_ title: String, _ detail: String, _ symbol: String, _ page: String) -> some View {
        Button { features.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 20).foregroundColor(mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 9)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func homeMode(_ index: Int, _ title: String, _ icon: String) -> some View {
        Button { select(index) } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                .lidlightGlass(selected: state.mode == index, radius: 12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.mode == index ? mint.opacity(0.6) : .clear, lineWidth: 1))
                .foregroundColor(state.mode == index ? mint : .primary)
        }.buttonStyle(.plain)
            .disabled(!state.running || features.pendingMode != nil)
            .accessibilityLabel(title)
            .accessibilityValue(state.mode == index ? "Selected" : "Not selected")
            .help(["Stay awake on AC power; allow sleep on battery.", "Stay awake on battery too, subject to battery protection.", "Let macOS sleep normally."][index])
    }

    private func modeButton(_ index: Int, _ title: String, _ detail: String, _ icon: String) -> some View {
        Button { select(index) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .lidlightGlass(selected: state.mode == index, radius: 14)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.mode == index ? mint.opacity(0.6) : Color.clear, lineWidth: 1))
                .foregroundColor(state.mode == index ? mint : .primary)
        }.buttonStyle(.plain).disabled(!state.running || features.pendingMode != nil).accessibilityLabel(title + ", " + detail)
    }
}
