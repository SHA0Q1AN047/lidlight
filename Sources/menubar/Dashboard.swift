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
    let select: (Int) -> Void
    let toggleDim: () -> Void
    let copyDiagnostics: () -> Void
    let quit: () -> Void
    private let mint = Color(red: 0.48, green: 0.93, blue: 0.78)
    private var headline: String {
        guard state.running else { return "Needs attention." }
        return state.awake.map { $0 ? "Keep going." : "Rest easy." } ?? "Checking status…"
    }
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 18) {
            if state.details {
                diagnosticsContent
            } else {
            HStack {
                Image(nsImage: NSImage(named: NSImage.Name("AppIcon")) ?? NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Lidlight")!).resizable().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lidlight").font(.system(size: 20, weight: .semibold))
                    Text("CLOSE THE LID. KEEP THE FLOW.").font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundColor(.gray)
                }
                Spacer()
                Text("LOCAL").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundColor(.gray)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(state.running && state.awake != nil ? (state.awake == true ? mint : Color.gray) : Color.orange).frame(width: 8, height: 8)
                    Text(!state.running ? "SERVICE OFFLINE" : (state.awake == true ? "AWAKE" : (state.awake == false ? "SLEEP ALLOWED" : "UNKNOWN"))).font(.system(size: 10, weight: .semibold)).tracking(1.5)
                }
                Text(headline).font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(!state.running ? "Open Details to check the background service." : (state.awake == true ? "Your Mac stays active with the lid closed." : (state.awake == false ? "Your Mac can sleep normally." : "Sleep behavior could not be confirmed."))).font(.system(size: 12)).foregroundColor(.gray).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Color.white.opacity(0.08))
                Label(state.power, systemImage: "bolt.fill").font(.system(size: 12)).foregroundColor(mint)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.045)).cornerRadius(18)
            VStack(alignment: .leading, spacing: 10) {
                Text("POWER MODE").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundColor(.gray)
                HStack(spacing: 8) {
                    modeButton(0, "Automatic", "On AC power", "bolt.circle")
                    modeButton(1, "Stay awake", "Even on battery", "sun.max")
                    modeButton(2, "Allow sleep", "Normal behavior", "moon")
                }
                if state.mode == 1 { Text("Battery protection allows sleep at 10%.").font(.system(size: 10)).foregroundColor(.gray) }
            }
            Toggle(isOn: Binding(get: { state.dim }, set: { _ in toggleDim() })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dim on lid close").font(.system(size: 12, weight: .medium))
                    Text("Backlight only. Your session stays active.").font(.system(size: 10)).foregroundColor(.gray)
                }
            }.toggleStyle(SwitchToggleStyle(tint: mint)).accentColor(mint)
            Divider()
            HStack {
                Button { state.details.toggle() } label: {
                    Label(state.details ? "Hide details" : "Details", systemImage: "waveform.path.ecg")
                }.buttonStyle(.plain)
                Spacer()
                Button("Quit & allow sleep", action: quit).buttonStyle(.plain).foregroundColor(.gray)
            }.font(.system(size: 11))
            if let message = state.message {
                Text(message).font(.system(size: 12)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 380, height: 540)
            .background(Color(red: 0.055, green: 0.075, blue: 0.095))
            .foregroundColor(.white).preferredColorScheme(.dark)
    }
    private var diagnosticsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button { state.details = false } label: { Label("Back to Lidlight", systemImage: "chevron.left") }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(mint)
            VStack(alignment: .leading, spacing: 6) {
                Text("Details").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Just the essentials.").font(.system(size: 12)).foregroundColor(.gray)
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Background service"); Spacer(); Text(state.running ? "Running" : "Offline").foregroundColor(state.running ? mint : .orange) }
                Divider()
                HStack { Text("Sleep"); Spacer(); Text(state.awake.map { $0 ? "Prevented" : "Allowed" } ?? "Unknown").foregroundColor(.gray) }
                Divider()
                HStack { Text("Version"); Spacer(); Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Preview").foregroundColor(.gray) }
            }.font(.system(size: 12)).padding(18).background(Color.white.opacity(0.045)).cornerRadius(16)
            Text(state.running ? "The background service applies your selected mode." : "Reinstall Lidlight to restore the background service.")
                .font(.system(size: 12)).foregroundColor(.gray).fixedSize(horizontal: false, vertical: true)
            Button(action: copyDiagnostics) { Label(state.copyLabel, systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(14) }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundColor(mint)
                .background(mint.opacity(0.1)).cornerRadius(12).disabled(state.copying)
            Text("Copies app, power and thermal status to your clipboard.")
                .font(.system(size: 10)).foregroundColor(.gray).fixedSize(horizontal: false, vertical: true)
            if let message = state.message { Text(message).font(.system(size: 12)).foregroundColor(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeButton(_ index: Int, _ title: String, _ detail: String, _ icon: String) -> some View {
        Button { select(index) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundColor(.gray).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(state.mode == index ? mint.opacity(0.12) : Color.white.opacity(0.035)).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.mode == index ? mint.opacity(0.6) : Color.clear, lineWidth: 1))
                .foregroundColor(state.mode == index ? mint : .white)
        }.buttonStyle(.plain).disabled(!state.running).accessibilityLabel(title + ", " + detail)
    }
}
