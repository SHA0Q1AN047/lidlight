import Foundation
import IOKit

// ACLC protocol values documented by MagHue; independent implementation.
protocol MagSafeAccess: AnyObject { func read() -> UInt8?; func write(_ value: UInt8) -> Bool }
final class MagSafeLED: MagSafeAccess {
    private var connection: io_connect_t = 0
    private(set) var key: String?
    private var count = 0
    init() {
        #if arch(arm64)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 1, &connection) == KERN_SUCCESS else { connection = 0; return }
        _ = IOConnectCallMethod(connection, 0, nil, 0, nil, 0, nil, nil, nil, nil)
        for (candidate, size, type) in [("ACLC", 1, "ui8 "), ("ACLC", 1, "hex_")] {
            guard let info = packet(candidate, 9, size: 0),
                  Array(info[28..<32]) == [UInt8(size), 0, 0, 0],
                  String(bytes: info[32..<36].reversed(), encoding: .ascii) == type,
                  (info[36] & 0x40) != 0 else { continue }
            key = candidate; count = size
            break
        }
        #endif
    }
    deinit { if connection != 0 {
        _ = IOConnectCallMethod(connection, 1, nil, 0, nil, 0, nil, nil, nil, nil)
        IOServiceClose(connection)
    } }
    private func packet(_ name: String, _ command: UInt8, size: Int, bytes: [UInt8] = []) -> [UInt8]? {
        guard connection != 0, name == "ACLC", [5, 6, 9].contains(command), size <= 4 else { return nil }
        var input = [UInt8](repeating: 0, count: 80), output = input
        let code = name.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        for i in 0..<4 { input[i] = UInt8(truncatingIfNeeded: code >> (8 * i)) }
        input[28] = UInt8(size); input[42] = command
        for (i, byte) in bytes.enumerated() { input[48+i] = byte }
        var length = 80
        let result = input.withUnsafeBytes { request in
            output.withUnsafeMutableBytes { reply in
                IOConnectCallStructMethod(connection, 2, request.baseAddress, 80, reply.baseAddress, &length)
            }
        }
        guard result == KERN_SUCCESS, length == 80, output[40] == 0 else { return nil }
        return output
    }
    func read() -> UInt8? {
        guard let key, let reply = packet(key, 5, size: count), [0, 1, 3, 4].contains(reply[48]) else { return nil }
        return reply[48]
    }
    func write(_ value: UInt8) -> Bool {
        guard [0, 1, 3, 4].contains(value), let key else { return false }
        _ = packet(key, 6, size: count, bytes: [value])
        return read() == value
    }
}

final class MagSafeController {
    private var led: MagSafeAccess?
    private var last: UInt8?
    private var owned = false
    private var deadline = Date.distantPast
    private var mode: UInt64 = 0
    private var phase = false
    private var blocked = false
    private let journal: String
    init(led: MagSafeAccess? = nil, journal: String = "/var/db/lidlight-magsafe-owned") {
        self.led = led; self.journal = journal
        owned = FileManager.default.fileExists(atPath: journal)
        if owned { _ = restore() }
    }
    @discardableResult func restore() -> Bool {
        guard owned else { return true }
        if led == nil { led = MagSafeLED() }
        guard led?.write(0) == true else { return false }
        owned = false; last = nil
        try? FileManager.default.removeItem(atPath: journal)
        return true
    }
    func command(_ value: UInt64) {
        guard value <= 3 else { return }
        if value == 0 { blocked = false }
        guard !blocked else { return }
        mode = value; deadline = Date().addingTimeInterval(15)
        tick()
    }
    func tick() {
        var status = MagSafeStatus()
        if led == nil { led = MagSafeLED() }
        guard let current = led?.read() else {
            status.message = "No supported ACLC LED interface. Requires compatible Apple Silicon MagSafe 3 hardware."
            publish(status); return
        }
        status.supported = true
        guard mode != 0, Date() < deadline else {
            status.message = restore() ? "LED managed by macOS" : "Could not restore LED. Reconnect MagSafe or restart the Mac."
            publish(status); return
        }
        // An explicit enabled mode acquires control; stop if another writer changes it later.
        if owned && last != nil && current != last {
            mode = 0; blocked = true
            status.message = "LED changed externally. Disable other LED tools before enabling this feature."
            // Only relinquish a live ownership claim, never overwrite the external value.
            owned = false; last = nil; try? FileManager.default.removeItem(atPath: journal)
            publish(status); return
        }
        if !owned {
            do { try Data("owned".utf8).write(to: URL(fileURLWithPath: journal), options: .atomic) }
            catch { status.message = "Could not save LED recovery state"; publish(status); return }
            owned = true
        }
        phase.toggle()
        let desired: UInt8 = mode == 1 ? 1 : mode == 3 ? 3 : (phase ? 4 : 1)
        if current != desired {
            guard led?.write(desired) == true else {
                mode = 0; _ = restore(); status.message = "LED write could not be confirmed"; publish(status); return
            }
        }
        last = desired
        status.message = mode == 1 ? "MagSafe light off" : mode == 3 ? "Codex idle · green" : "Codex running · blinking amber"
        publish(status)
    }
    private func publish(_ status: MagSafeStatus) {
        if let data = try? JSONEncoder().encode(status) { try? data.write(to: URL(fileURLWithPath: MagSafeStatus.path), options: .atomic) }
    }
}
