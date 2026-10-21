import Foundation

final class FakeGate: ChargeGateAccess {
    var value: Bool? = false
    var fail = false
    var writes: [Bool] = []
    func paused() -> Bool? { value }
    func setPaused(_ paused: Bool) -> Bool {
        writes.append(paused)
        if fail { return false }
        value = paused; return true
    }
}
@main struct Test {
    static func main() throws {
        for p in 0...100 {
            assert(ChargeLimitPolicy.pause(enabled: true, fullOnce: false, ac: true, percent: p, previouslyPaused: false) == (p >= 80))
            assert(ChargeLimitPolicy.pause(enabled: true, fullOnce: false, ac: true, percent: p, previouslyPaused: true) == (p > 75))
            assert(!ChargeLimitPolicy.pause(enabled: true, fullOnce: true, ac: true, percent: p, previouslyPaused: true))
            assert(!ChargeLimitPolicy.pause(enabled: true, fullOnce: false, ac: false, percent: p, previouslyPaused: true))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config").path
        let output = directory.appendingPathComponent("status").path
        let gate = FakeGate()
        var percent = 80; var ac = true
        func controller(native: Bool = false) -> ChargeController {
            ChargeController(path: path, statusPath: output, makeGate: { gate }, batteryReader: { (percent, ac, true) }, nativeOverride: native)
        }
        func status() throws -> ChargeLimitStatus { try JSONDecoder().decode(ChargeLimitStatus.self, from: Data(contentsOf: URL(fileURLWithPath: output))) }
        let c = controller()
        c.tick(force: true); assert(gate.writes.isEmpty) // Default off never writes.
        c.command(1); assert(gate.value == true); assert(try! status().enabled)
        percent = 78; c.tick(force: true); assert(gate.value == true)
        percent = 75; c.tick(force: true); assert(gate.value == false)
        c.prepareSleep(); assert(gate.value == true)
        c.tick(force: true); assert(gate.value == false)
        percent = 80; c.tick(force: true); assert(gate.value == true)
        c.command(2); assert(gate.value == false); assert(try! status().fullOnce)
        ac = false; c.tick(force: true); assert(!(try! status().fullOnce))
        ac = true; c.tick(force: true); assert(gate.value == true)
        assert(controller().restore()); assert(gate.value == false) // Crash journal recovery.
        controller().tick(force: true); assert(gate.value == true) // Persistent limit.
        controller(native: true).tick(force: true); assert(gate.value == false); assert(try! status().systemManaged)
        let d = controller(); d.command(0); assert(!(try! status().enabled))
        gate.value = true; let count = gate.writes.count
        d.command(1); assert(gate.writes.count == count); assert(!(try! status().supported)) // Other tool untouched.
        gate.value = false; gate.fail = true
        d.command(1); assert(!(try! status().paused)); assert(try! status().message.contains("Could not"))
        gate.fail = false; d.tick(force: true)
        assert(!(try! status().message.contains("Could not")))
        assert(controller().restore())
        let e = controller(); e.command(1); e.command(2)
        percent = 100; e.tick(force: true)
        assert(!(try! status().fullOnce)); assert(gate.value == true)
        let before = gate.writes.count; e.command(99); assert(gate.writes.count == before)
        gate.fail = true; assert(!controller().restore())
        gate.fail = false; assert(controller().restore())
        gate.value = nil
        controller().tick(force: true); assert(!(try! status().supported))
        let noBattery = ChargeController(path: path, statusPath: output, makeGate: { gate }, batteryReader: { nil }, nativeOverride: false)
        noBattery.tick(force: true); assert(!(try! status().hasBattery))
        print("PASS: charge hysteresis, off, full-once/unplug, sleep/wake, restart recovery, native handoff, external ownership and failed write")
    }
}
