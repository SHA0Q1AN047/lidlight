import Foundation

@main struct Tests {
    static func expect(_ condition: Bool, _ message: String) { precondition(condition,message) }
    static func main() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var supply = SupplyAssessment()
        for second in stride(from: 0,through: 180,by: 5) {
            supply.update(ac: true,percent: second == 180 ? 78 : 80,now: now.addingTimeInterval(Double(second)))
        }
        expect(supply.falling,"Sustained AC loss warns")
        supply.update(ac: true,percent: 79,now: now.addingTimeInterval(185))
        expect(!supply.falling,"Charging recovery clears warning")
        supply.update(ac: false,percent: 78,now: now.addingTimeInterval(190))
        expect(!supply.falling,"Unplug clears warning")
        for second in stride(from: 0,through: 300,by: 5) { supply.update(ac: true,percent: 80,now: now.addingTimeInterval(Double(second))) }
        expect(!supply.falling,"Stable charging limit never warns")
        supply.update(ac: true,percent: 70,now: now.addingTimeInterval(900))
        expect(!supply.falling,"Sleep gap re-primes, never claims AC loss while asleep")
        supply.update(ac: true,percent: nil,now: now.addingTimeInterval(905))
        expect(!supply.falling,"Missing battery is not a supply failure")
        let previous = [Int32(1): ProcessCPUTick(pid: 1,started: 10,nanoseconds: 1_000_000_000,name: "A")]
        let current = [ProcessCPUTick(pid: 1,started: 10,nanoseconds: 5_000_000_000,name: "A"),ProcessCPUTick(pid: 2,started: 20,nanoseconds: 9_000_000_000,name: "New")]
        expect(ProcessCPUReader.ranked(previous: previous,current: current,elapsed: 2).first?.percent == 200,"Multicore CPU follows Activity Monitor convention")
        expect(ProcessCPUReader.ranked(previous: previous,current: [ProcessCPUTick(pid: 1,started: 11,nanoseconds: 8_000_000_000,name: "Reused")],elapsed: 2).isEmpty,"Reused PID never gets old CPU history")
        expect(ProcessCPUReader.ranked(previous: previous,current: current,elapsed: 20).isEmpty,"Panel reopen cannot average hidden interval")
        func window(_ used: Double, _ id: String = "primary", reset: Double = 3600, minutes: Int = 300) -> QuotaWindow {
            QuotaWindow(id: id,used: used,minutes: minutes,resetsAt: now.addingTimeInterval(reset))
        }
        var tracker = QuotaRecoveryTracker()
        expect(!tracker.observe([window(20)],now: now),"First available reading is not a recovery")
        expect(!tracker.observe([window(100),window(100,"secondary")],now: now),"Exhaustion arms without notification")
        expect(!tracker.observe([window(0)],now: now),"Missing weekly window cannot claim recovery")
        expect(!tracker.observe([window(0),window(100,"secondary")],now: now),"A second exhausted window still blocks use")
        expect(!tracker.observe([window(0),window(0,"secondary",reset: -1)],now: now),"Clock expiry is not confirmed recovery")
        let persisted = try! JSONEncoder().encode(tracker)
        tracker = try! JSONDecoder().decode(QuotaRecoveryTracker.self,from: persisted)
        expect(tracker.observe([window(0,reset: 7200),window(0,"secondary",reset: 7200)],now: now),"Fresh usable windows confirm recovery across restart")
        expect(!tracker.observe([window(0,reset: 7200),window(0,"secondary",reset: 7200)],now: now),"Recovery notification deduplicates")
        var partial = QuotaRecoveryTracker()
        expect(!partial.observe([window(100),window(50,"secondary")],now: now),"Remember all known windows during exhaustion")
        expect(!partial.observe([window(0)],now: now),"Missing previously healthy window cannot claim recovery")
        expect(partial.observe([window(0),window(50,"secondary")],now: now),"Complete response confirms recovery")
        let reader = ProcessCPUReader()
        expect(reader.sample().isEmpty,"First process snapshot only primes")
        Thread.sleep(forTimeInterval: 1)
        let live = reader.sample()
        expect(!live.isEmpty && live.allSatisfy { $0.percent.isFinite && $0.percent > 0 },"Native process CPU deltas are readable without administrator access")
        reader.reset(); expect(reader.sample().isEmpty,"Process reader can pause cleanly")
        print("PASS: AC loss/recovery/gaps, multicore CPU/PID reuse/pause, quota recovery/reset/missing-window/persistence/dedup")
    }
}
