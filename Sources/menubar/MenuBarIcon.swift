import AppKit

/// Integer-aligned template pixels stay crisp on Retina and standard displays.
enum MenuBarIcon {
    static let awake = draw(state: true)
    static let asleep = draw(state: false)
    static let unknown = draw(state: nil)
    static let lowBattery = draw(state: nil, lowBattery: true)

    static func image(awake: Bool?) -> NSImage {
        awake.map { $0 ? self.awake : asleep } ?? unknown
    }

    private static func draw(state: Bool?, lowBattery: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = false
            NSColor.black.setFill()
            func pixels(_ x: Int, _ y: Int, _ width: Int = 1, _ height: Int = 1) {
                NSRect(x: x, y: y, width: width, height: height).fill()
            }
            // A tiny laptop with cat ears, rather than a system status symbol.
            pixels(4, 14, 2, 2); pixels(14, 14, 2, 2)
            pixels(6, 14, 8); pixels(3, 6, 1, 8); pixels(16, 6, 1, 8)
            pixels(4, 5, 12); pixels(2, 3, 16); pixels(1, 4, 2); pixels(17, 4, 2)
            if lowBattery {
                pixels(9, 9, 2, 3); pixels(9, 6, 2)
            } else if state == true {
                pixels(6, 9, 2, 2); pixels(12, 9, 2, 2)
                pixels(9, 7, 2)
            } else if state == false {
                pixels(6, 9, 2); pixels(12, 9, 2)
                pixels(9, 7, 2)
            } else {
                pixels(8, 11, 3); pixels(11, 9, 1, 2)
                pixels(9, 8, 2); pixels(9, 6)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Lidlight · " + (lowBattery ? "Low battery" : (state.map { $0 ? "Awake" : "Sleep allowed" } ?? "Unknown"))
        return image
    }
}
