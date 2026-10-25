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
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { connection = 0; return }
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
        guard packet(key, 6, size: count, bytes: [value]) != nil else { return false }
        // System is a handoff command, not an observable color. Firmware may
        // immediately report green/amber after accepting it.
        if value == 0 { return true }
        // Adapter LED reporting can lag an acknowledged write slightly.
        for attempt in 0..<4 {
            if read() == value { return true }
            if attempt < 3 { Thread.sleep(forTimeInterval: 0.05) }
        }
        return false
    }
}

final class MagSafeController {
    private var led: MagSafeAccess?
    private var last: UInt8?
    private var owned = false
    private var deadline: TimeInterval = 0
    private var mode: UInt64 = 0
    private var phaseStart: TimeInterval = 0
    private var mismatches = 0
    private let uptime: () -> TimeInterval
    private let statusPath: String
    private var blocked = false
    private let journal: String
    init(led: MagSafeAccess? = nil, journal: String = "/var/db/lidlight-magsafe-owned", statusPath: String = MagSafeStatus.path, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.led = led; self.journal = journal; self.uptime = uptime; self.statusPath = statusPath
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
        if value == 0 { blocked = false; mismatches = 0 }
        guard !blocked else { return }
        let changed = mode != value
        mode = value; deadline = uptime() + 15
        if changed { phaseStart = uptime(); mismatches = 0 }
        // Heartbeats renew the lease only; they never advance the blink phase.
        if changed || value == 0 { tick() }
    }
    func tick() {
        var status = MagSafeStatus()
        if led == nil { led = MagSafeLED() }
        guard let current = led?.read() else {
            status.message = "No supported ACLC LED interface. Requires compatible Apple Silicon MagSafe 3 hardware."
            publish(status); return
        }
        status.supported = true
        if blocked {
            status.message = "LED is being changed repeatedly. Turn off other LED controls, then disable and re-enable this feature."
            publish(status); return
        }
        guard mode != 0, uptime() < deadline else {
            status.message = restore() ? "LED managed by macOS" : "Could not restore LED. Reconnect MagSafe or restart the Mac."
            publish(status); return
        }
        // Firmware/adapter reconnects can briefly reset the color. Retry a transient
        // mismatch, but stop after three consecutive conflicts instead of fighting another writer.
        if owned, let last, current != last { mismatches += 1 } else { mismatches = 0 }
        if mismatches >= 3 {
            mode = 0; blocked = true
            status.message = "LED is being changed repeatedly. Turn off other LED controls, then disable and re-enable this feature."
            owned = false; last = nil; try? FileManager.default.removeItem(atPath: journal)
            publish(status); return
        }
        if !owned {
            do { try Data("owned".utf8).write(to: URL(fileURLWithPath: journal), options: .atomic) }
            catch { status.message = "Could not save LED recovery state"; publish(status); return }
            owned = true
        }
        let amber = max(0, uptime() - phaseStart).truncatingRemainder(dividingBy: 4) < 2
        let desired: UInt8 = mode == 1 ? 1 : mode == 3 ? 3 : (amber ? 4 : 1)
        if current != desired {
            guard led?.write(desired) == true else {
                mode = 0; _ = restore(); status.message = "LED write could not be confirmed"; publish(status); return
            }
        }
        last = desired
        status.message = mode == 1 ? "MagSafe light off" : mode == 3 ? "Codex idle · green" : "Codex running · slow amber pulse"
        publish(status)
    }
    private func publish(_ status: MagSafeStatus) {
        if let data = try? JSONEncoder().encode(status) { try? data.write(to: URL(fileURLWithPath: statusPath), options: .atomic) }
    }
}
