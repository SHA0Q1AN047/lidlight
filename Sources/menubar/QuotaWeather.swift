import SwiftUI

enum QuotaResetCountdown {
    static func label(reset: Date, now: Date) -> String {
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset pending" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "Resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "Resets in \(hours)h \(minutes % 60)m" }
        return "Resets in \(hours / 24)d \(hours % 24)h"
    }
}

enum QuotaSky: CaseIterable {
    case sunny, cloudy, sunset, sleeping, resetting, checking, unavailable, off
    var title: String {
        switch self {
        case .sunny: return "Sunny · Plenty left"
        case .cloudy: return "Cloudy · Pace yourself"
        case .sunset: return "Sunset · Running low"
        case .sleeping: return "Resting · Limit reached"
        case .resetting: return "Reset pending · Checking the sky"
        case .checking: return "Checking the sky…"
        case .unavailable: return "Sky unknown · Open for details"
        case .off: return "Weather off · Open to enable"
        }
    }
    static func window(_ window: QuotaWindow, now: Date) -> Self {
        if window.resetsAt <= now { return .resetting }
        if window.used >= 100 { return .sleeping }
        // Match the displayed rounded percentage; only a truly exhausted window sleeps.
        let left = window.remaining
        return left >= 50 ? .sunny : left >= 20 ? .cloudy : .sunset
    }
    static func overview(windows: [QuotaWindow], enabled: Bool, busy: Bool, failed: Bool, updated: Date?, now: Date) -> Self {
        guard enabled else { return .off }
        guard !windows.isEmpty else { return busy ? .checking : .unavailable }
        guard !failed, let updated, now.timeIntervalSince(updated) <= 15 * 60 else { return .unavailable }
        let skies = windows.map { window($0, now: now) }
        if skies.contains(.resetting) { return .resetting }
        if skies.contains(.sleeping) { return .sleeping }
        if skies.contains(.sunset) { return .sunset }
        if skies.contains(.cloudy) { return .cloudy }
        return .sunny
    }
}

/// A tiny hand-drawn sprite grid. No animation, network assets or extra timers.
struct QuotaWeatherSprite {
    static let size = 16
    // Palette: clear, gold, amber, cloud, shadow, ink, lavender, blue.
    static func pixels(_ sky: QuotaSky) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: size), count: size)
        func dot(_ x: Int, _ y: Int, _ color: Int) {
            if (0..<size).contains(x) && (0..<size).contains(y) { grid[y][x] = color }
        }
        func line(_ x: Int, _ y: Int, _ width: Int, _ color: Int) {
            for offset in 0..<width { dot(x + offset, y, color) }
        }
        func disk(_ cx: Int, _ cy: Int, _ radius: Int, _ color: Int) {
            for y in 0..<size { for x in 0..<size where (x-cx)*(x-cx)+(y-cy)*(y-cy) <= radius*radius { dot(x, y, color) } }
        }
        func sun() {
            disk(7, 7, 4, 2); disk(7, 7, 3, 1)
            for (x, y) in [(7,0),(7,1),(7,13),(7,14),(0,7),(1,7),(13,7),(14,7),(2,2),(3,3),(11,3),(12,2),(2,12),(3,11),(11,11),(12,12)] { dot(x,y,1) }
            dot(6,6,5); dot(9,6,5); line(7,9,2,5)
        }
        func cloud() {
            disk(5,8,3,4); disk(9,7,4,4); disk(12,9,2,4)
            disk(5,7,3,3); disk(9,6,3,3); disk(12,8,2,3)
            line(3,9,11,3); line(4,10,9,4)
        }
        switch sky {
        case .sunny: sun()
        case .cloudy:
            disk(4,4,3,2); disk(4,4,2,1); dot(4,0,1); dot(0,4,1); dot(1,1,1); cloud()
        case .sunset:
            disk(7,10,5,2); disk(7,10,4,1)
            for y in 11..<size { for x in 0..<size { dot(x,y,0) } }
            line(1,11,14,2); line(3,13,4,2); line(10,13,3,2)
            dot(5,8,5); dot(9,8,5); line(6,10,3,5); dot(7,2,2); dot(1,5,2); dot(13,5,2)
        case .sleeping:
            disk(7,7,5,6)
            for y in 0..<size { for x in 0..<size where (x-10)*(x-10)+(y-4)*(y-4) <= 25 { dot(x,y,0) } }
            line(4,8,2,5); dot(12,10,1); line(11,11,3,1); dot(12,12,1)
            line(11,1,3,6); dot(12,2,6); line(11,3,3,6)
        case .resetting:
            cloud(); line(6,12,6,7); dot(5,13,7); line(4,14,3,7); dot(5,15,7); dot(12,13,7); line(11,14,3,7)
        case .checking:
            cloud(); dot(4,13,7); dot(8,13,7); dot(12,13,7)
        case .unavailable:
            cloud(); line(6,2,4,7); dot(10,3,7); dot(9,4,7); dot(8,5,7); dot(8,7,7)
        case .off:
            cloud(); line(5,6,6,5)
        }
        return grid
    }
}

