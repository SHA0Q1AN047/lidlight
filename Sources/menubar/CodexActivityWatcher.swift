import Foundation
import CoreServices

/// FSEvents coalesces writes; no polling or per-file descriptors while idle.
final class CodexActivityWatcher {
    private var stream: FSEventStreamRef?
    private let changed: ([URL], Bool) -> Void
    private let sessions: String
    init(root: URL, changed: @escaping ([URL], Bool) -> Void) {
        self.changed = changed
        sessions = root.resolvingSymlinksInPath().appendingPathComponent("sessions").path
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let owner = Unmanaged<CodexActivityWatcher>.fromOpaque(info).takeUnretainedValue()
            let names = unsafeBitCast(paths, to: NSArray.self) as! [String]
            var urls: [URL] = []
            var rescan = false
            for i in 0..<count {
                let dropped = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
                if flags[i] & FSEventStreamEventFlags(dropped) != 0 { rescan = true }
                let path = URL(fileURLWithPath: names[i]).resolvingSymlinksInPath().path
                if path.hasPrefix(owner.sessions + "/"), path.hasSuffix(".jsonl") { urls.append(URL(fileURLWithPath: path)) }
            }
            if !urls.isEmpty || rescan { owner.changed(urls, rescan) }
        }
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot
        stream = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25, FSEventStreamCreateFlags(flags))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            if !FSEventStreamStart(stream) { stop() }
        }
    }
    func stop() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
    }
    deinit { stop() }
}
