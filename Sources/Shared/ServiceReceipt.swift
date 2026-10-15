import Foundation
import Darwin

struct ServiceReceipt: Codable {
    let pid: Int32
    let version: String
    let nonce: UInt64
    static let path = "/var/run/lidlight-runtime.json"
    static func verifiedVersion(nonce: UInt64) -> String? {
        var info = stat()
        guard nonce != 0, lstat(path, &info) == 0, info.st_uid == 0, info.st_mode & 0o022 == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_size > 0, info.st_size < 2048,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let receipt = try? JSONDecoder().decode(Self.self, from: data),
              receipt.nonce == nonce else { return nil }
        var name = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(receipt.pid, &name, UInt32(name.count)) > 0,
              String(cString: name) == "/Library/PrivilegedHelperTools/lidlightd" else { return nil }
        return receipt.version
    }
    static func publish(version: String, nonce: UInt64 = 0) {
        guard getuid() == 0,
              let data = try? JSONEncoder().encode(Self(pid: getpid(),version: version,nonce: nonce)) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        chmod(path,0o644)
    }
}
