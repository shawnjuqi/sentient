import Foundation

/// Debug-only logging utility.
/// All log calls are completely removed from release builds.
enum Log {
    /// Logs a debug message. Removed in release builds.
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: Optional category prefix (e.g., "SpeechRecognizer")
    static func debug(_ message: String, category: String? = nil) {
        #if DEBUG
        if let category = category {
            print("[\(category)] \(message)")
        } else {
            print(message)
        }
        #endif
    }
    
    /// Logs an error message. Removed in release builds.
    /// For errors that should also show in UI, handle separately.
    static func error(_ message: String, category: String? = nil) {
        #if DEBUG
        if let category = category {
            print("[\(category)] ❌ \(message)")
        } else {
            print("❌ \(message)")
        }
        #endif
    }
}

