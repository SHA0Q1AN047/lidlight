import SwiftUI

struct UpdatesView: View {
    @ObservedObject var updater: AppUpdater
    @ObservedObject var verification: InstallVerification
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Updates").font(.system(size: 28, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 10) {
                Text("Running app · \(updater.currentVersion)")
                if let status = verification.status {
                    Text("Installed app · \(status.installed ?? "Unavailable")")
                    Text("Running service · \(status.service ?? "Unverified")")
                    Label(verification.updateConfirmed ? "Update confirmed" : status.summary, systemImage: status.verified ? "checkmark.seal.fill" : "exclamationmark.circle")
                        .foregroundColor(status.verified ? .accentColor : .orange)
                } else { Text("Checking installation…").foregroundColor(.secondary) }
            }.font(.system(size: 12)).padding(14).frame(maxWidth: .infinity, alignment: .leading).lidlightCard()
            Toggle("Automatically check for updates", isOn: $updater.automatic)
            Toggle("Include preview releases", isOn: $updater.previews).disabled(updater.checking || updater.downloading)
            Text("Checks GitHub every six hours while Lidlight is running. Downloads begin only when you choose Update.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            if let release = updater.available {
                VStack(alignment: .leading, spacing: 14) {
                    Label("\(release.tag) is available", systemImage: "arrow.down.circle.fill").font(.system(size: 16, weight: .semibold)).foregroundColor(LidlightPalette.iris)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(release.bytes), countStyle: .file)).font(.system(size: 10)).foregroundColor(.secondary)
                    Button { updater.downloadAndInstall() } label: {
                        Label(updater.downloading ? "Downloading…" : "Download & update", systemImage: "arrow.down.circle")
                    }.buttonStyle(GlassActionStyle()).disabled(updater.checking || updater.downloading || !release.hasDigest)
                    if !release.hasDigest { Text(UpdateError.missingDigest.localizedDescription).font(.system(size: 11)).foregroundColor(.orange) }
                    Divider()
                    Text("What’s new").font(.system(size: 12, weight: .semibold))
                    Text(release.notes).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).lidlightCard()
            }
            Button { updater.check(force: true) } label: {
                Label(updater.checking ? "Checking…" : "Check for updates", systemImage: "arrow.clockwise")
            }.buttonStyle(GlassActionStyle()).disabled(updater.checking || updater.downloading)
            if let message = updater.message {
                Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            if let checked = updater.checked {
                Text("Last checked · \(checked.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US"))))").font(.system(size: 10)).foregroundColor(.secondary)
            }
            Text("The download is checked against GitHub's SHA-256 digest before macOS Installer opens. Updating the background service requires administrator authorization. Your settings are kept.")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Link("View GitHub releases", destination: URL(string: "https://github.com/SHA0Q1AN047/lidlight/releases")!).font(.system(size: 11))
        }.toggleStyle(SwitchToggleStyle(tint: .accentColor)).frame(maxWidth: .infinity, alignment: .leading)
    }
}
