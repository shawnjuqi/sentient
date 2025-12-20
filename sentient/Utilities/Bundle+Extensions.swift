import Foundation

// MARK: - Bundle Extensions

extension Bundle {
    /// App version from Info.plist (e.g., "1.0.0")
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    /// Build number from Info.plist (e.g., "1")
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
