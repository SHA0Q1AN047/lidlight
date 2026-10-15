import Foundation
import Darwin

struct ProcessCPUReading: Identifiable {
    let id: Int32
    let name: String
    let percent: Double
}
struct ProcessCPUTick {
    let pid: Int32
    let started: UInt64
    let nanoseconds: UInt64
    let name: String
}
final class ProcessCPUReader {
    private var previous: [Int32: ProcessCPUTick] = [:]
    private var timestamp: TimeInterval?
    func reset() { previous.removeAll(); timestamp = nil }
    static func ranked(previous: [Int32: ProcessCPUTick], current: [ProcessCPUTick], elapsed: Double) -> [ProcessCPUReading] {
        guard elapsed > 0, elapsed <= 6 else { return [] }
        return current.compactMap { tick -> ProcessCPUReading? in
            guard let old = previous[tick.pid], old.started == tick.started, tick.nanoseconds >= old.nanoseconds else { return nil }
            let percent = Double(tick.nanoseconds - old.nanoseconds) / 1_000_000_000 / elapsed * 100
            guard percent.isFinite, percent > 0 else { return nil }
            return ProcessCPUReading(id: tick.pid,name: tick.name,percent: percent)
        }.sorted { $0.percent == $1.percent ? $0.id < $1.id : $0.percent > $1.percent }.prefix(3).map { $0 }
    }
    func sample() -> [ProcessCPUReading] {
        let now = ProcessInfo.processInfo.systemUptime
        let count = max(32, Int(proc_listallpids(nil,0)) * 2 + 32)
        var pids = [Int32](repeating: 0,count: count)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress,Int32($0.count)) }
        var current: [ProcessCPUTick] = []
        for pid in pids.prefix(max(0,min(Int(found),count))) where pid > 0 {
            var identity = proc_bsdinfo(); var task = proc_taskinfo()
            guard proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&identity,Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                  proc_pidinfo(pid,PROC_PIDTASKINFO,0,&task,Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size else { continue }
            var name = [CChar](repeating: 0,count: 256)
            guard proc_name(pid,&name,UInt32(name.count)) > 0 else { continue }
            let total = task.pti_total_user.addingReportingOverflow(task.pti_total_system)
            guard !total.overflow else { continue }
            current.append(ProcessCPUTick(pid: pid,started: identity.pbi_start_tvsec &* 1_000_000 &+ identity.pbi_start_tvusec,nanoseconds: total.partialValue,name: String(cString: name)))
        }
        let ranked = timestamp.map { Self.ranked(previous: previous,current: current,elapsed: now - $0) } ?? []
        previous = Dictionary(current.map { ($0.pid,$0) },uniquingKeysWith: { _, new in new }); timestamp = now
        return ranked
    }
}
