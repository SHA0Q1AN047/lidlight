import AppKit

/// Six original, integer-grid cat poses. Transparent eyes remain crisp in either menu-bar theme.
enum MenuBarIcon {
    static let frameCount = 6
    static let size = NSSize(width: 24, height: 18)
    private static let frames = (0..<frameCount).map { draw(frame: $0, warning: false) }
    private static let warningFrames = (0..<frameCount).map { draw(frame: $0, warning: true) }
    private static let sweatingFrames = (0..<frameCount).map { draw(frame: $0, warning: false, sweating: true) }
    private static let hotWarningFrames = (0..<frameCount).map { draw(frame: $0, warning: true, sweating: true) }
    static func cat(frame: Int, lowBattery: Bool = false, sweating: Bool = false) -> NSImage {
        (sweating ? (lowBattery ? hotWarningFrames : sweatingFrames) : (lowBattery ? warningFrames : frames))[((frame % frameCount) + frameCount) % frameCount]
    }
    static func pixels(frame: Int, warning: Bool = false, sweating: Bool = false) -> [[Bool]] {
        let phase = ((frame % frameCount) + frameCount) % frameCount
        let bounce = [0,0,-1,-1,0,0][phase]
        var pixels = Array(repeating: Array(repeating: false, count: 24), count: 18)
        func dot(_ x: Int, _ y: Int, _ filled: Bool = true) {
            if (0..<24).contains(x) && (0..<18).contains(y) { pixels[y][x] = filled }
        }
        func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
            for row in y..<(y+height) { for column in x..<(x+width) { dot(column,row) } }
        }
        // Body, pointed ears, muzzle and hooked tail; coordinates run top-to-bottom.
        rect(7,7+bounce,11,4); rect(9,6+bounce,8,1); rect(6,8+bounce,1,2)
        rect(16,4+bounce,6,4); rect(17,3+bounce,4,1)
        rect(16,2+bounce,2,2); dot(16,1+bounce)
        rect(20,2+bounce,2,2); dot(21,1+bounce)
        rect(21,6+bounce,2,2); dot(22,5+bounce)
        dot(20,5+bounce,false); dot(21,7+bounce,false)
        rect(5,6+bounce,2,2); rect(4,4+bounce,1,3); rect(3,3+bounce,2,1); dot(2,4+bounce)
        // Each leg is an independent pixel chain: planted, passing, extended, airborne.
        let legs: [[[(Int,Int)]]] = [
            [[(7,11),(6,12),(5,13),(4,13)],[(10,11),(11,12),(12,12)],[(15,11),(16,12),(17,13),(18,13)],[(17,10),(18,11),(19,11)]],
            [[(7,11),(7,12),(7,13),(8,13)],[(10,11),(9,12),(8,12)],[(15,11),(15,12),(15,13),(16,13)],[(17,10),(18,11),(19,12),(20,12)]],
            [[(7,11),(8,12),(9,12)],[(10,11),(8,11),(7,12)],[(15,11),(14,12),(13,12)],[(17,10),(17,11),(18,12),(19,12)]],
            [[(7,11),(8,12),(9,13),(10,13)],[(10,11),(9,12),(8,12)],[(15,11),(14,12),(13,13),(12,13)],[(17,10),(16,11),(15,11)]],
            [[(7,11),(7,12),(7,13),(8,13)],[(10,11),(11,12),(12,12)],[(15,11),(15,12),(15,13),(16,13)],[(17,10),(16,11),(15,12),(14,12)]],
            [[(7,11),(6,12),(5,12),(4,12)],[(10,11),(10,12),(11,13),(12,13)],[(15,11),(16,12),(17,12)],[(17,10),(16,11),(15,12),(14,12)]]
        ]
        for leg in legs[phase] { for (x,y) in leg { dot(x,y+bounce) } }
        if sweating {
            dot(20,5+bounce) // Worried, narrowed eye and a falling pixel sweat drop.
            dot(19,5+bounce,false)
            dot(23,9+bounce); rect(22,10+bounce,2,2); dot(23,12+bounce)
        }
        if warning { rect(0,6,1,4); dot(0,11) }
        return pixels
    }
    private static func draw(frame: Int, warning: Bool, sweating: Bool = false) -> NSImage {
        let pixels = pixels(frame: frame, warning: warning, sweating: sweating)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 36,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        if let data = rep.bitmapData {
            memset(data,0,rep.bytesPerRow * rep.pixelsHigh)
            for y in 0..<18 { for x in 0..<24 where pixels[y][x] {
                for dy in 0..<2 { for dx in 0..<2 { data[(y*2+dy)*rep.bytesPerRow+(x*2+dx)*4+3] = 255 } }
            } }
        }
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        image.accessibilityDescription = warning ? "Lidlight pixel cat · Low battery" : "Lidlight pixel cat"
        return image
    }
}
