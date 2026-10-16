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
        expect(HardwareSensors.decode(type: "sp4b",bytes: [0x19,0]) == 3.125,"Older signed SMC formats decode correctly")
        expect(HardwareSensors.decode(type: "sp4b",bytes: [0xf8,0]) == -1,"Older signed SMC values retain sign")
        expect(HardwareSensors.decode(type: "spff",bytes: [0,0]) == nil,"Malformed fixed point layout is rejected")
        var inventoryCalls = 0
        for invalidCount: Double? in [nil,-1,0,1.5,.nan,.infinity,16_385] {
            expect(HardwareSensors.discoverKeys(count: invalidCount,readIndex: { _ in inventoryCalls += 1; return nil }).isEmpty,"Invalid SMC inventory count is rejected")
        }
        expect(inventoryCalls == 0,"Malformed count never invokes the controller")
        let discoveredKeys = HardwareSensors.discoverKeys(count: 4) { index in
            if index == 1 { return nil }
            if index == 2 { return [0] }
            var response = [UInt8](repeating: 0,count: 80)
            response.replaceSubrange(0..<4,with: Array("TC1C".utf8).reversed())
            return response
        }
        expect(discoveredKeys == ["TC1C"],"Inventory tolerates failed/truncated responses and deduplicates the decoded ABI key")
        let inventory = ["TC0c","TC1C","TC9D","TCAC","TCBC","TCGC","TG0D","TB1T","Tp0P","TC1x","TC1C","TC12C"]
        let intel = HardwareSensors.selectedCPUKeys(brand: "Intel(R) Xeon(R)",available: inventory)
        expect(["TC0c","TC1C","TC9D","TCAC","TCBC"].allSatisfy { intel.contains($0) },"Intel core and dual-package channels are discovered")
        expect(["TCGC","TG0D","TB1T","Tp0P","TC1x","TC12C"].allSatisfy { !intel.contains($0) },"GPU, battery, board and unclassified channels are excluded")
        expect(intel.count == Set(intel).count,"Discovery removes duplicate keys")
        for chip in ["Apple M1","Apple M1 Pro","Apple M2 Max","Apple M3 Ultra","Apple M4","Apple M5","Apple M99"] {
            expect(HardwareSensors.usesHIDFallback(brand: chip),"Every Apple Silicon family can try named CPU services")
        }
        expect(!HardwareSensors.usesHIDFallback(brand: "Intel Core i7"),"Intel does not attempt Apple Silicon services")
        expect(HardwareSensors.cpuKeys(brand: "Apple M10").isEmpty,"M10 never inherits M1 keys by substring")
        expect(HardwareSensors.selectedCPUKeys(brand: "Apple M99",available: inventory).isEmpty,"Unknown silicon never borrows Intel or unrelated sensors")
        for model in ["MacBook8,1","MacBook9,1","MacBook10,1"] {
            expect(HardwareSensors.isKnownFanless(model: model),"12-inch Intel MacBooks have no fans")
        }
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
        expect(HardwareSensors.isKnownFanless(model: "MacBookAir10,1"), "M1 Air hides fans even if SMC is unavailable")
        expect(!HardwareSensors.isKnownFanless(model: "MacBookPro17,1"), "M1 Pro laptop is not mistaken for a fanless Air")
        expect(!HardwareSensors.isKnownFanless(model: "Unknown"), "Unknown model never implies no fan")
        expect(CPUThermalHID.isCPUSensor("pACC MTR Temp Sensor0") && CPUThermalHID.isCPUSensor("eACC MTR Temp Sensor1"), "Accept CPU thermal channels")
        expect(!CPUThermalHID.isCPUSensor("GPU MTR Temp Sensor") && !CPUThermalHID.isCPUSensor("Battery") && !CPUThermalHID.isCPUSensor("PMU tdie"), "Do not mislabel GPU, battery or ambiguous die temperatures as CPU")
        let missing = SensorSample(date: now,watts: nil,cpuCelsius: nil,cpuKey: nil,fans: [],fanCount: nil)
        let recovered = HardwareSensors.resolved(missing,fallback: ("HID: pACC MTR Temp Sensor0",52.5),fanless: true)
        expect(recovered.cpuCelsius == 52.5 && recovered.fanCount == 0 && recovered.fans.isEmpty, "M1 HID fallback works independently of SMC and fan count")
        expect(HardwareSensors.resolved(recovered,fallback: ("HID: other",60),fanless: false).cpuCelsius == 52.5, "Primary temperature wins over fallback")
        expect(HardwareSensors.resolved(missing,fallback: ("HID: cpu",6.7),fanless: false).cpuCelsius == nil, "Invalid fallback remains unavailable")
        expect(HardwareSensors.resolved(missing,fallback: nil,fanless: false).fanCount == nil, "Failed fan read never becomes fanless")
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
        expect(monitor.hasFans == false,"A confirmed fanless device hides fan UI")
        var topologySample = SensorSample(date: now,watts: 10,cpuCelsius: 45,cpuKey: "test",fans: [FanReading(index: 0,rpm: 0)],fanCount: 1)
        let topology = PerformanceMonitor(readSample: { topologySample })
        topology.refresh(visible: true,now: now)
        for _ in 0..<200 { if !topology.busy { break }; try? await Task.sleep(nanoseconds: 1_000_000) }
        expect(topology.hasFans == true,"Stopped physical fan remains visible")
        topologySample = missing
        topology.refresh(visible: true,now: now.addingTimeInterval(3))
        for _ in 0..<200 { if !topology.busy { break }; try? await Task.sleep(nanoseconds: 1_000_000) }
        expect(topology.hasFans == true,"A failed subsequent read does not hide installed fans")
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
