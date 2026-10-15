import Foundation
import CryptoKit

final class MockUpdateProtocol: URLProtocol {
    static var respond: (URLRequest) -> (Int, Data) = { _ in (500, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    static var holdDownloads = false
    static var held: MockUpdateProtocol?
    override func startLoading() {
        if Self.holdDownloads && request.url?.host != "api.github.com" { Self.held = self; return }
        deliver()
    }
    func deliver() {
        let (code, data) = Self.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Tests {
    static let package = Data("test package fixture".utf8)
    static let digest = "sha256:" + SHA256.hash(data: package).map { String(format: "%02x", $0) }.joined()
    static func entry(_ tag: String, preview: Bool = false, draft: Bool = false, url: String? = nil, hash: String? = digest) -> [String: Any] {
        ["tag_name": tag, "prerelease": preview, "draft": draft, "body": "Release notes", "assets": [
            ["name": "Lidlight.pkg", "state": "uploaded", "size": package.count, "digest": hash as Any? ?? NSNull(),
             "browser_download_url": url ?? "https://github.com/SHA0Q1AN047/lidlight/releases/download/\(tag)/Lidlight.pkg"]
        ]]
    }
    static func feed(_ entries: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: entries) }
    static func expect(_ value: Bool, _ label: String) { if !value { fatalError(label) } }
    @MainActor static func settle(_ done: () -> Bool) async {
        for _ in 0..<300 { if done() { return }; try! await Task.sleep(nanoseconds: 10_000_000) }
        fatalError("Async updater timed out")
    }
    @MainActor static func main() async throws {
        expect(AppVersion("v1.10.0")! > AppVersion("1.9.9")!, "numeric comparison")
        expect(AppVersion("1.0.0")! > AppVersion("1.0.0-rc.2")!, "stable after preview")
        expect(AppVersion("1.0.0-rc.10")! > AppVersion("1.0.0-rc.2")!, "numeric preview order")
        expect(AppVersion("1.0.0-rc")! > AppVersion("1.0.0-1")!, "numeric preview before alphabetic")
        for bad in ["1.2", "1.2.3.4", "01.2.3", "1.2.3-", "1.2.3-rc.01", "1.2.3/evil", "999999999999999999999999.0.0"] {
            expect(AppVersion(bad) == nil, "Reject malformed version \(bad)")
        }
        let releases = try GitHubUpdate.releases(feed([entry("v1.9.0"), entry("v1.10.0"), entry("v9.0.0", preview: true), entry("v8.0.0", draft: true)]), previews: false)
        expect(releases.map(\.tag) == ["v1.10.0", "v1.9.0"], "Stable filtering and newest numeric version")
        expect(try GitHubUpdate.releases(feed([entry("v9.0.0-rc.1", preview: true)]), previews: true).count == 1, "Opt-in preview")
        for url in ["http://github.com/SHA0Q1AN047/lidlight/releases/download/v2.0.0/Lidlight.pkg", "https://evil.example/Lidlight.pkg", "https://github.com/other/repo/releases/download/v2.0.0/Lidlight.pkg", "https://github.com/SHA0Q1AN047/lidlight/releases/download/v2.0.0/Lidlight.pkg?evil=1"] {
            expect(try GitHubUpdate.releases(feed([entry("v2.0.0", url: url)]), previews: true).isEmpty, "Reject foreign URL")
        }
        try releases[0].verify(package)
        do { try releases[0].verify(Data("corrupt".utf8)); fatalError("Corrupt package accepted") } catch UpdateError.checksum {}
        let noHash = try GitHubUpdate.releases(feed([entry("v2.0.0", hash: nil)]), previews: false)[0]
        expect(!noHash.hasDigest, "Missing digest cannot install")
        do { try noHash.verify(package); fatalError("Missing digest accepted") } catch UpdateError.missingDigest {}

        let suite = "com.lidlight.updater-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockUpdateProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var opened: URL?
        let updater = AppUpdater(currentVersion: "1.0.0", defaults: defaults, session: session, openInstaller: { opened = $0; return true })
        let releaseData = feed([entry("v2.0.0")])
        MockUpdateProtocol.respond = { request in (200, request.url!.host == "api.github.com" ? releaseData : package) }
        updater.check(force: true)
        await settle { !updater.checking }
        expect(updater.available?.tag == "v2.0.0", "Check finds newer version")
        updater.downloadAndInstall()
        await settle { !updater.downloading }
        expect(opened != nil, "Verified package handed to installer")
        expect(defaults.string(forKey: "pendingUpdateVersion") == "2.0.0", "Installer handoff records expected version, not success")
        expect(try Data(contentsOf: opened!) == package, "Installer file matches downloaded bytes")
        try FileManager.default.removeItem(at: opened!.deletingLastPathComponent())
        opened = nil
        defaults.set("9.9.9",forKey: "pendingUpdateVersion")
        let failedOpen = AppUpdater(currentVersion: "1.0.0",defaults: defaults,session: session,openInstaller: { _ in false })
        failedOpen.check(force: true)
        await settle { !failedOpen.checking }
        failedOpen.downloadAndInstall()
        await settle { !failedOpen.downloading }
        expect(failedOpen.message == UpdateError.installer.localizedDescription && defaults.string(forKey: "pendingUpdateVersion") == "9.9.9", "Failed installer open restores prior pending target")
        MockUpdateProtocol.respond = { _ in (200, Data("corrupt".utf8)) }
        updater.downloadAndInstall()
        await settle { !updater.downloading }
        expect(opened == nil && updater.message == UpdateError.checksum.localizedDescription, "Corruption never launches installer")
        MockUpdateProtocol.respond = { _ in (429, Data()) }
        updater.check(force: true)
        await settle { !updater.checking }
        expect(updater.message == UpdateError.http(429).localizedDescription, "Rate limit shown honestly")
        expect(updater.available?.tag == "v2.0.0", "Transient check failure preserves known update")
        MockUpdateProtocol.respond = { _ in (200, feed([entry("v1.0.0"), entry("v0.9.0")])) }
        updater.check(force: true)
        await settle { !updater.checking }
        expect(updater.available == nil, "Equal or older releases never offered")
        updater.automatic = false
        updater.check()
        expect(!updater.checking, "Automatic checks respect opt-out")
        MockUpdateProtocol.respond = { request in
            (200, request.url!.host == "api.github.com" ? feed([entry("v3.0.0",preview: true),entry("v2.0.0")]) : package)
        }
        updater.previews = true
        await settle { !updater.checking }
        expect(updater.available?.tag == "v3.0.0", "Preview selected for race test")
        MockUpdateProtocol.holdDownloads = true
        updater.downloadAndInstall()
        await settle { MockUpdateProtocol.held != nil }
        updater.previews = false
        MockUpdateProtocol.holdDownloads = false
        MockUpdateProtocol.held!.deliver(); MockUpdateProtocol.held = nil
        await settle { !updater.downloading && !updater.checking && updater.available?.tag == "v2.0.0" }
        expect(opened == nil,"Changing channel during download must never launch the old-channel installer")
        defaults.set(true,forKey: "automaticUpdateChecks")
        defaults.set(Date().addingTimeInterval(86400),forKey: "lastUpdateAttempt")
        let corrected = AppUpdater(currentVersion: "1.0.0",defaults: defaults,session: session,openInstaller: { _ in false })
        corrected.check()
        expect(corrected.checking,"A future stored timestamp cannot freeze automatic checks after clock correction")
        await settle { !corrected.checking }
        if CommandLine.arguments.contains("--live") {
            defaults.set(true, forKey: "previewUpdates")
            var downloaded: URL?
            let live = AppUpdater(currentVersion: "0.0.0", defaults: defaults, openInstaller: { downloaded = $0; return true })
            live.check(force: true)
            for _ in 0..<400 { if !live.checking { break }; try await Task.sleep(nanoseconds: 100_000_000) }
            expect(live.available != nil, "Live GitHub discovery: \(live.message ?? "no release")")
            live.downloadAndInstall()
            for _ in 0..<400 { if !live.downloading { break }; try await Task.sleep(nanoseconds: 100_000_000) }
            expect(downloaded != nil, "Live package digest: \(live.message ?? "no download")")
            try FileManager.default.removeItem(at: downloaded!.deletingLastPathComponent())
            print("PASS: live GitHub discovery, asset download and SHA-256 verification; installer launch mocked")
        }
        print("PASS: versions, release channel, URL allowlist, digest validation, download/installer handoff, corruption, rate limit, downgrade and opt-out")
    }
}
