import Foundation
@main struct WatcherTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("sessions/2025/01/01")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var received = Set<URL>()
        let watcher = CodexActivityWatcher(root: root) { urls, _ in received.formUnion(urls) }
        func waitFor(_ url: URL) {
            let deadline = Date().addingTimeInterval(8)
            while !received.contains(url) && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            assert(received.contains(url), "Missing filesystem event: \(url.path)")
            received.removeAll()
        }
        let file = folder.appendingPathComponent("test.jsonl")
        try Data("start\n".utf8).write(to: file)
        waitFor(file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("complete\n".utf8)); try handle.close()
        waitFor(file)
        watcher.stop()
        try Data("stopped\n".utf8).write(to: file)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        assert(received.isEmpty)
        print("Codex filesystem watcher: create, append, stop passed")
    }
}
