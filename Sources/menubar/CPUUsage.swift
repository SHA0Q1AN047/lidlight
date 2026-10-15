import Foundation
import Darwin

struct CPUTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
    static func usage(previous: Self, current: Self) -> Double? {
        // Kernel counters are 32-bit; wrapping subtraction preserves valid deltas.
        let busy = UInt64(current.user &- previous.user) + UInt64(current.system &- previous.system) + UInt64(current.nice &- previous.nice)
        let idle = UInt64(current.idle &- previous.idle)
        let total = busy + idle
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }
}

final class CPUUsageReader {
    private let host = mach_host_self()
    private var previous: CPUTicks?
    deinit { mach_port_deallocate(mach_task_self_, host) }
    func reset() { previous = nil }
    func sample() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { previous = nil; return nil }
        let ticks = CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { previous = ticks }
        guard let previous else { return nil }
        return CPUTicks.usage(previous: previous, current: ticks)
    }
}

enum CatPace {
    /// Six frames per cycle: slow walking at idle, up to two strides per second.
    static func framesPerSecond(usage: Double) -> Double {
        guard usage.isFinite else { return 0 }
        let percent = max(0, min(1, usage)) * 100
        let speed: Double
        if percent <= 10 { speed = 2 }
        else if percent <= 40 { speed = 2 + (percent - 10) / 10 }
        else if percent <= 80 { speed = 5 + (percent - 40) / 8 }
        else { speed = 10 + (percent - 80) / 10 }
        return (speed * 2).rounded() / 2
    }
}
