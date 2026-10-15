import AppKit
import CryptoKit
import SwiftUI

struct AppVersion: Comparable, Equatable {
    let numbers: [Int]
    let prerelease: [String]
    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let components = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }
        var parsed: [Int] = []
        for component in components {
            guard !component.isEmpty, component.allSatisfy({ $0.isASCII && $0.isNumber }),
                  component.count == 1 || component.first != "0", let number = Int(component) else { return nil }
            parsed.append(number)
        }
        let suffix = parts.count == 2 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard parts.count == 1 || (!suffix.isEmpty && suffix.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } && (!$0.allSatisfy(\.isNumber) || $0.count == 1 || $0.first != "0") })) else { return nil }
        numbers = parsed; prerelease = suffix
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            let numericA = a.allSatisfy(\.isNumber), numericB = b.allSatisfy(\.isNumber)
            if numericA && numericB { return a.count == b.count ? a < b : a.count < b.count }
            if numericA != numericB { return numericA }
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct GitHubUpdate: Equatable {
    let tag: String
    let version: AppVersion
    let notes: String
    let url: URL
    let bytes: Int
    let digest: String
    static let maxBytes = 100 * 1024 * 1024

    static func releases(_ data: Data, previews: Bool) throws -> [Self] {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UpdateError.invalidFeed
        }
        return entries.compactMap { entry in
            guard entry["draft"] as? Bool == false,
                  let isPreview = entry["prerelease"] as? Bool,
                  previews || !isPreview,
                  let tag = entry["tag_name"] as? String, let version = AppVersion(tag),
                  previews || version.prerelease.isEmpty,
                  let assets = entry["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { $0["name"] as? String == "Lidlight.pkg" && $0["state"] as? String == "uploaded" }),
                  let link = asset["browser_download_url"] as? String, let url = URL(string: link),
                  url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil, url.port == nil,
                  url.query == nil, url.fragment == nil,
                  url.path == "/SHA0Q1AN047/lidlight/releases/download/\(tag)/Lidlight.pkg",
                  let bytes = asset["size"] as? Int, bytes > 0, bytes <= maxBytes else { return nil }
            // Missing digests remain visible, but cannot be installed inside the app.
            let digest = asset["digest"] as? String ?? ""
            return Self(tag: tag, version: version, notes: String((entry["body"] as? String ?? "No release notes.").prefix(12_000)), url: url, bytes: bytes, digest: digest)
        }.sorted { $0.version > $1.version }
    }
    var hasDigest: Bool {
        digest.hasPrefix("sha256:") && digest.count == 71 && digest.dropFirst(7).allSatisfy { $0.isHexDigit && $0.isASCII }
    }
    func verify(_ data: Data) throws {
        guard hasDigest else { throw UpdateError.missingDigest }
        guard data.count == bytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == digest.dropFirst(7).lowercased() else { throw UpdateError.checksum }
    }
}

enum UpdateError: LocalizedError {
    case invalidFeed, missingDigest, checksum, http(Int), invalidVersion, installer
    var errorDescription: String? {
        switch self {
        case .invalidFeed: return "GitHub returned an unreadable release list. Try again later."
        case .missingDigest: return "This release has no SHA-256 digest. Ask the publisher to upload Lidlight.pkg again."
        case .checksum: return "The download did not match the release. Nothing was opened; try downloading again."
        case .http(403), .http(429): return "GitHub's request limit was reached. Try again later."
        case .http(let code): return "GitHub could not complete the request (\(code)). Try again later."
        case .invalidVersion: return "The installed app version is invalid. Reinstall a published version."
        case .installer: return "macOS could not open the installer. Try downloading again."
        }
    }
}

private final class UpdateRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let hosts = ["api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"]
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, let host = url.host, hosts.contains(host) else { completionHandler(nil); return }
        completionHandler(request)
    }
}

@MainActor final class AppUpdater: ObservableObject {
    @Published private(set) var available: GitHubUpdate?
    @Published private(set) var checking = false
    @Published private(set) var downloading = false
    @Published private(set) var checked: Date?
    @Published private(set) var message: String?
    @Published var automatic: Bool { didSet { defaults.set(automatic, forKey: "automaticUpdateChecks") } }
    @Published var previews: Bool {
        didSet { defaults.set(previews, forKey: "previewUpdates"); available = nil; message = nil; check(force: true) }
    }
    let currentVersion: String
    private let defaults: UserDefaults
    private let session: URLSession
    private let openInstaller: (URL) -> Bool
    private var lastAttempt: Date

    init(currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0", defaults: UserDefaults = .standard, session: URLSession? = nil, openInstaller: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.currentVersion = currentVersion; self.defaults = defaults; self.openInstaller = openInstaller
        automatic = defaults.object(forKey: "automaticUpdateChecks") as? Bool ?? true
        previews = defaults.bool(forKey: "previewUpdates")
        lastAttempt = defaults.object(forKey: "lastUpdateAttempt") as? Date ?? .distantPast
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = session ?? URLSession(configuration: configuration, delegate: UpdateRedirectPolicy(), delegateQueue: nil)
    }
    func check(force: Bool = false) {
        guard !checking, !downloading, force || (automatic && Date().timeIntervalSince(lastAttempt) >= 6 * 3600) else { return }
        checking = true; message = nil; lastAttempt = Date()
        defaults.set(lastAttempt, forKey: "lastUpdateAttempt")
        let includePreviews = previews
        Task {
            defer { checking = false; if previews != includePreviews { check(force: true) } }
            do {
                guard let current = AppVersion(currentVersion) else { throw UpdateError.invalidVersion }
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/SHA0Q1AN047/lidlight/releases?per_page=30")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                request.setValue("Lidlight/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                try Self.validate(response)
                guard data.count <= 2 * 1024 * 1024 else { throw UpdateError.invalidFeed }
                let releases = try GitHubUpdate.releases(data, previews: includePreviews)
                // A changed channel invalidates the in-flight result.
                guard previews == includePreviews else { return }
                available = releases.first(where: { $0.version > current })
                checked = Date()
                if available == nil { message = releases.isEmpty ? "No installable releases are available on this channel." : "You're up to date." }
            } catch { message = error.localizedDescription }
        }
    }
    func downloadAndInstall() {
        guard let release = available, !checking, !downloading else { return }
        guard release.hasDigest else { message = UpdateError.missingDigest.localizedDescription; return }
        downloading = true; message = "Downloading \(release.tag)…"
        Task {
            defer { downloading = false }
            do {
                var request = URLRequest(url: release.url)
                request.setValue("Lidlight/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                try Self.validate(response)
                try release.verify(data)
                let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let directory = cache.appendingPathComponent("com.lidlight.updates/\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let package = directory.appendingPathComponent("Lidlight.pkg")
                do {
                    try data.write(to: package, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: package.path)
                    let previous = defaults.string(forKey: "pendingUpdateVersion")
                    defaults.set(release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag,forKey: "pendingUpdateVersion")
                    guard openInstaller(package) else {
                        if let previous { defaults.set(previous,forKey: "pendingUpdateVersion") } else { defaults.removeObject(forKey: "pendingUpdateVersion") }
                        throw UpdateError.installer
                    }
                } catch { try? FileManager.default.removeItem(at: directory); throw error }
                message = "Installer opened. Follow the macOS steps to finish updating; Lidlight will restart."
            } catch { message = error.localizedDescription }
        }
    }
    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidFeed }
        guard (200...299).contains(http.statusCode) else { throw UpdateError.http(http.statusCode) }
    }
}
