import Foundation

/// Reads only event types/timestamps from local Codex session logs. No prompts or credentials leave the Mac.
final class CodexActivityReader {
    private struct Cursor { var offset: UInt64 = 0; var modified: Date?; var active = false; var known = false; var seen = Date.distantPast; var remainder = Data() }
    private var cursors: [URL: Cursor] = [:]
    private let formatter = ISO8601DateFormatter()
    private let rootOverride: URL?
    private var discovered = Set<URL>()
    private var lastDiscovery = Date.distantPast
    init(root: URL? = nil) { rootOverride = root }
    static var root: URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    func changed(_ urls: [URL], rescan: Bool) {
        if rescan { lastDiscovery = .distantPast }
        for url in urls.prefix(257) { discovered.insert(url) }
    }
    func running(now: Date = Date()) -> Bool? {
        let root = (rootOverride ?? Self.root).resolvingSymlinksInPath()
        let sessions = root.appendingPathComponent("sessions")
        guard FileManager.default.isReadableFile(atPath: sessions.path) else { return nil }
        // Resumed threads keep their original date directory. Discover by modification time,
        // rather than overlooking a week-old thread which is running again today.
        if now.timeIntervalSince(lastDiscovery) >= 30 {
            guard let items = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
            var recent = Set<URL>()
            for case let url as URL in items where url.pathExtension == "jsonl" {
                let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if info?.isRegularFile == true, let modified = info?.contentModificationDate, now.timeIntervalSince(modified) < 2*86400 { recent.insert(url) }
                if recent.count > 256 { return nil }
            }
            discovered = recent; lastDiscovery = now
        }
        // New threads live in today's directory. Check only these shallow folders
        // between full scans, covering both UTC and local date boundaries.
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy/MM/dd"
        var days = Set<String>()
        for zone in [TimeZone.current, TimeZone(secondsFromGMT: 0)!] {
            dayFormatter.timeZone = zone
            for date in [now, now.addingTimeInterval(-86400)] { days.insert(dayFormatter.string(from: date)) }
        }
        for day in days {
            let folder = sessions.appendingPathComponent(day)
            let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            for url in entries where url.pathExtension == "jsonl" {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { discovered.insert(url) }
                if discovered.count > 256 { return nil }
            }
        }
        var files = Set(cursors.keys)
        files.formUnion(discovered)
        guard files.count <= 256 else { cursors.removeAll(); return nil }
        var uncertain = false
        for url in files {
            guard let handle = try? FileHandle(forReadingFrom: url) else { cursors.removeValue(forKey: url); uncertain = true; continue }
            defer { try? handle.close() }
            var cursor = cursors[url] ?? Cursor()
            guard let size = try? handle.seekToEnd() else { uncertain = true; continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if size < cursor.offset || size == cursor.offset && modified != cursor.modified { cursor = Cursor() }
            cursor.modified = modified
            if size - cursor.offset > 2_000_000 {
                cursor.offset = size - 2_000_000; cursor.remainder = Data(); cursor.active = false; cursor.known = false
                uncertain = true
            }
            do {
                try handle.seek(toOffset: cursor.offset)
                let data = try handle.read(upToCount: 2_000_000) ?? Data()
                cursor.offset += UInt64(data.count); cursor.remainder.append(data)
                while let end = cursor.remainder.firstIndex(of: 10) {
                    let line = cursor.remainder.prefix(upTo: end)
                    if let item = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                       item["type"] as? String == "event_msg",
                       let payload = item["payload"] as? [String: Any], let type = payload["type"] as? String {
                        if type == "task_started" { cursor.active = true; cursor.known = true }
                        if ["task_complete", "turn_aborted"].contains(type) { cursor.active = false; cursor.known = true }
                        if let timestamp = item["timestamp"] as? String {
                            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            if let date = formatter.date(from: timestamp) { cursor.seen = date }
                        }
                    }
                    cursor.remainder.removeSubrange(...end)
                }
                if cursor.remainder.count > 1_000_000 { cursor.remainder.removeAll(); uncertain = true }
                cursors[url] = cursor
            } catch { uncertain = true }
        }
        // A crashed or stale session is unknown, not a permanent running signal.
        let active = cursors.values.filter { $0.active }
        if active.contains(where: { now.timeIntervalSince($0.seen) < 900 }) { return true }
        if !active.isEmpty || cursors.isEmpty || cursors.values.contains(where: { !$0.known }) { uncertain = true }
        cursors = cursors.filter { now.timeIntervalSince($0.value.seen) < 2*86400 }
        return uncertain ? nil : false
    }
}

