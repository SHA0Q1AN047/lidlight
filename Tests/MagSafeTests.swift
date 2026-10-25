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
        assert(MagSafePolicy.mode(enabled: true, nightEnabled: true, minute: 0, start: 1380, end: 420, running: true, dark: false) == 2)
        assert(MagSafePolicy.mode(enabled: true, nightEnabled: false, minute: 0, start: 0, end: 0, running: nil, dark: false) == 0)
        // Activity overrides darkness only when activity monitoring is enabled.
        for enabled in [false, true] {
            for dark in [false, true] {
                for night in [false, true] {
                    for minute in [0, 720] {
                        for running: Bool? in [true, false, nil] {
                            let off = dark || (night && minute == 0)
                            let expected: UInt64 = enabled && running == true ? 2 : off ? 1 : enabled && running == false ? 3 : 0
                            assert(MagSafePolicy.mode(enabled: enabled, nightEnabled: night, minute: minute, start: 1380, end: 420, running: running, dark: dark) == expected)
                        }
                    }
                }
            }
        }
        let path = NSTemporaryDirectory()+UUID().uuidString
        var now: TimeInterval = 100
        let led = FakeLED(); let statusPath = path + "-status"
        defer { try? FileManager.default.removeItem(atPath: statusPath) }
        let c = MagSafeController(led: led, journal: path, statusPath: statusPath, uptime: { now })
        c.tick(); assert(led.writes.isEmpty)
        c.command(2); assert(led.value == 4)
        for second in 0..<32 {
            now = 100 + Double(second)
            c.tick()
            assert(led.value == (second % 4 < 2 ? 4 : 1))
            let count = led.writes.count
            c.command(2); c.command(2); c.tick()
            assert(led.writes.count == count) // repeated heartbeats cannot create extra edges
        }
        now += 0.9; c.command(2); c.tick(); assert(led.value == 1)
        now += 0.1; c.tick(); assert(led.value == 4)
        c.command(1); assert(led.value == 1) // completion during darkness turns off
        c.command(2); assert(led.value == 4) // next task resumes activity
        c.command(3); assert(led.value == 3)
        c.command(1); assert(led.value == 1)
        c.command(0); assert(led.value == 0); assert(!FileManager.default.fileExists(atPath:path))
        c.command(3); led.value = 4; c.tick(); assert(led.value == 3) // transient firmware reset
        c.tick() // successful stable read clears the mismatch count
        for _ in 0..<3 { led.value = 4; c.tick() }
        assert(led.value == 4) // persistent external writer: stop fighting
        let count = led.writes.count
        c.command(3); c.tick(); assert(led.writes.count == count)
        let status = try JSONDecoder().decode(MagSafeStatus.self, from: Data(contentsOf: URL(fileURLWithPath:statusPath)))
        assert(status.message.contains("repeatedly"))
        c.command(0); led.value = 0; c.command(3)
        let restored = MagSafeController(led: led, journal:path, statusPath: statusPath, uptime: { now })
        assert(led.value == 0); assert(restored.restore())
        restored.command(3); assert(led.value == 3)
        now += 15.1
        restored.tick(); assert(led.value == 0) // lost app heartbeat expires
        assert(!FileManager.default.fileExists(atPath: path))
        print("MagSafe: regular cadence, duplicate heartbeats, transient reset, persistent conflict, lease and recovery passed")
    }
}
