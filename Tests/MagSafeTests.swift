import Foundation
final class FakeLED: MagSafeAccess {
    var value: UInt8? = 0
    var writes: [UInt8] = []
    func read() -> UInt8? { value }
    func write(_ v: UInt8) -> Bool { writes.append(v); value = v; return true }
}
@main struct MagSafeTests {
    static func main() throws {
        assert(MagSafePolicy.night(minute: 1430, start: 1380, end: 420))
        assert(MagSafePolicy.night(minute: 0, start: 1380, end: 420))
        assert(!MagSafePolicy.night(minute: 420, start: 1380, end: 420))
        assert(!MagSafePolicy.night(minute: 12, start: 12, end: 12))
        assert(MagSafePolicy.mode(enabled: true, nightEnabled: true, minute: 0, start: 1380, end: 420, running: true, dark: false) == 1)
        assert(MagSafePolicy.mode(enabled: true, nightEnabled: false, minute: 0, start: 0, end: 0, running: nil, dark: false) == 0)
        let path = NSTemporaryDirectory()+UUID().uuidString
        let led = FakeLED(); let c = MagSafeController(led: led, journal: path)
        c.tick(); assert(led.writes.isEmpty)
        c.command(2); c.tick(); assert(Set(led.writes) == Set([1,4]))
        c.command(3); assert(led.value == 3)
        c.command(1); assert(led.value == 1)
        c.command(0); assert(led.value == 0); assert(!FileManager.default.fileExists(atPath:path))
        c.command(3); led.value = 4; c.tick(); assert(led.value == 4) // external override
        c.command(0); led.value = 0; c.command(3)
        let restored = MagSafeController(led: led, journal:path)
        assert(led.value == 0); assert(restored.restore())
        restored.command(3); assert(led.value == 3)
        Thread.sleep(forTimeInterval: 15.1)
        restored.tick(); assert(led.value == 0) // lost app heartbeat expires
        assert(!FileManager.default.fileExists(atPath: path))
        print("MagSafe policy, blinking, ownership and restart recovery passed")
    }
}
