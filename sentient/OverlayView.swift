import SwiftUI
import KeyboardShortcuts

// MARK: - Page Enum

/// Tracks which page is currently displayed in the overlay
enum OverlayPage {
    case main
    case settings
}

// MARK: - Main Overlay Container

/// Container view that handles navigation between main and settings pages
struct OverlayView: View {
    @ObservedObject var speechRecognizer: SpeechRecognizer
    @State private var currentPage: OverlayPage = .main
    
    private let panelWidth: CGFloat = 500
    private let settingsHeight: CGFloat = 380
    
    /// Calculate dynamic height for main page based on response length
    private var mainPageHeight: CGFloat {
        let baseHeight: CGFloat = 360
        let maxHeight: CGFloat = 650
        
        let responseText = speechRecognizer.aiResponse
        if responseText.isEmpty {
            return baseHeight
        }
        
        // Estimate lines: ~55 chars per line at current width, ~22px per line
        let estimatedLines = ceil(Double(responseText.count) / 55.0)
        let additionalHeight = min(CGFloat(estimatedLines) * 22, 250)
        
        return min(baseHeight + additionalHeight, maxHeight)
    }
    
    /// Current height based on which page is active
    private var currentHeight: CGFloat {
        currentPage == .main ? mainPageHeight : settingsHeight
    }
    
    var body: some View {
        ZStack {
            // Glass effect background
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            
            // Page content with animation
            Group {
                switch currentPage {
                case .main:
                    MainPageView(
                        speechRecognizer: speechRecognizer,
                        onSettingsTapped: { currentPage = .settings }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    
                case .settings:
                    SettingsPageView(
                        onBackTapped: { currentPage = .main }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: currentPage)
        }
        .frame(width: panelWidth, height: currentHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: currentHeight)
    }
}

// MARK: - Main Page

/// The main voice input and AI response page
struct MainPageView: View {
    @ObservedObject var speechRecognizer: SpeechRecognizer
    var onSettingsTapped: () -> Void
    
    /// Check if API key is configured
    @AppStorage("xai_api_key") private var apiKey: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with settings button
            headerView
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // API key warning if not configured
            if apiKey.isEmpty {
                apiKeyWarning
            }
            
            // Error message if present
            if let error = speechRecognizer.errorMessage {
                errorBanner(message: error)
            }
            
            // Transcribed text section
            transcriptSection
            
            // AI response section
            responseSection
            
            // Recording controls
            controlsSection
        }
        .padding(20)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text("Sentient")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Status indicator
            statusBadge
            
            // Settings button
            Button(action: onSettingsTapped) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.1))
        )
    }
    
    private var statusColor: Color {
        if speechRecognizer.isModelLoading {
            return .orange
        } else if speechRecognizer.isRecording {
            return .red
        } else if speechRecognizer.isProcessingAI {
            return .blue
        } else {
            return .green
        }
    }
    
    private var statusText: String {
        if speechRecognizer.isModelLoading {
            return "Loading Model..."
        } else if speechRecognizer.isRecording {
            return "Listening..."
        } else if speechRecognizer.isProcessingAI {
            return "Thinking..."
        } else {
            return "Ready"
        }
    }
    
    // MARK: - API Key Warning
    
    private var apiKeyWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("API key required.")
                .font(.caption)
            Button("Configure") {
                onSettingsTapped()
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
        )
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Show "Open Settings" button for microphone permission errors
            if speechRecognizer.microphonePermissionDenied {
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            // Dismiss button
            Button {
                speechRecognizer.clearError()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.15))
        )
    }
    
    // MARK: - Transcript Section
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your Voice", systemImage: "mic.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(speechRecognizer.transcript.isEmpty ? "Press the button or Option+Space to speak..." : speechRecognizer.transcript)
                .font(.body)
                .foregroundColor(speechRecognizer.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }
    
    // MARK: - Response Section
    
    /// Calculate response box height based on content
    private var responseBoxHeight: CGFloat {
        let minHeight: CGFloat = 36  // Minimum height for placeholder text
        let maxHeight: CGFloat = 280 // Maximum before scrolling kicks in
        
        let responseText = speechRecognizer.aiResponse
        if responseText.isEmpty {
            return minHeight
        }
        
        // Estimate: ~55 chars per line, ~22px per line
        let estimatedLines = ceil(Double(responseText.count) / 55.0)
        let calculatedHeight = CGFloat(estimatedLines) * 22
        
        return min(max(calculatedHeight, minHeight), maxHeight)
    }
    
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Grok", systemImage: "sparkles")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView {
                Text(speechRecognizer.aiResponse.isEmpty ? "AI response will appear here..." : speechRecognizer.aiResponse)
                    .font(.body)
                    .foregroundColor(speechRecognizer.aiResponse.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled) // Allow copying response
            }
            .frame(height: responseBoxHeight)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
            .animation(.easeInOut(duration: 0.2), value: responseBoxHeight)
        }
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        HStack {
            // Record button
            Button(action: {
                speechRecognizer.toggleRecording()
            }) {
                HStack {
                    Image(systemName: speechRecognizer.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                    Text(speechRecognizer.isRecording ? "Stop" : "Record")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(speechRecognizer.isRecording ? .red : .accentColor)
            .disabled(speechRecognizer.isModelLoading)
            
            // Clear button
            Button(action: {
                speechRecognizer.clearAll()
            }) {
                Image(systemName: "trash")
                    .font(.title2)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.bordered)
            .disabled(speechRecognizer.transcript.isEmpty && speechRecognizer.aiResponse.isEmpty)
        }
    }
}

// MARK: - Settings Page

/// Settings page for API key configuration
struct SettingsPageView: View {
    var onBackTapped: () -> Void
    
    /// Persists API key to UserDefaults
    @AppStorage("xai_api_key") private var apiKey: String = ""
    
    /// Controls visibility of the API key
    @State private var showAPIKey: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with back button
            headerView
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // API Key section
            apiKeySection
            
            // Keyboard shortcuts info
            shortcutsSection
            
            Spacer()
            
            // Footer
            footerView
        }
        .padding(20)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button(action: onBackTapped) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            Text("Settings")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Invisible spacer for centering
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .opacity(0)
        }
    }
    
    // MARK: - API Key Section
    
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("xAI API Key")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Group {
                    if showAPIKey {
                        TextField("Enter your API key...", text: $apiKey)
                    } else {
                        SecureField("Enter your API key...", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                
                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help(showAPIKey ? "Hide" : "Show")
            }
            
            HStack {
                if !apiKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("API key configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Get your key from")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link("console.x.ai", destination: URL(string: "https://console.x.ai")!)
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    // MARK: - Shortcuts Section
    
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(spacing: 10) {
                // Toggle Overlay shortcut
                HStack {
                    Text("Toggle Overlay")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    KeyboardShortcuts.Recorder(for: .toggleOverlay)
                        .controlSize(.small)
                }
                
                // Toggle Recording shortcut
                HStack {
                    Text("Start/Stop Recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    KeyboardShortcuts.Recorder(for: .toggleRecording)
                        .controlSize(.small)
                }
            }
            
            Text("Click a recorder and press your desired key combination")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Text("Sentient v\(Bundle.main.appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Bundle Extension

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

// MARK: - Preview

#Preview {
    OverlayView(speechRecognizer: SpeechRecognizer())
}
