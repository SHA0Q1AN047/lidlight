import Foundation

final class PerformanceMonitor: ObservableObject {
    @Published private(set) var sample: SensorSample?
    @Published private(set) var history: [SensorSample] = []
    @Published private(set) var busy = false
    @Published private(set) var topProcesses: [ProcessCPUReading] = []
    @Published private(set) var processesUpdated: Date?
    private let processes = ProcessCPUReader()
    private var lastAttempt = Date.distantPast
    private let queue = DispatchQueue(label: "com.lidlight.sensors", qos: .utility)
    private var reader: HardwareSensors? // Accessed only on queue.
    private let readSample: (() -> SensorSample)?
    init(readSample: (() -> SensorSample)? = nil) { self.readSample = readSample }
    func refresh(visible: Bool, now: Date = Date(), includeProcesses: Bool = false) {
        guard visible, !busy, now.timeIntervalSince(lastAttempt) >= 2 else { return }
        lastAttempt = now; busy = true
        queue.async { [weak self] in
            guard let self else { return }
            let result: SensorSample
            if let readSample = self.readSample { result = readSample() }
            else {
                if self.reader == nil { self.reader = HardwareSensors() }
                result = self.reader!.sample()
            }
            let top: [ProcessCPUReading]
            if includeProcesses { top = self.processes.sample() }
            else { self.processes.reset(); top = [] }
            DispatchQueue.main.async {
                self.topProcesses = top
                self.processesUpdated = includeProcesses ? result.date : nil
                self.sample = result
                self.history.append(result)
                self.history = Array(self.history.filter { result.date.timeIntervalSince($0.date) <= 120 }.suffix(60))
                self.busy = false
            }
        }
    }
    static func isFresh(_ sample: SensorSample?, now: Date) -> Bool {
        guard let sample else { return false }
        let age = now.timeIntervalSince(sample.date)
        return age >= -2 && age <= 6
    }
}
