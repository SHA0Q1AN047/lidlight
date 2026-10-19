import SwiftUI

struct PerformanceSummary: View {
    @ObservedObject var monitor: PerformanceMonitor
    let now: Date
    var body: some View {
        let sample = PerformanceMonitor.isFresh(monitor.sample, now: now) ? monitor.sample : nil
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LIVE SENSORS").tracking(1)
                Spacer()
                Image(systemName: "chevron.right")
            }.font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
            HStack(spacing: 8) {
                metric("System power", color: LidlightPalette.iris, path: { $0.watts }, value: sample?.watts.map { String(format: "%.1f W", $0) } ?? "—")
                metric("CPU temp", color: LidlightPalette.peach, path: { $0.cpuCelsius }, value: sample?.cpuCelsius.map { String(format: "%.1f°C", $0) } ?? "—", cpuSource: sample?.cpuKey)
                if monitor.hasFans != false {
                    metric("Fans · max RPM", color: LidlightPalette.mist, path: { $0.fans.compactMap(\.rpm).max() }, value: sample?.fans.compactMap(\.rpm).max().map { String(format: "%.0f", $0) } ?? "—")
                }
            }
        }.contentShape(Rectangle())
    }
    private func metric(_ title: String, color: Color, path: @escaping (SensorSample) -> Double?, value: String, cpuSource: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65).allowsTightening(true)
            SensorTrend(history: monitor.history, now: now, value: path, color: color, cpuSource: cpuSource).frame(height: 18)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PerformanceView: View {
    @ObservedObject var monitor: PerformanceMonitor
    let now: Date
    private var current: SensorSample? { PerformanceMonitor.isFresh(monitor.sample, now: now) ? monitor.sample : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance").font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Live sensors · Refreshes about every 2s").font(.system(size: 11)).foregroundColor(.secondary)
            if monitor.sample == nil {
                Text(monitor.busy ? "Reading sensors…" : "Waiting for the first reading…").font(.system(size: 12))
            } else if current == nil {
                Text("Readings are stale. Waiting for a fresh sample.").font(.system(size: 12)).foregroundColor(.orange)
            } else if current?.hasReadings == false {
                Text("Hardware readings are unavailable on this Mac. The system may restrict sensor access.").font(.system(size: 12)).foregroundColor(.orange)
            } else if current?.cpuCelsius == nil {
                Text("CPU temperature unavailable · Waiting for a supported reading (10–130°C).").font(.system(size: 11)).foregroundColor(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                card("System power", value: current?.watts, unit: "W", icon: "bolt.fill", color: LidlightPalette.iris, path: \.watts,
                     note: "System sensor reading")
                card("CPU temp", value: current?.cpuCelsius, unit: "°C", icon: "thermometer", color: LidlightPalette.peach, path: \.cpuCelsius,
                     note: current?.cpuKey.map { "Fixed sensor · " + $0 } ?? "Waiting for CPU sensor", cpuSource: current?.cpuKey)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Top CPU processes").font(.system(size: 13, weight: .semibold))
                if let updated = monitor.processesUpdated, now.timeIntervalSince(updated) <= 6, !monitor.topProcesses.isEmpty {
                    ForEach(monitor.topProcesses) { process in
                        HStack {
                            Text(process.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(String(format: "%.1f%%", process.percent)).monospacedDigit().fixedSize()
                        }.font(.system(size: 11))
                    }
                } else {
                    Text("Collecting CPU activity…").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Text("Readable processes only · 100% = one CPU core. Samples only while this page is open; process names stay on your Mac.").font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(16).lidlightCard()
            if monitor.hasFans != false {
            VStack(alignment: .leading, spacing: 12) {
                Label("Fans", systemImage: "fanblades").font(.system(size: 13, weight: .semibold))
                if let fans = current?.fans, !fans.isEmpty {
                    ForEach(fans) { fan in
                        HStack {
                            Text("Fan \(fan.index + 1)")
                            Spacer()
                            Text(fan.rpm.map { String(format: "%.0f RPM", $0) } ?? "Unavailable").monospacedDigit().fontWeight(.medium)
                        }.font(.system(size: 12))
                    }
                    SensorTrend(history: monitor.history, now: now, value: { $0.fans.compactMap(\.rpm).max() }, color: LidlightPalette.mist).frame(height: 38)
                    Text("Chart shows the fastest fan. 0 RPM means a stopped fan.").font(.system(size: 10)).foregroundColor(.secondary)
                } else { Text("Fan readings unavailable").font(.system(size: 12)).foregroundColor(.secondary) }
                Text("Monitoring only. macOS continues to control fan speeds.").font(.system(size: 10)).foregroundColor(.secondary)
            }.padding(16).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).lidlightCard()
            }
            Text("System watts are device-reported, not a wall-outlet measurement. Charts keep up to two minutes while this panel is open. Closing the panel pauses sampling. Sensor support varies by Mac; unavailable readings are never shown as zero.")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let date = current?.date {
                Text("Updated \(date.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(Locale(identifier: "en_US"))))")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func card(_ title: String, value: Double?, unit: String, icon: String, color: Color, path: KeyPath<SensorSample, Double?>, note: String, cpuSource: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { String(format: "%.1f", $0) } ?? "Unavailable")
                    .font(.system(size: value == nil ? 15 : 23, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).allowsTightening(true)
                    .layoutPriority(1)
                if value != nil {
                    Text(unit).font(.system(size: 14, weight: .medium)).fixedSize()
                }
            }.foregroundColor(color).frame(maxWidth: .infinity, alignment: .leading)
            SensorTrend(history: monitor.history, now: now, value: { $0[keyPath: path] }, color: color, cpuSource: cpuSource).frame(height: 30)
            Text(note).font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).lidlightCard()
    }
}

private struct SensorTrend: View {
    let history: [SensorSample]
    let now: Date
    let value: (SensorSample) -> Double?
    let color: Color
    var cpuSource: String? = nil
    var body: some View {
        let samples = history.filter { now.timeIntervalSince($0.date) >= 0 && now.timeIntervalSince($0.date) <= 120 }
        let maximum = max(samples.filter { cpuSource == nil || $0.cpuKey == cpuSource }.compactMap(value).max() ?? 1, 1) * 1.15
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                if samples.compactMap(value).count < 2 {
                    Text("Collecting trend…").font(.system(size: 9)).foregroundColor(.secondary).frame(maxHeight: .infinity)
                }

                Path { path in
                    var previous: Date?
                    for sample in samples {
                        guard cpuSource == nil || sample.cpuKey == cpuSource, let reading = value(sample) else { previous = nil; continue }
                        let point = CGPoint(x: geometry.size.width * (1 - now.timeIntervalSince(sample.date) / 120), y: geometry.size.height * (1 - reading / maximum))
                        if let previous, sample.date.timeIntervalSince(previous) <= 6 { path.addLine(to: point) }
                        else { path.move(to: point) }
                        previous = sample.date
                    }
                }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
}
