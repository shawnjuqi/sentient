import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Keyboard shortcut to toggle the overlay panel visibility
    /// Default: Option+Space (same as before, but now user-customizable)
    static let toggleOverlay = Self("toggleOverlay", default: .init(.space, modifiers: [.option]))
    
    /// Keyboard shortcut to start/stop voice recording
    /// Default: Option+R (R for Record)
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.option]))
}
