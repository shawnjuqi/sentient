import SwiftUI

// MARK: - Page Enum

/// Tracks which page is currently displayed in the overlay
enum OverlayPage {
    case main
    case settings
}

// MARK: - OverlayViewModel

/// ViewModel for the overlay UI.
@MainActor
class OverlayViewModel: ObservableObject {
    
    // MARK: - Published UI State
    // These drive the UI. When they change, SwiftUI automatically re-renders.
    
    /// Current transcribed text from speech
    @Published var transcript: String = ""
    
    /// Streaming response from Grok AI
    @Published var aiResponse: String = ""
    
    /// True while WhisperKit model is loading
    @Published var isModelLoading: Bool = true
    
    /// True while actively recording audio
    @Published var isRecording: Bool = false
    
    /// True while waiting for/receiving AI response
    @Published var isProcessingAI: Bool = false
    
    /// User-facing error message (nil when no error)
    @Published var errorMessage: String?
    
    /// True if microphone permission was denied
    @Published var microphonePermissionDenied: Bool = false
    
    /// Current page in the overlay navigation
    @Published var currentPage: OverlayPage = .main
    
    // MARK: - Dependencies
    // Services are injected, making this testable.
    
    private let speechService: SpeechService
    private let grokService: GrokService
    
    // MARK: - Initialization
    
    /// Creates the ViewModel with its required services.
    init(speechService: SpeechService, grokService: GrokService) {
        self.speechService = speechService
        self.grokService = grokService
        
        // Start loading the speech model
        Task {
            await loadSpeechModel()
        }
    }
    
    /// Convenience initializer that creates default services.
    /// Used in production; the full initializer is used for testing.
    convenience init() {
        self.init(
            speechService: SpeechService(),
            grokService: GrokService()
        )
    }
    
    // MARK: - Model Loading
    
    private func loadSpeechModel() async {
        do {
            try await speechService.loadModel()
            isModelLoading = false
            Log.debug("Speech model loaded", category: "OverlayViewModel")
        } catch {
            isModelLoading = false
            errorMessage = "Failed to load speech recognition model. Please restart the app."
            Log.error("Failed to load speech model: \(error)", category: "OverlayViewModel")
        }
    }
    
    // MARK: - Public Actions
    // These are called by the View in response to user interaction.
    // Notice how they update UI state AND coordinate service calls.
    
    /// Toggles recording state (start/stop)
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Clears transcript and AI response
    func clearAll() {
        transcript = ""
        aiResponse = ""
        errorMessage = nil
        speechService.clearAudio()
        Task {
            await grokService.cancelRequest()
        }
    }
    
    /// Clears the current error message
    func clearError() {
        errorMessage = nil
    }
    
    /// Navigate to settings page
    func showSettings() {
        currentPage = .settings
    }
    
    /// Navigate back to main page
    func showMain() {
        currentPage = .main
    }
    
    // MARK: - Private Recording Logic
    
    private func startRecording() {
        // Clear any previous error
        errorMessage = nil
        
        // Validate state before starting
        guard !isModelLoading else {
            errorMessage = "Please wait, speech model is still loading..."
            return
        }
        
        guard speechService.isModelLoaded else {
            errorMessage = "Speech model not available. Please restart the app."
            return
        }
        
        // Attempt to start recording
        do {
            try speechService.startRecording()
            isRecording = true
            Log.debug("Recording started", category: "OverlayViewModel")
        } catch SpeechServiceError.microphonePermissionDenied {
            microphonePermissionDenied = true
            errorMessage = "Microphone access denied. Please enable in System Settings."
        } catch SpeechServiceError.microphonePermissionNotDetermined {
            // Request permission - this will call back asynchronously
            speechService.requestMicrophonePermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startRecording() // Retry after permission granted
                    } else {
                        self?.microphonePermissionDenied = true
                        self?.errorMessage = "Microphone access is required to use voice input."
                    }
                }
            }
        } catch {
            errorMessage = "Unable to access microphone. Please check your audio settings."
            Log.error("Failed to start recording: \(error)", category: "OverlayViewModel")
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        speechService.stopRecording()
        Log.debug("Recording stopped", category: "OverlayViewModel")
        
        // Transcribe and send to AI
        Task {
            await transcribeAndSendToGrok()
        }
    }
    
    // MARK: - Transcription & AI Coordination
    // This is "orchestration" - coordinating multiple services.
    
    private func transcribeAndSendToGrok() async {
        // Get transcription from speech service
        do {
            let text = try await speechService.transcribe()
            
            if text.isEmpty {
                errorMessage = "No speech detected. Please try again."
                return
            }
            
            transcript = text
            Log.debug("Transcription: \(text)", category: "OverlayViewModel")
            
            // Send to Grok
            await sendToGrok(prompt: text)
            
        } catch SpeechServiceError.noAudioRecorded {
            errorMessage = "No audio recorded. Try speaking louder or check your microphone."
        } catch {
            errorMessage = "Failed to transcribe speech. Please try again."
            Log.error("Transcription error: \(error)", category: "OverlayViewModel")
        }
    }
    
    private func sendToGrok(prompt: String) async {
        isProcessingAI = true
        aiResponse = ""
        
        Log.debug("Sending to Grok: \(prompt)", category: "OverlayViewModel")
        
        await grokService.streamResponse(
            prompt: prompt,
            onToken: { [weak self] token in
                self?.aiResponse += token
            },
            onComplete: { [weak self] in
                self?.isProcessingAI = false
                Log.debug("Grok response complete", category: "OverlayViewModel")
            },
            onError: { [weak self] error in
                self?.isProcessingAI = false
                self?.aiResponse = "Error: \(error.localizedDescription)"
                Log.error("Grok error: \(error)", category: "OverlayViewModel")
            }
        )
    }
}
