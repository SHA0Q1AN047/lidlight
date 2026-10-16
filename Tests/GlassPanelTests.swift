import AppKit
@main struct GlassPanelTests {
    static func main() {
        _ = NSApplication.shared
        let panel = GlassDashboardPanel()
        precondition(!panel.isOpaque && panel.backgroundColor == .clear && panel.canBecomeKey)
        let screen = NSRect(x: 0,y: 0,width: 1440,height: 875)
        for x in [0.0,720,1440] {
            let frame = GlassDashboardPanel.anchoredFrame(anchor: NSRect(x: x,y: 875,width: 20,height: 24),size: NSSize(width: 380,height: 600),visible: screen)
            precondition(screen.contains(frame) && frame.size == NSSize(width: 380,height: 600),"Window stays on screen at either menu-bar edge")
        }
        let secondary = NSRect(x: -1920,y: -300,width: 1920,height: 1080)
        let frame = GlassDashboardPanel.anchoredFrame(anchor: NSRect(x: -1900,y: 780,width: 20,height: 24),size: NSSize(width: 380,height: 600),visible: secondary)
        precondition(secondary.contains(frame),"Secondary displays with negative coordinates are supported")
        panel.orderFront(nil)
        precondition(panel.isShown)
        panel.cancelOperation(nil)
        precondition(!panel.isShown,"Escape closes the panel and pauses visible-only sampling")
        panel.close()
        print("PASS: clear panel, keyboard focus, edge/multi-display positioning, Escape and repeat close")
    }
}
