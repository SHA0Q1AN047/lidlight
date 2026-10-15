import Foundation

@main struct Tests {
    static func expect(_ condition: Bool, _ label: String) { precondition(condition,label) }
    static func main() {
        let zero = CPUTicks(user: 0,system: 0,idle: 0,nice: 0)
        let reading = CPUTicks(user: 10,system: 15,idle: 70,nice: 5)
        expect(CPUTicks.usage(previous: zero,current: reading) == 0.3,"User + system + nice divided by all ticks")
        expect(CPUTicks.usage(previous: zero,current: CPUTicks(user: 0,system: 0,idle: 100,nice: 0)) == 0,"Idle")
        expect(CPUTicks.usage(previous: zero,current: CPUTicks(user: 100,system: 0,idle: 0,nice: 0)) == 1,"All busy")
        expect(CPUTicks.usage(previous: reading,current: reading) == nil,"No elapsed ticks is unknown")
        let old = CPUTicks(user: UInt32.max-9,system: 0,idle: 50,nice: 0)
        let new = CPUTicks(user: 5,system: 0,idle: 65,nice: 0)
        expect(CPUTicks.usage(previous: old,current: new) == 0.5,"Counter wrap")
        expect(CatPace.framesPerSecond(usage: 0) == 2,"Idle walks")
        expect(CatPace.framesPerSecond(usage: 0.1) == 2,"Very low load walks")
        expect(CatPace.framesPerSecond(usage: 1) == 12,"High load capped at 12 FPS")
        expect(CatPace.framesPerSecond(usage: .nan) == 0,"Invalid reading stops animation")
        var previous = 0.0
        for percent in 0...100 {
            let fps = CatPace.framesPerSecond(usage: Double(percent)/100)
            expect(fps >= previous && fps >= 2 && fps <= 12,"Monotonic bounded speed")
            previous = fps
        }
        expect(MenuBarIcon.cat(frame: 0).tiffRepresentation != MenuBarIcon.cat(frame: 0,sweating: true).tiffRepresentation,"Sweating cat is visually distinct")
        expect(MenuBarIcon.cat(frame: 0,sweating: true).tiffRepresentation != MenuBarIcon.cat(frame: 0,lowBattery: true,sweating: true).tiffRepresentation,"Low battery remains visible with thermal warning")
        let animator = MenuCatAnimator()
        animator.update(usage: 0,enabled: true,reduceMotion: false)
        expect(animator.isAnimating,"Walking timer starts")
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        expect(animator.frame != 0,"Timer advances gait")
        animator.update(usage: 1,enabled: true,reduceMotion: false)
        expect(abs(animator.usage! - 0.55) < 0.001,"CPU spikes are smoothed")
        animator.update(usage: 1,enabled: true,reduceMotion: true)
        expect(!animator.isAnimating && animator.frame == 0,"Reduce Motion keeps cat still")
        animator.update(usage: 1,enabled: false,reduceMotion: false)
        expect(!animator.isAnimating,"User can disable animation")
        animator.update(usage: nil,enabled: true,reduceMotion: false)
        expect(!animator.isAnimating && animator.usage == nil,"Missing CPU is never treated as idle")
        animator.update(usage: 0.5,enabled: true,reduceMotion: false)
        animator.pause()
        expect(!animator.isAnimating,"Display sleep stops timer")
        let reader = CPUUsageReader()
        expect(reader.sample() == nil,"First sample primes counters")
        Thread.sleep(forTimeInterval: 1.1)
        let live = reader.sample()
        expect(live != nil && (0...1).contains(live!),"Live system CPU read")
        reader.reset()
        expect(reader.sample() == nil,"Wake reset never averages sleep into a fresh reading")
        print("PASS: CPU deltas and wrap, native live sampling, monotonic pace, smoothing, animation advance, opt-out, Reduce Motion and pause")
    }
}
