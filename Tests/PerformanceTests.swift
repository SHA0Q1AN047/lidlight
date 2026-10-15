import Foundation

@main struct Tests {
    static func expect(_ condition: Bool, _ message: String) { precondition(condition, message) }
    @MainActor static func main() async {
        expect(HardwareSensors.decode(type: "flt ", bytes: [0,0,72,66]) == 50, "Float is little endian")
        expect(HardwareSensors.decode(type: "sp78", bytes: [0x32,0x80]) == 50.5, "Signed fixed point temperature")
        expect(HardwareSensors.decode(type: "sp78", bytes: [0xff,0x00]) == -1, "Signed decoding")
        expect(HardwareSensors.decode(type: "fpe2", bytes: [0x1f,0x40]) == 2000, "Fixed point RPM")
        expect(HardwareSensors.decode(type: "ui16", bytes: [1,0]) == 256, "Integer endian")
        expect(HardwareSensors.decode(type: "flt ", bytes: [0,0,0xc0,0x7f]) == nil, "Reject NaN")
        expect(HardwareSensors.decode(type: "flt ", bytes: [0]) == nil, "Reject truncated data")
        expect(HardwareSensors.decode(type: "xxxx", bytes: [0,0]) == nil, "Unknown format")
        let now = Date()
        var values: [String: Double] = ["PSTR": 18.25,"T001": 45,"T002": 51,"FNum": 2,"F0Ac": 0,"F1Ac": 2300]
        func collect() -> SensorSample { HardwareSensors.collect(now: now, keys: ["T001","T002"], read: { values[$0] }) }
        var sample = collect()
        expect(sample.watts == 18.25 && sample.cpuCelsius == 51 && sample.cpuKey == "T002", "System power and hottest CPU sensor")
        expect(sample.fans.count == 2 && sample.fans[0].rpm == 0, "Zero RPM is a stopped fan, not missing data")
        values.removeValue(forKey: "F0Ac"); sample = collect()
        expect(sample.fans[0].rpm == nil && sample.fans[1].rpm == 2300, "Partial fan failure remains visible")
        values = ["FNum": 0]; sample = collect()
        expect(sample.fanCount == 0 && sample.fans.isEmpty && sample.hasReadings, "Explicit fanless hardware")
        values = [:]; sample = collect()
        expect(sample.fanCount == nil && !sample.hasReadings, "Missing count does not imply fanless")
        values = ["PSTR": -1,"T001": 999,"T002": .nan,"FNum": .infinity]
        sample = collect()
        expect(sample.watts == nil && sample.cpuCelsius == nil && sample.fanCount == nil, "Reject invalid sensor readings")
        values = ["PSTR": 12,"T001": 6.7,"T002": 4.63,"FNum": 0]
        sample = collect()
        expect(sample.cpuCelsius == nil && sample.watts == 12,"Low SMC artifacts never become a CPU temperature or chart point")
        values["T001"] = 45
        expect(collect().cpuCelsius == 45,"A valid temperature immediately recovers")
        expect(HardwareSensors.cpuKeys(brand: "Apple M2 Pro").contains("Tp1h"), "M2 CPU thermal zone")
        expect(HardwareSensors.cpuKeys(brand: "Apple M99").isEmpty, "Unknown silicon does not guess CPU temperature")
        expect(PerformanceMonitor.isFresh(sample, now: now), "Fresh sample")
        expect(!PerformanceMonitor.isFresh(sample, now: now.addingTimeInterval(7)), "Stale sample hidden")
        let monitor = PerformanceMonitor(readSample: { sample })
        monitor.refresh(visible: false)
        expect(!monitor.busy && monitor.sample == nil, "Hidden panel never samples")
        monitor.refresh(visible: true, now: now)
        for _ in 0..<200 {
            if !monitor.busy { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        expect(monitor.sample != nil && monitor.history.count == 1, "Background sample delivered to UI")
        monitor.refresh(visible: true, now: now.addingTimeInterval(1))
        expect(!monitor.busy && monitor.history.count == 1, "Sampling interval enforced")
        var sequence = 0
        let bounded = PerformanceMonitor(readSample: {
            sequence += 1
            return SensorSample(date: now.addingTimeInterval(Double(sequence) * 2), watts: 10, cpuCelsius: 45, cpuKey: "test", fans: [], fanCount: 0)
        })
        for index in 0..<65 {
            bounded.refresh(visible: true, now: now.addingTimeInterval(Double(index) * 3))
            for _ in 0..<200 { if !bounded.busy { break }; try? await Task.sleep(nanoseconds: 1_000_000) }
        }
        expect(bounded.history.count == 60, "History stays bounded")
        let before = bounded.history.count
        bounded.refresh(visible: false, now: now.addingTimeInterval(1000))
        expect(!bounded.busy && bounded.history.count == before, "Closing pauses all further sampling")
        print("PASS: SMC decoding, power/CPU/fan validation, stopped versus absent fan, unknown hardware, freshness, background delivery and idle throttling")
        if CommandLine.arguments.contains("--live") {
            let reader = HardwareSensors()
            let live = reader.sample()
            expect(reader.connected && live.watts != nil && live.cpuCelsius != nil && live.fans.count == 2, "This M2 Pro exposes all three requested metrics")
            print("LIVE: \(String(format: "%.1f",live.watts!)) W, \(String(format: "%.1f",live.cpuCelsius!)) °C, fans \(live.fans.map { $0.rpm.map { String(format: "%.0f RPM",$0) } ?? "Unavailable" }.joined(separator: ", "))")
        }
    }
}