struct PixelQuotaWeather: View {
    let sky: QuotaSky
    private let palette: [Color] = [.clear, Color(red: 1, green: 0.82, blue: 0.3), Color(red: 0.94, green: 0.46, blue: 0.16), Color(red: 0.87, green: 0.94, blue: 0.98), Color(red: 0.4, green: 0.54, blue: 0.65), Color(red: 0.16, green: 0.2, blue: 0.29), Color(red: 0.72, green: 0.65, blue: 1), Color(red: 0.15, green: 0.55, blue: 0.9)]
    var body: some View {
        let pixels = QuotaWeatherSprite.pixels(sky)
        GeometryReader { geometry in
            let unit = floor(min(geometry.size.width, geometry.size.height) / 16)
            let dx = floor((geometry.size.width - unit * 16) / 2)
            let dy = floor((geometry.size.height - unit * 16) / 2)
            ZStack {
                ForEach(1..<palette.count, id: \.self) { color in
                    Path { path in
                        for y in 0..<16 { for x in 0..<16 where pixels[y][x] == color {
                            path.addRect(CGRect(x: dx + CGFloat(x) * unit, y: dy + CGFloat(y) * unit, width: unit, height: unit))
                        } }
                    }.fill(palette[color], style: FillStyle(antialiased: false))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct CodexWeatherHeader: View {
    @ObservedObject var quota: CodexQuota
    let now: Date
    var body: some View {
        let sky = QuotaSky.overview(windows: quota.windows, enabled: quota.enabled, busy: quota.busy, failed: quota.message != nil, updated: quota.updated, now: now)
        VStack(alignment: .leading, spacing: 6) {
            Text("CODEX WEATHER").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundColor(.secondary)
            if quota.enabled && !quota.windows.isEmpty {
                HStack(spacing: 10) {
                    ForEach(quota.windows) { window in
                        HStack(spacing: 6) {
                            PixelQuotaWeather(sky: sky == .unavailable ? .unavailable : QuotaSky.window(window, now: now)).frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(window.compact + " left").font(.system(size: 9)).foregroundColor(.secondary)
                                Text(window.resetsAt <= now ? "—" : (window.remaining == 0 && window.used < 100 ? "<1%" : "\(window.remaining)%"))
                                    .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                                    .foregroundColor(sky == .unavailable ? .secondary : .primary)
                                Text(QuotaResetCountdown.label(reset: window.resetsAt, now: now))
                                    .font(.system(size: 9)).foregroundColor(.secondary).monospacedDigit()
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(window.label), \(window.resetsAt <= now ? "reset pending" : (window.remaining == 0 && window.used < 100 ? "less than 1 percent remaining" : "\(window.remaining) percent remaining")), \(sky == .unavailable ? "cached reading" : QuotaSky.window(window, now: now).title)")
                    }
                }
            } else {
                HStack(spacing: 8) {
                    PixelQuotaWeather(sky: sky).frame(width: 32, height: 32)
                    Text(sky == .off ? "Quota weather is off" : sky == .checking ? "Checking quota…" : "Quota unavailable")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            if quota.enabled && quota.message == nil, let window = quota.windows.first, let trend = quota.history.trend(for: window,now: now) {
                Text("\(window.compact) · " + trend.shortLabel).font(.system(size: 9)).foregroundColor(.secondary)
            }
            Text(sky == .unavailable && !quota.windows.isEmpty ? "Cached reading · Open to retry" : sky.title)
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .help("Weather follows your remaining Codex quota. Open for reset times and refresh.")
    }
}
