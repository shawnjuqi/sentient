import AppKit
import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    /// Menu bar status item (icon in menu bar)
    private var statusItem: NSStatusItem?
    
    /// Custom floating panel for the overlay
    private var overlayPanel: OverlayPanel?
    
    /// Shared speech recognizer instance
    private var speechRecognizer: SpeechRecognizer?
    
    // MARK: - App Lifecycle
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Start as .prohibited: No dock icon, no activation
        // This prevents the app from appearing in Cmd+Tab
        NSApp.setActivationPolicy(.prohibited)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Switch to .accessory: No dock icon, but can show windows/panels
        // This allows our panel to become key and receive input
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize components
        speechRecognizer = SpeechRecognizer()
        setupMenuBar()
        setupOverlayPanel()
        setupKeyboardShortcut()
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        // SF Symbol for menu bar icon
        button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Sentient")
        button.image?.isTemplate = true // Adapts to dark/light mode
        
        button.action = #selector(handleMenuBarClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }
    
    @objc private func handleMenuBarClick(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseDown {
            showContextMenu()
        } else {
            toggleOverlay()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: "Toggle Overlay",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Sentient",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        if let button = statusItem?.button {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
                in: button
            )
        }
    }
    
    // MARK: - Overlay Panel Setup
    
    private func setupOverlayPanel() {
        // Calculate centered position on screen
        guard let screen = NSScreen.main else { return }
        
        let panelWidth: CGFloat = 500
        let panelHeight: CGFloat = 350
        
        // Position panel in upper-center of screen (like Spotlight)
        let xPos = (screen.frame.width - panelWidth) / 2
        let yPos = screen.frame.height * 0.65 // Upper third of screen
        
        let contentRect = NSRect(x: xPos, y: yPos, width: panelWidth, height: panelHeight)
        
        overlayPanel = OverlayPanel(contentRect: contentRect)
        
        // Create SwiftUI view and host it in the panel
        if let recognizer = speechRecognizer {
            let overlayView = OverlayView(speechRecognizer: recognizer)
            let hostingView = NSHostingView(rootView: overlayView)
            
            // Required for transparent background to work properly
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear
            
            overlayPanel?.contentView = hostingView
        }
        
        // Start hidden
        overlayPanel?.orderOut(nil)
    }
    
    // MARK: - Keyboard Shortcuts (using KeyboardShortcuts package)
    
    private func setupKeyboardShortcut() {
        // Register listener for the toggle overlay shortcut
        // KeyboardShortcuts handles all the complexity:
        // - Global monitoring (works when other apps are focused)
        // - Local monitoring (works when this app is focused)
        // - User customization (stored in UserDefaults)
        // - Conflict detection with system shortcuts
        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) { [weak self] in
            self?.toggleOverlay()
        }
        
        // Register listener for the toggle recording shortcut
        // This allows users to start/stop recording from anywhere
        // Must dispatch to MainActor since SpeechRecognizer is @MainActor isolated
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                self?.speechRecognizer?.toggleRecording()
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleOverlay() {
        guard let panel = overlayPanel else { return }
        
        if panel.isVisible {
            // Hide with animation
            panel.animator().alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                panel.orderOut(nil)
                panel.alphaValue = 1 // Reset for next show
            }
        } else {
            // Recenter panel on current screen
            recenterPanel()
            
            // Activate app FIRST to ensure window operations succeed
            // This is critical for accessory apps without established window presence
            NSApp.activate(ignoringOtherApps: true)
            
            // Show with animation
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            panel.animator().alphaValue = 1
        }
    }
    
    /// Recenters panel on the current main screen
    private func recenterPanel() {
        guard let panel = overlayPanel, let screen = NSScreen.main else { return }
        
        let panelWidth = panel.frame.width
        
        let xPos = (screen.frame.width - panelWidth) / 2 + screen.frame.origin.x
        let yPos = screen.frame.height * 0.65 + screen.frame.origin.y
        
        panel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
