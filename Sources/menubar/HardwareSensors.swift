import Foundation
import IOKit

/// Read-only AppleSMC client. Only key-info (9) and read-value (5) commands are sent.
final class HardwareSensors {
    private var connection: io_connect_t = 0
    private var metadata: [String: (Int, String)] = [:]
    private var temperatureKeys: [String]?
    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    var connected: Bool { connection != 0 }
    private func packet(key: String, command: UInt8, count: Int = 0) -> [UInt8]? {
        guard connected, command == 5 || command == 9, key.utf8.count == 4, count >= 0, count <= 32 else { return nil }
        // AppleSMC's user-client ABI is an 80-byte record on both supported architectures.
        var request = [UInt8](repeating: 0, count: 80)
        var reply = request
        let code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        for i in 0..<4 { request[i] = UInt8(truncatingIfNeeded: code >> (8*i)) }
        request[28] = UInt8(count)
        request[42] = command
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
        let info: (Int, String)
        if let cached = metadata[key] { info = cached }
        else {
            guard let bytes = packet(key: key, command: 9) else { return nil }
            let count = (0..<4).reduce(0) { $0 | (Int(bytes[28+$1]) << (8*$1)) }
            let type = String(bytes: bytes[32..<36].reversed(), encoding: .ascii) ?? ""
            guard (1...32).contains(count), type.count == 4 else { return nil }
            info = (count,type); metadata[key] = info
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
            if chars.count == 4, chars[0] == "f", chars[1] == "p", let integer = chars[2].hexDigitValue, let fraction = chars[3].hexDigitValue, integer + fraction == 16, bytes.count == 2 {
                value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / pow(2, Double(fraction))
            }
        }
        guard let value, value.isFinite else { return nil }
        return value
    }
    static func cpuKeys(brand: String) -> [String] {
        if brand.contains("Apple M1") { return ["Tp09","Tp0T","Tp01","Tp05","Tp0D","Tp0H","Tp0L","Tp0P","Tp0X","Tp0b"] }
        if brand.contains("Apple M2") { return ["Tp1h","Tp1t","Tp1p","Tp1l"] }
        if brand.contains("Apple M3") { return ["Te05","Te0L","Te0P","Te0S","Tf04","Tf09","Tf0A","Tf0B","Tf0D","Tf0E","Tf44","Tf49","Tf4A","Tf4B","Tf4D","Tf4E"] }
        if brand.contains("Apple M4") { return ["Te05","Te0S","Te09","Te0H","Tp01","Tp05","Tp09","Tp0D","Tp0V","Tp0Y","Tp0b","Tp0e"] }
        if brand.contains("Apple M5") { return ["Tp00","Tp04","Tp08","Tp0C","Tp0G","Tp0K","Tp01","Tp0R","Tp0U","Tp0X","Tp0a","Tp0d","Tp0g","Tp0j","Tp0m","Tp0p","Tp0u","Tp0y"] }
        if brand.contains("Intel") { return ["TCAD","TC0D","TC0E","TC0F"] }
        return [] // Unknown silicon: do not label arbitrary temperature sensors as CPU.
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
        guard connected else { return SensorSample(date: now, watts: nil, cpuCelsius: nil, cpuKey: nil, fans: [], fanCount: nil) }
        // Cache candidate names, never availability: sleeping channels must be retried next sample.
        if temperatureKeys == nil { temperatureKeys = Self.cpuKeys(brand: Self.cpuBrand()) }
        return Self.collect(now: now, keys: temperatureKeys ?? [], read: read)
    }
    static func collect(now: Date, keys: [String], read: (String) -> Double?) -> SensorSample {
        let temperatures = keys.compactMap { key -> (String,Double)? in
            guard let value = read(key), value.isFinite, value >= 10, value < 130 else { return nil }; return (key,value)
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
