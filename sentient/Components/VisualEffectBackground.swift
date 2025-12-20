import SwiftUI
import AppKit

// MARK: - Visual Effect Background
struct VisualEffectBackground: NSViewRepresentable {
    /// Material defines the blur/tint style.
    /// - .hudWindow: Dark translucent style similar to media HUDs
    /// - .popover: Lighter, similar to system popovers
    /// - .sidebar: Even lighter, like Finder sidebar
    let material: NSVisualEffectView.Material
    
    /// Blending mode determines how the blur interacts with content behind.
    /// - .behindWindow: Blurs content from windows behind this one
    /// - .withinWindow: Blurs content within the same window
    let blendingMode: NSVisualEffectView.BlendingMode
    
    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // .active: Always show the vibrancy effect, even when window is inactive
        view.state = .active
        // Required for proper transparency compositing
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
