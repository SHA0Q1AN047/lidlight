import SwiftUI

struct CodexQuotaView: View {
    @ObservedObject var quota: CodexQuota
    private let mint = Color(red: 0.48, green: 0.93, blue: 0.78)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Codex quota").font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Remaining account quota, not a token balance.").font(.system(size: 12)).foregroundColor(.gray)
            Toggle("Check Codex quota", isOn: $quota.enabled)
            if quota.enabled {
                ForEach(quota.windows) { window in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(window.label).fontWeight(.medium)
                            Spacer()
                            Text(window.resetsAt <= Date() ? "Reset pending" : "\(window.remaining)% left").foregroundColor(window.remaining < 20 ? .orange : mint)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(window.remaining < 20 ? Color.orange : mint)
                                    .frame(width: geometry.size.width * CGFloat(window.remaining) / 100)
                            }
                        }.frame(height: 5).accessibilityLabel("\(window.remaining) percent remaining")
                        Text("Resets \(window.resetsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US"))))")
                            .font(.system(size: 10)).foregroundColor(.gray)
                    }.padding(16).background(Color.white.opacity(0.045)).cornerRadius(14)
                }
                Button { quota.refresh(force: true) } label: { Label(quota.busy ? "Checking…" : "Refresh quota", systemImage: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundColor(mint).disabled(quota.busy)
                if let updated = quota.updated {
                    Text("Last successful update: \(updated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US"))))").font(.system(size: 10)).foregroundColor(.gray)
                }
                if let message = quota.message {
                    Text(message).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                    if !quota.windows.isEmpty { Text("The readings above are cached.").foregroundColor(.orange) }
                }
                Text("Uses your local Codex sign-in. No API key or copied credentials. Checks at most once every five minutes automatically; manual refresh is available.")
                    .font(.system(size: 11)).foregroundColor(.gray).fixedSize(horizontal: false, vertical: true)
                Text("This meter covers Codex account limits, not every ChatGPT model's message limit.")
                    .font(.system(size: 10)).foregroundColor(.gray).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
    }
}
