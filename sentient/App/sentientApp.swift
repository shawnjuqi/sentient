import SwiftUI

/// Main app entry point.
/// Uses NSApplicationDelegateAdaptor to bridge AppDelegate for AppKit functionality.
/// The app runs as a menu bar accessory without a dock icon or main window.
@main
struct SentientApp: App {
    // Bridge AppDelegate to SwiftUI app lifecycle
    // This allows us to use AppKit APIs (NSPanel, NSEvent monitors, etc.)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty Settings scene
        Settings {
            EmptyView()
        }
    }
}
