import Foundation

final class PerformanceMonitor: ObservableObject {
    @Published private(set) var sample: SensorSample?
    @Published private(set) var history: [SensorSample] = []
    @Published private(set) var hasFans: Bool? = HardwareSensors.isKnownFanless(model: HardwareSensors.modelIdentifier()) ? false : nil
    @Published private(set) var busy = false
    @Published private(set) var topProcesses: [ProcessCPUReading] = []
    @Published private(set) var processesUpdated: Date?
    private let processes = ProcessCPUReader()
    private var processesActive = false
    private var lastAttempt = Date.distantPast
    private let queue = DispatchQueue(label: "com.lidlight.sensors", qos: .utility)
    private var reader: HardwareSensors? // Accessed only on queue.
    private let readSample: (() -> SensorSample)?
    init(readSample: (() -> SensorSample)? = nil) { self.readSample = readSample }
    func refresh(visible: Bool, now: Date = Date(), includeProcesses: Bool = false) {
        if !visible || !includeProcesses {
            if processesActive {
                processesActive = false
                queue.async { [weak self] in self?.processes.reset() }
            }
            if !topProcesses.isEmpty { topProcesses = [] }
            if processesUpdated != nil { processesUpdated = nil }
        }
        guard visible, !busy, (now < lastAttempt || now.timeIntervalSince(lastAttempt) >= 2) else { return }
        lastAttempt = now; busy = true
        processesActive = includeProcesses
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
                self.topProcesses = self.processesActive && includeProcesses ? top : []
                self.processesUpdated = self.processesActive && includeProcesses ? result.date : nil
                if let count = result.fanCount, count > 0 { self.hasFans = true }
                else if result.fanCount == 0 && self.hasFans != true { self.hasFans = false }
                self.sample = result
                // Clock corrections must not retain future points or join unrelated traces.
                self.history = self.history.filter { $0.date <= result.date && result.date.timeIntervalSince($0.date) <= 120 }
                self.history.append(result)
                self.history = Array(self.history.suffix(60))
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
