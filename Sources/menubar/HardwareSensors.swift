import Foundation
import IOKit

/// Read-only AppleSMC client. Only read-value (5), enumerate-key (8) and key-info (9) commands are sent.
final class HardwareSensors {
    private var connection: io_connect_t = 0
    private var metadata: [String: (Int, String)] = [:]
    private var temperatureKeys: [String]?
    private var missingKeys: [String: Double] = [:]
    private var lastConnectionAttempt = -Double.infinity
    private var lastDiscovery = -Double.infinity
    private var emptySamples = 0
    private let brand = HardwareSensors.cpuBrand()
    private let fanless = HardwareSensors.isKnownFanless(model: HardwareSensors.modelIdentifier())
    private var hid: CPUThermalHID?
    private var lastHIDAttempt = -Double.infinity
    init() { open() }
    private func open() {
        lastConnectionAttempt = ProcessInfo.processInfo.systemUptime
        if connection != 0 { IOServiceClose(connection); connection = 0 }
        metadata.removeAll(); missingKeys.removeAll(); temperatureKeys = nil
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    var connected: Bool { connection != 0 }
    private func packet(key: String, command: UInt8, count: Int = 0, index: UInt32 = 0) -> [UInt8]? {
        guard connected, command == 5 || command == 8 || command == 9, key.utf8.count == 4, count >= 0, count <= 32 else { return nil }
        // AppleSMC's user-client ABI is an 80-byte record on both supported architectures.
        var request = [UInt8](repeating: 0, count: 80)
        var reply = request
        let code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        for i in 0..<4 { request[i] = UInt8(truncatingIfNeeded: code >> (8*i)) }
        request[28] = UInt8(count)
        request[42] = command
        for i in 0..<4 { request[44+i] = UInt8(truncatingIfNeeded: index >> (8*i)) }
        var length = 80
        let result = request.withUnsafeBytes { input in
            reply.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(connection, 2, input.baseAddress, 80, output.baseAddress, &length)
            }
        }
        guard result == KERN_SUCCESS, length == 80, reply[40] == 0 else { return nil }
        return reply
    }
    func read(_ key: String) -> Double? {
        let uptime = ProcessInfo.processInfo.systemUptime
        if let retry = missingKeys[key], uptime < retry { return nil }
        let info: (Int, String)
        if let cached = metadata[key] { info = cached }
        else {
            guard let bytes = packet(key: key, command: 9) else { missingKeys[key] = uptime + 60; return nil }
            let count = (0..<4).reduce(0) { $0 | (Int(bytes[28+$1]) << (8*$1)) }
            let type = String(bytes: bytes[32..<36].reversed(), encoding: .ascii) ?? ""
            guard (1...32).contains(count), type.count == 4 else { return nil }
            info = (count,type); metadata[key] = info; missingKeys.removeValue(forKey: key)
        }
        guard let response = packet(key: key, command: 5, count: info.0) else { metadata.removeValue(forKey: key); return nil }
        return Self.decode(type: info.1, bytes: Array(response[48..<(48+info.0)]))
    }
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        var value: Double?
        switch type {
        case "flt " where bytes.count == 4:
            let bits = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[$1]) << (8*$1)) }
            value = Double(Float(bitPattern: bits))
        case "ui8 " where bytes.count == 1: value = Double(bytes[0])
        case "ui16" where bytes.count == 2: value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4: value = Double(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        case "sp78" where bytes.count == 2:
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            let chars = Array(type)
            if chars.count == 4, (chars[0] == "f" || chars[0] == "s"), chars[1] == "p", let integer = chars[2].hexDigitValue, let fraction = chars[3].hexDigitValue, integer + fraction == (chars[0] == "s" ? 15 : 16), bytes.count == 2 {
                let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
                value = (chars[0] == "s" ? Double(Int16(bitPattern: raw)) : Double(raw)) / pow(2, Double(fraction))
            }
        }
        guard let value, value.isFinite else { return nil }
        return value
    }
    static func cpuKeys(brand: String) -> [String] {
        let family = brand.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        if brand.hasPrefix("Apple ") && family == "M1" { return ["Tp09","Tp0T","Tp01","Tp05","Tp0D","Tp0H","Tp0L","Tp0P","Tp0X","Tp0b"] }
        if brand.hasPrefix("Apple ") && family == "M2" { return ["Tp1h","Tp1t","Tp1p","Tp1l","Tp01","Tp05","Tp09","Tp0D","Tp0X","Tp0b","Tp0f","Tp0j"] }
        if brand.hasPrefix("Apple ") && family == "M3" { return ["Te05","Te0L","Te0P","Te0S","Tf04","Tf09","Tf0A","Tf0B","Tf0D","Tf0E","Tf44","Tf49","Tf4A","Tf4B","Tf4D","Tf4E"] }
        if brand.hasPrefix("Apple ") && family == "M4" { return ["Te05","Te0S","Te09","Te0H","Tp01","Tp05","Tp09","Tp0D","Tp0V","Tp0Y","Tp0b","Tp0e"] }
        if brand.hasPrefix("Apple ") && family == "M5" { return ["Tp00","Tp04","Tp08","Tp0C","Tp0G","Tp0K","Tp0O","Tp0R","Tp0U","Tp0X","Tp0a","Tp0d","Tp0g","Tp0j","Tp0m","Tp0p","Tp0u","Tp0y"] }
        if brand.contains("Intel") { return ["TCAD","TC0D","TC0E","TC0F","TC0P","TC0H"] }
        return [] // Unknown silicon: do not label arbitrary temperature sensors as CPU.
    }
    /// Enumerate once per connection/recovery, never on every two-second sample.
    private func availableKeys() -> [String] {
        Self.discoverKeys(count: read("#KEY")) { packet(key: "    ", command: 8, index: $0) }
    }
    static func discoverKeys(count: Double?, readIndex: (UInt32) -> [UInt8]?) -> [String] {
        guard let count, count.isFinite, count > 0,
              count <= 16_384, count.rounded() == count else { return [] }
        var keys = Set<String>()
        for index in 0..<Int(count) {
            guard let response = readIndex(UInt32(index)), response.count == 80,
                  let key = String(bytes: response[0..<4].reversed(), encoding: .ascii),
                  key.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 }) else { continue }
            keys.insert(key)
        }
        return keys.sorted()
    }
    static func selectedCPUKeys(brand: String, available: [String]) -> [String] {
        let known = cpuKeys(brand: brand)
        // Intel core channels have a numeric index. TCGC is integrated GPU, not CPU.
        let discovered = brand.contains("Intel") ? available.filter { key in
            let bytes = Array(key.utf8)
            return ["TCAC", "TCBC", "TCAH", "TCBH"].contains(key) ||
                (bytes.count == 4 && bytes[0] == 84 && bytes[1] == 67 &&
                 (48...57).contains(bytes[2]) && [67, 99, 68, 69, 70, 72, 80].contains(bytes[3]))
        } : []
        return Array(Set(known + discovered)).sorted()
    }
    static func usesHIDFallback(brand: String) -> Bool { brand.hasPrefix("Apple M") }
    static func validTemperature(_ value: Double) -> Bool { value.isFinite && value >= 10 && value < 130 }
    static func isKnownFanless(model: String) -> Bool {
        ["MacBook8,1", "MacBook9,1", "MacBook10,1", "MacBookAir10,1", "Mac14,2", "Mac14,15", "Mac15,12", "Mac15,13", "Mac16,12", "Mac16,13", "Mac17,3", "Mac17,4"].contains(model)
    }
    static func modelIdentifier() -> String {
        var count = 0
        guard sysctlbyname("hw.model",nil,&count,nil,0) == 0, count > 0, count < 1024 else { return "Unknown" }
        var bytes = [CChar](repeating: 0,count: count)
        guard sysctlbyname("hw.model",&bytes,&count,nil,0) == 0 else { return "Unknown" }
        return String(cString: bytes)
    }
    static func cpuBrand() -> String {
        var count = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &count, nil, 0) == 0, count > 0, count < 1024 else { return "Unknown" }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &count, nil, 0) == 0 else { return "Unknown" }
        return String(cString: bytes)
    }
    func sample() -> SensorSample {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        // Retry after controller failure, or after sleep leaves a stale connection.
        if (!connected || emptySamples >= 3) && uptime-lastConnectionAttempt >= 60 {
            open(); hid = nil; lastHIDAttempt = -.infinity; emptySamples = 0
        }
        if temperatureKeys == nil || (emptySamples >= 3 && uptime-lastDiscovery >= 60) {
            temperatureKeys = Self.selectedCPUKeys(brand: brand, available: brand.contains("Intel") ? availableKeys() : [])
            lastDiscovery = uptime
        }
        let primary = Self.collect(now: now, keys: temperatureKeys ?? [], read: read)
        if primary.watts == nil && primary.cpuCelsius == nil && primary.fanCount == nil { emptySamples += 1 }
        else { emptySamples = 0 }
        // CPU-named HID services are useful on any Apple Silicon generation.
        var fallback: (key: String, celsius: Double)?
        if primary.cpuCelsius == nil && Self.usesHIDFallback(brand: brand) {
            if uptime-lastHIDAttempt >= 60 {
                lastHIDAttempt = uptime; hid = CPUThermalHID()
            }
            fallback = hid?.read()
        }
        return Self.resolved(primary, fallback: fallback, fanless: fanless)
    }
    static func resolved(_ primary: SensorSample, fallback: (key: String, celsius: Double)?, fanless: Bool) -> SensorSample {
        let alternate = fallback.flatMap { validTemperature($0.celsius) ? $0 : nil }
        return SensorSample(date: primary.date,watts: primary.watts,cpuCelsius: primary.cpuCelsius ?? alternate?.celsius,cpuKey: primary.cpuKey ?? alternate?.key,
            fans: fanless ? [] : primary.fans,fanCount: fanless ? 0 : primary.fanCount)
    }
    static func collect(now: Date, keys: [String], read: (String) -> Double?) -> SensorSample {
        let temperatures = keys.compactMap { key -> (String,Double)? in
            guard let value = read(key), Self.validTemperature(value) else { return nil }; return (key,value)
        }
        let hottest = temperatures.max { $0.1 < $1.1 }
        let power = read("PSTR").flatMap { $0.isFinite && $0 > 0 && $0 < 2000 ? $0 : nil }
        let count = read("FNum").flatMap { $0.isFinite && $0 >= 0 && $0 <= 8 && $0.rounded() == $0 ? Int($0) : nil }
        let fans = (0..<(count ?? 0)).map { index in
            FanReading(index: index, rpm: read("F\(index)Ac").flatMap { $0.isFinite && $0 >= 0 && $0 < 30_000 ? $0 : nil })
        }
        return SensorSample(date: now, watts: power, cpuCelsius: hottest?.1, cpuKey: hottest?.0, fans: fans, fanCount: count)
    }
}

