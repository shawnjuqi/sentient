import AppKit
import SwiftUI

/// Custom NSPanel subclass for Spotlight-style floating overlay.
/// NSPanel is preferred over NSWindow for auxiliary floating windows because:
/// - It can float above standard windows without stealing focus from other apps
/// - It supports becoming key window while another app remains "active"
/// - Perfect for Spotlight-like transient UI
final class OverlayPanel: NSPanel {
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // .borderless: No title bar, close/minimize buttons, or resize handles
            // .nonactivatingPanel: Panel won't cause app to become "active" (other apps stay frontmost)
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configurePanel()
    }
    
    private func configurePanel() {
        // MARK: - Transparency & Background
        
        // isOpaque = false: Required for any transparency effects to work.
        // Without this, the window would render with a solid background.
        isOpaque = false
        
        // Clear background so only SwiftUI content is visible.
        // The glass effect comes from NSVisualEffectView in OverlayView.
        backgroundColor = .clear
        
        // MARK: - Window Level & Behavior
        
        // .floating: Window stays above normal windows from all apps.
        // Use .screenSaver for above-everything, but .floating is more polite.
        level = .floating
        
        // .canJoinAllSpaces: Panel appears on every virtual desktop/Space.
        // Without this, switching Spaces would hide the overlay.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // MARK: - Focus & Interaction
        
        // Allow panel to receive keyboard input (become key window).
        // Required for text fields and keyboard shortcuts to work.
        // NSPanel normally doesn't become key unless explicitly allowed.
        
        // hidesOnDeactivate = false: Don't auto-hide when another app activates.
        // Set to true if you want Spotlight-like behavior where clicking
        // elsewhere dismisses the panel.
        hidesOnDeactivate = false
        
        // MARK: - Visual Polish
        
        // hasShadow: Adds subtle drop shadow for depth.
        hasShadow = true
        
        // titlebarAppearsTransparent + titleVisibility: Even though we're borderless,
        // these ensure no residual title bar elements appear.
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        
        // isMovableByWindowBackground: Allows dragging the panel by its background.
        // Since we have no title bar, this is the only way to move it.
        isMovableByWindowBackground = true
        
        // animationBehavior: Smooth fade animation when showing/hiding.
        animationBehavior = .utilityWindow
    }
    
    // MARK: - Key Window Override
    
    /// Override to allow panel to become key window and receive keyboard events.
    /// NSPanel returns false by default for `canBecomeKey`.
    override var canBecomeKey: Bool {
        return true
    }
    
    /// Allow panel to become main window if needed.
    /// This enables proper focus behavior.
    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - Visual Effect Background View

/// NSView wrapper that provides the "glass" visual effect background.
/// This bridges NSVisualEffectView to SwiftUI via NSViewRepresentable.
struct VisualEffectBackground: NSViewRepresentable {
    /// Material defines the blur/tint style.
    /// .hudWindow: Dark translucent style similar to media HUDs
    /// .popover: Lighter, similar to system popovers
    /// .sidebar: Even lighter, like Finder sidebar
    let material: NSVisualEffectView.Material
    
    /// Blending mode determines how the blur interacts with content behind.
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
        // .behindWindow: Blurs content from windows behind this one
        // .withinWindow: Blurs content within the same window (rarely needed)
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
