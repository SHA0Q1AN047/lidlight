import Foundation
import IOKit
import IOKit.ps

// Charge-key metadata and values follow Battery Toolkit's BSD-3-Clause interface.
// Copyright (C) 2022 - 2025 Marvin Häuser. See Resources/ThirdPartyNotices.txt.
// Only the charging gate is writable; adapter power and arbitrary SMC keys are excluded.
protocol ChargeGateAccess: AnyObject {
    func paused() -> Bool?
    func setPaused(_ paused: Bool) -> Bool
}
final class ChargeGate: ChargeGateAccess {
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
        for (candidate, size, type) in [("CHTE", 4, "ui32"), ("CH0C", 1, "hex_")] {
            guard let info = packet(candidate, 9, size: 0),
                  Array(info[28..<32]) == [UInt8(size), 0, 0, 0],
                  String(bytes: info[32..<36].reversed(), encoding: .ascii) == type,
                  info[36] == 0xD4 else { continue }
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
        guard connection != 0, ["CHTE", "CH0C"].contains(name), [5, 6, 9].contains(command), size <= 4 else { return nil }
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
    func paused() -> Bool? {
        guard let key, let reply = packet(key, 5, size: count) else { return nil }
        let bytes = Array(reply[48..<(48+count)])
        if bytes == Array(repeating: UInt8(0), count: count) { return false }
        if bytes == [UInt8(1)] + Array(repeating: UInt8(0), count: count-1) { return true }
        return nil // Unknown values are not guessed or overwritten.
    }
    func setPaused(_ paused: Bool) -> Bool {
        guard let key else { return false }
        let bytes = [UInt8(paused ? 1 : 0)] + Array(repeating: UInt8(0), count: count-1)
        _ = packet(key, 6, size: count, bytes: bytes)
        return self.paused() == paused
    }
}

final class ChargeController {
    private struct Saved: Codable {
        var enabled = false
        var ownsPause = false
    }
    private let path: String
    private let statusPath: String
    private let makeGate: () -> ChargeGateAccess
    private let batteryReader: (() -> (percent: Int, ac: Bool, charging: Bool)?)?
    private let nativeOverride: Bool?
    private var saved: Saved
    private var gate: ChargeGateAccess?
    private var fullOnce = false
    private var fullDeadline = Date.distantPast
    private var wasAC = false
    private var lastTick = Date.distantPast
    private var status = ChargeLimitStatus()
    private var failure: String?
    init(path: String = "/var/db/lidlight-charge.json", statusPath: String = ChargeLimitStatus.path,
         makeGate: @escaping () -> ChargeGateAccess = { ChargeGate() },
         batteryReader: (() -> (percent: Int, ac: Bool, charging: Bool)?)? = nil,
         nativeOverride: Bool? = nil) {
        self.path = path; self.statusPath = statusPath; self.makeGate = makeGate
        self.batteryReader = batteryReader; self.nativeOverride = nativeOverride
        saved = (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
    }
    private func save() -> Bool {
        do { try JSONEncoder().encode(saved).write(to: URL(fileURLWithPath: path), options: .atomic); return true }
        catch { failure = "Could not save charging state."; return false }
    }
    private func battery() -> (percent: Int, ac: Bool, charging: Bool)? {
        if let batteryReader { return batteryReader() }
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        for source in IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef] {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let percent = d[kIOPSCurrentCapacityKey] as? Int, (0...100).contains(percent) else { continue }
            return (percent, d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue, d[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }
    private var nativeLimit: Bool {
        if let nativeOverride { return nativeOverride }
        #if arch(arm64)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0))
        #else
        return false
        #endif
    }
    @discardableResult func restore() -> Bool {
        guard saved.ownsPause else { return true }
        if gate == nil { gate = makeGate() }
        guard gate?.setPaused(false) == true else { failure = "Could not restore charging. Retry or restart the Mac."; return false }
        saved.ownsPause = false
        failure = nil
        return save()
    }
    func command(_ value: UInt64) {
        guard value <= 2 else { return }
        tick(force: true)
        failure = nil
        if value == 0 {
            saved.enabled = false; fullOnce = false
            _ = save(); _ = restore()
        } else if status.supported {
            if value == 1 { saved.enabled = true; fullOnce = false; _ = save() }
            if value == 2 && saved.enabled {
                fullOnce = true; fullDeadline = Date().addingTimeInterval(24*3600)
                _ = restore()
            }
        }
        tick(force: true)
    }
    func tick(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastTick) >= 5 else { return }
        lastTick = Date()
        status = ChargeLimitStatus()
        status.enabled = saved.enabled; status.fullOnce = fullOnce
        guard let battery = battery() else {
            _ = restore(); status.message = "No internal battery detected."; publish(); return
        }
        status.hasBattery = true; status.charging = battery.charging
        status.systemManaged = nativeLimit
        if nativeLimit {
            _ = restore()
            status.message = failure ?? "Use macOS Charge Limit in Battery settings."
            publish(); return
        }
        if gate == nil { gate = makeGate() }
        guard let paused = gate?.paused() else {
            gate = nil
            status.message = "Charging control unavailable on this Mac or firmware."
            publish(); return
        }
        // A gate set by another utility is not ours to release or take over.
        status.supported = !paused || saved.ownsPause
        if !status.supported {
            status.message = "Charging is controlled by another tool. Disable it first."
            publish(); return
        }
        if fullOnce && (battery.percent >= 100 || wasAC && !battery.ac || Date() >= fullDeadline) { fullOnce = false }
        wasAC = battery.ac
        let want = ChargeLimitPolicy.pause(enabled: saved.enabled, fullOnce: fullOnce, ac: battery.ac, percent: battery.percent, previouslyPaused: paused)
        if want && !paused {
            // Journal ownership before writing, allowing recovery after a crash.
            saved.ownsPause = true
            if save() {
                failure = gate?.setPaused(true) == true ? nil : "Could not confirm charging pause."
            }
        } else if !want && saved.ownsPause { _ = restore() }
        status.enabled = saved.enabled
        status.fullOnce = fullOnce
        let confirmed = gate?.paused()
        status.paused = confirmed == true
        if confirmed == nil { status.supported = false; failure = "Charging state could not be confirmed." }
        status.message = failure ?? (fullOnce ? "Charging to 100% once · ends on unplug, restart or after 24h" : saved.enabled ? (status.paused ? "Paused at the 80% limit" : "80% limit active · resumes at 75%") : "Charging managed by macOS")
        publish()
    }
    /// Pause before sleep so the polling controller cannot overshoot while suspended.
    func prepareSleep() {
        guard saved.enabled, !fullOnce, !nativeLimit, let battery = battery(), battery.ac else { return }
        if gate == nil { gate = makeGate() }
        guard let paused = gate?.paused(), !paused else { return }
        saved.ownsPause = true
        if save(), gate?.setPaused(true) != true { failure = "Could not pause charging before sleep." }
    }
    private func publish() {
        status.updated = Date()
        if let data = try? JSONEncoder().encode(status) { try? data.write(to: URL(fileURLWithPath: statusPath), options: .atomic) }
    }
}
