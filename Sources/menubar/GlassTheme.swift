import SwiftUI

enum LidlightPalette {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let iris = adaptive(light: NSColor(red: 0.40,green: 0.28,blue: 0.68,alpha: 1),dark: NSColor(red: 0.80,green: 0.74,blue: 1,alpha: 1))
    static let mist = adaptive(light: NSColor(red: 0.16,green: 0.44,blue: 0.55,alpha: 1),dark: NSColor(red: 0.52,green: 0.82,blue: 0.88,alpha: 1))
    static let peach = adaptive(light: NSColor(red: 0.70,green: 0.31,blue: 0.20,alpha: 1),dark: NSColor(red: 1,green: 0.73,blue: 0.62,alpha: 1))
}

private struct OpaquePreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Allows the layout renderer to inspect the solid accessibility appearance.
    var lidlightOpaquePreview: Bool {
        get { self[OpaquePreviewKey.self] }
        set { self[OpaquePreviewKey.self] = newValue }
    }
}

/// A frosted panel supports readable content; controls retain a subtle glass finish.
extension View {
    func lidlightGlass(selected: Bool = false, radius: CGFloat = 14) -> some View {
        modifier(GlassControl(selected: selected, radius: radius))
    }
    func lidlightCard(radius: CGFloat = 18) -> some View {
        modifier(ContentSurface(radius: radius))
    }
}

private struct GlassControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.lidlightOpaquePreview) private var opaquePreview
    let selected: Bool
    let radius: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || opaquePreview {
            content.background {
                RoundedRectangle(cornerRadius: radius).fill(Color(nsColor: .controlColor))
                    .overlay(RoundedRectangle(cornerRadius: radius).fill(LidlightPalette.iris.opacity(selected ? 0.18 : 0.055)))
            }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(selected ? LidlightPalette.iris.opacity(0.08) : nil).interactive(), in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
    }
}

private struct ContentSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.lidlightOpaquePreview) private var opaquePreview
    let radius: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || opaquePreview {
            content.background {
                RoundedRectangle(cornerRadius: radius).fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: radius).fill(LidlightPalette.iris.opacity(0.035)))
            }
        } else {
            content.background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.24))
            }.overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.035), .white.opacity(0.09)],startPoint: .topLeading,endPoint: .bottomTrailing),lineWidth: 0.65)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .underWindowBackground
    }
}

struct PanelBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.lidlightOpaquePreview) private var opaquePreview
    var body: some View {
        ZStack {
            if reduceTransparency || opaquePreview { Color(nsColor: .windowBackgroundColor) }
            else {
                PanelMaterial()
                // Keep the blur at full strength; tint it instead of exposing a sharp desktop.
                Color(nsColor: .windowBackgroundColor).opacity(0.32)
            }
            LinearGradient(colors: [LidlightPalette.iris.opacity(0.018), LidlightPalette.mist.opacity(0.008), LidlightPalette.peach.opacity(0.012)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.overlay {
            RoundedRectangle(cornerRadius: 26).strokeBorder(
                LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05), .white.opacity(0.14)],startPoint: .topLeading,endPoint: .bottomTrailing),lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

struct GlassActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundColor(.primary).padding(.horizontal, 11).padding(.vertical, 8)
            .lidlightGlass().opacity(configuration.isPressed ? 0.7 : 1)
    }
}
