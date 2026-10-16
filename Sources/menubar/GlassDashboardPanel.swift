import AppKit

/// An anchored, transparent window avoids the opaque background of an NSPopover.
final class GlassDashboardPanel: NSPanel {
    private weak var anchor: NSView?
    private var localClicks: Any?
    private var globalClicks: Any?
    private var applicationChange: NSObjectProtocol?
    private var displayChange: NSObjectProtocol?
    var isShown: Bool { isVisible }
    var contentSize: NSSize {
        get { contentRect(forFrameRect: frame).size }
        set { setContentSize(newValue) }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: NSRect(x: 0,y: 0,width: 380,height: 600),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .none
        title = "Lidlight"
    }
    static func anchoredFrame(anchor: NSRect, size: NSSize, visible: NSRect) -> NSRect {
        let inset = visible.insetBy(dx: 8,dy: 8)
        let width = min(size.width,inset.width)
        let height = min(size.height,inset.height)
        return NSRect(x: min(max(anchor.midX-width/2,inset.minX),inset.maxX-width),
                      y: min(max(anchor.minY-height-6,inset.minY),inset.maxY-height),
                      width: width,height: height)
    }
    func show(relativeTo bounds: NSRect, of view: NSView) {
        guard let window = view.window, let screen = window.screen else { return }
        removeMonitors()
        anchor = view
        let rect = window.convertToScreen(view.convert(bounds,to: nil))
        setFrame(Self.anchoredFrame(anchor: rect,size: contentSize,visible: screen.visibleFrame),display: false)
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 26
        contentView?.layer?.masksToBounds = true
        makeKeyAndOrderFront(nil)
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown,.rightMouseDown,.otherMouseDown]
        localClicks = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            guard let self, self.isVisible else { return event }
            // Keep embedded menus, popovers, sheets and the menu-bar toggle interactive.
            if event.window === self || self.childWindows?.contains(where: { $0 === event.window }) == true ||
                event.window?.isSheet == true || (event.window?.level.rawValue ?? 0) >= NSWindow.Level.popUpMenu.rawValue {
                return event
            }
            if let anchor = self.anchor, event.window === anchor.window,
               anchor.bounds.contains(anchor.convert(event.locationInWindow,from: nil)) { return event }
            self.close()
            return event
        }
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in self?.close() }
        applicationChange = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,object: nil,queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.close() }
        }
        displayChange = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,object: nil,queue: .main) { [weak self] _ in self?.close() }
    }
    override func cancelOperation(_ sender: Any?) { close() }
    override func close() {
        orderOut(nil)
        removeMonitors()
        anchor = nil
    }
    private func removeMonitors() {
        if let localClicks { NSEvent.removeMonitor(localClicks) }; localClicks = nil
        if let globalClicks { NSEvent.removeMonitor(globalClicks) }; globalClicks = nil
        if let applicationChange { NSWorkspace.shared.notificationCenter.removeObserver(applicationChange) }; applicationChange = nil
        if let displayChange { NotificationCenter.default.removeObserver(displayChange) }; displayChange = nil
    }
}
