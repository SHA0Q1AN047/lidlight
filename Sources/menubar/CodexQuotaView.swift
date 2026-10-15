import SwiftUI

struct CodexQuotaView: View {
    @ObservedObject var quota: CodexQuota
    private let mint = LidlightPalette.iris
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Codex quota").font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Remaining account quota, not a token balance.").font(.system(size: 12)).foregroundColor(.secondary)
            Text("Sunny ≥50% · Cloudy 20–49% · Sunset <20%\nA sleeping moon means the limit was reached.").font(.system(size: 10)).foregroundColor(.secondary)
            Toggle("Check Codex quota", isOn: $quota.enabled)
            Toggle("Notify when quota is available again", isOn: Binding(get: { quota.recoveryNotifications }, set: quota.setRecoveryNotifications))
            Text("Enable notifications to hear when a successful check confirms recovery from an observed limit. Checks run every 5 minutes while the display is awake.").font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let message = quota.notificationMessage { Text(message).font(.system(size: 11)).foregroundColor(.orange) }
            if quota.enabled {
                ForEach(quota.windows) { window in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            PixelQuotaWeather(sky: QuotaSky.overview(windows: [window], enabled: quota.enabled, busy: quota.busy, failed: quota.message != nil, updated: quota.updated, now: Date())).frame(width: 24, height: 24)
                            Text(window.label).fontWeight(.medium)
                            Spacer()
                            Text(window.resetsAt <= Date() ? "Reset pending" : "\(window.remaining)% left").foregroundColor(window.remaining < 20 ? .orange : mint)
                        }
                        if let trend = quota.history.trend(for: window), quota.message == nil {
                            Text(trend.label).font(.system(size: 10)).foregroundColor(.secondary)
                        } else {
                            Text("Trend needs 3 readings across 10+ minutes, within the same reset window.").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule().fill(window.remaining < 20 ? Color.orange : mint)
                                    .frame(width: geometry.size.width * CGFloat(window.remaining) / 100)
                            }
                        }.frame(height: 5).accessibilityLabel("\(window.remaining) percent remaining")
                        Text("Resets \(window.resetsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US"))))")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }.padding(16).lidlightCard(radius: 14)
                }
                Button { quota.refresh(force: true) } label: { Label(quota.busy ? "Checking…" : "Refresh quota", systemImage: "arrow.clockwise") }
                    .buttonStyle(GlassActionStyle()).foregroundColor(mint).disabled(quota.busy)
                if let updated = quota.updated {
                    Text("Last successful update: \(updated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US"))))").font(.system(size: 10)).foregroundColor(.secondary)
                }
                if let message = quota.message {
                    Text(message).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                    if !quota.windows.isEmpty { Text("The readings above are cached.").foregroundColor(.orange) }
                }
                Text("Uses your local Codex sign-in. No API key or copied credentials. Checks at most once every five minutes automatically; manual refresh is available.")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Clear local quota history") { quota.history.clear(); quota.objectWillChange.send() }.buttonStyle(.plain).font(.system(size: 11))
                Text("One quota point is one percentage point. Trends show observed usage, not token counts or a forecast of remaining time.").font(.system(size: 10)).foregroundColor(.secondary)
                Text("This meter covers Codex account limits, not every ChatGPT model's message limit.")
                    .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
    }
}