struct FanReading: Equatable, Identifiable {
    let index: Int
    let rpm: Double?
    var id: Int { index }
}
struct SensorSample: Equatable {
    let date: Date
    let watts: Double?
    let cpuCelsius: Double?
    let cpuKey: String?
    let fans: [FanReading]
    let fanCount: Int?
    var hasReadings: Bool { watts != nil || cpuCelsius != nil || fans.contains { $0.rpm != nil } || fanCount == 0 }
}

/// Optional, read-only CPU thermal service fallback. No input-event subscription or keyboard access.
final class CPUThermalHID {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias Match = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias Services = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias Property = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias Event = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias Value = @convention(c) (CFTypeRef, Int32) -> Double
    private let library: UnsafeMutableRawPointer
    private let client: CFTypeRef
    private let services: Services
    private let property: Property
    private let event: Event
    private let value: Value
    init?() {
        guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let create = dlsym(library,"IOHIDEventSystemClientCreate"),
              let matching = dlsym(library,"IOHIDEventSystemClientSetMatching"),
              let services = dlsym(library,"IOHIDEventSystemClientCopyServices"),
              let property = dlsym(library,"IOHIDServiceClientCopyProperty"),
              let event = dlsym(library,"IOHIDServiceClientCopyEvent"),
              let value = dlsym(library,"IOHIDEventGetFloatValue"),
              let client = unsafeBitCast(create,to: Create.self)(kCFAllocatorDefault)?.takeRetainedValue() else { dlclose(library); return nil }
        self.library = library; self.client = client
        self.services = unsafeBitCast(services,to: Services.self)
        self.property = unsafeBitCast(property,to: Property.self)
        self.event = unsafeBitCast(event,to: Event.self)
        self.value = unsafeBitCast(value,to: Value.self)
        unsafeBitCast(matching,to: Match.self)(client,["PrimaryUsagePage": 0xff00,"PrimaryUsage": 5] as CFDictionary)
    }
    deinit { dlclose(library) }
    static func isCPUSensor(_ name: String) -> Bool {
        name.hasPrefix("pACC MTR Temp Sensor") || name.hasPrefix("eACC MTR Temp Sensor")
    }
    func read() -> (key: String, celsius: Double)? {
        guard let list = services(client)?.takeRetainedValue() else { return nil }
        var hottest: (String,Double)?
        for service in list as [AnyObject] {
            guard let name = property(service,"Product" as CFString)?.takeRetainedValue() as? String,
                  Self.isCPUSensor(name), let sample = event(service,15,0,0)?.takeRetainedValue() else { continue }
            let temperature = value(sample,15 << 16)
            guard HardwareSensors.validTemperature(temperature) else { continue }
            if temperature > (hottest?.1 ?? -.infinity) { hottest = (name,temperature) }
        }
        return hottest.map { ("HID: " + $0.0,$0.1) }
    }
}
