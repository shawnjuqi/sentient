import SwiftUI
import WhisperKit
import AVFoundation

// MARK: - Audio Processor Helper

/// Handles raw audio processing on a background thread to avoid blocking the Main Actor.
/// Thread-safe: All shared state is protected by NSLock.
/// @unchecked Sendable: We manually ensure thread safety, so Swift trusts us.
final class AudioProcessor: @unchecked Sendable {
    
    // MARK: - Private State (All protected by lock)
    
    private var audioBuffer: [Float] = []
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    
    /// Target format: 16kHz mono Float32 (WhisperKit's expected input)
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!
    
    // MARK: - Public API
    
    /// Processes an audio buffer from the microphone tap.
    /// Converts to 16kHz and appends to internal buffer.
    /// Called from the audio thread - must be thread-safe.
    func process(buffer: AVAudioPCMBuffer) {
        let inputFormat = buffer.format
        
        // --- LOCK: Access/initialize converter ---
        lock.lock()
        
        // Lazy initialization of converter on first buffer
        // This avoids main thread → audio thread race condition
        if converter == nil {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            if converter == nil {
                Log.error("Failed to create converter", category: "AudioProcessor")
                lock.unlock()
                return
            }
        }
        
        // Copy converter reference while holding lock
        let conv = converter!
        
        // --- UNLOCK: Conversion is CPU-bound, don't hold lock during it ---
        lock.unlock()
        
        // Calculate output buffer capacity based on sample rate ratio
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = UInt32(ceil(Double(buffer.frameLength) * ratio))
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            Log.error("Failed to create output buffer", category: "AudioProcessor")
            return
        }
        
        // Track if input has been consumed (converter may call multiple times)
        var inputConsumed = false
        
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        var error: NSError?
        let status = conv.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error {
            Log.error("Conversion error: \(error?.localizedDescription ?? "unknown")", category: "AudioProcessor")
            return
        }
        
        // Extract samples from converted buffer
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
        
        // --- LOCK: Append to shared buffer ---
        lock.lock()
        defer { lock.unlock() }
        audioBuffer.append(contentsOf: samples)
    }
    
    /// Returns accumulated audio samples and clears the buffer.
    /// Called from main thread after recording stops.
    func retrieveAndClearAudio() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        let data = audioBuffer
        audioBuffer.removeAll(keepingCapacity: true)
        
        // Reset converter to flush internal state
        converter?.reset()
        
        return data
    }
    
    /// Clears buffer and resets converter without returning data.
    /// Called when starting a new recording or clearing all.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        audioBuffer.removeAll(keepingCapacity: true)
        converter?.reset()
        converter = nil  // Force re-creation on next recording (handles format changes)
    }
}

// MARK: - Main Speech Recognizer

/// Manages speech-to-text using WhisperKit and integrates with GrokService.
/// @MainActor ensures all UI-related state updates happen on the main thread.
@MainActor
class SpeechRecognizer: ObservableObject {
    
    // MARK: - Published State
    
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
    
    // MARK: - Private Properties
    
    /// WhisperKit speech recognition pipeline
    private var whisperPipe: WhisperKit?
    
    /// Audio engine for capturing microphone input
    private let audioEngine = AVAudioEngine()
    
    /// Thread-safe audio processor (handles all audio thread work)
    private let audioProcessor = AudioProcessor()
    
    /// Grok API service (actor-isolated for thread safety)
    private let grokService = GrokService()
    
    // MARK: - Initialization
    
    init() {
        Task {
            await setupWhisper()
        }
    }
    
    /// Loads the WhisperKit model asynchronously
    private func setupWhisper() async {
        do {
            Log.debug("Loading WhisperKit...", category: "SpeechRecognizer")
            whisperPipe = try await WhisperKit(model: "distil-large-v3")
            isModelLoading = false
            Log.debug("WhisperKit loaded successfully.", category: "SpeechRecognizer")
        } catch {
            Log.error("Error loading WhisperKit: \(error)", category: "SpeechRecognizer")
            isModelLoading = false
            errorMessage = "Failed to load speech recognition model. Please restart the app."
        }
    }
    
    // MARK: - Public API
    
    /// Toggles recording state (start/stop)
    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }
    
    /// Clears transcript and AI response
    func clearAll() {
        transcript = ""
        aiResponse = ""
        errorMessage = nil
        audioProcessor.clear()
        Task {
            await grokService.cancelRequest()
        }
    }
    
    /// Clears the current error message
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Recording
    
    private func startRecording() {
        // Clear any previous error when attempting to record
        errorMessage = nil
        
        guard !isModelLoading else {
            Log.debug("Cannot record: model still loading", category: "SpeechRecognizer")
            errorMessage = "Please wait, speech model is still loading..."
            return
        }
        
        // Check if model failed to load
        guard whisperPipe != nil else {
            errorMessage = "Speech model not available. Please restart the app."
            return
        }
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setupAndStartEngine()
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted {
                        self.setupAndStartEngine()
                    } else {
                        Log.error("Microphone access denied by user", category: "SpeechRecognizer")
                        self.microphonePermissionDenied = true
                        self.errorMessage = "Microphone access is required to use voice input."
                    }
                }
            }
            
        case .denied, .restricted:
            Log.error("Microphone access denied. Enable in System Settings > Privacy > Microphone", category: "SpeechRecognizer")
            microphonePermissionDenied = true
            errorMessage = "Microphone access denied. Please enable in System Settings."
            
        @unknown default:
            break
        }
    }
    
    private func setupAndStartEngine() {
        // Stop engine if already running
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        let inputNode = audioEngine.inputNode
        
        // Remove existing tap and reset engine
        inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        
        // Clear previous audio data and reset converter
        audioProcessor.clear()
        
        // Get hardware's native format
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        Log.debug("Hardware format: \(hardwareFormat.sampleRate) Hz, \(hardwareFormat.channelCount) ch", category: "SpeechRecognizer")
        
        // Capture local reference to processor to avoid capturing 'self' in audio callback
        // This is critical: the audio callback runs on a background thread
        let processor = self.audioProcessor
        
        // Install tap - closure captures only 'processor', not 'self'
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            // Runs on audio thread - processor handles thread safety internally
            processor.process(buffer: buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            Log.debug("Recording started", category: "SpeechRecognizer")
        } catch {
            Log.error("Failed to start audio engine: \(error)", category: "SpeechRecognizer")
            inputNode.removeTap(onBus: 0)
            audioEngine.reset()
            errorMessage = "Unable to access microphone. Please check your audio settings."
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        
        // Stop engine and remove tap
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        
        Log.debug("Recording stopped", category: "SpeechRecognizer")
        
        // Transcribe and send to Grok
        Task {
            await transcribeAndSendToGrok()
        }
    }
    
    // MARK: - Transcription & AI
    
    private func transcribeAndSendToGrok() async {
        guard let pipe = whisperPipe else {
            Log.error("WhisperKit not initialized", category: "SpeechRecognizer")
            errorMessage = "Speech recognition not available."
            return
        }
        
        // Retrieve audio from processor (thread-safe, clears buffer)
        let audioSamples = audioProcessor.retrieveAndClearAudio()
        
        guard !audioSamples.isEmpty else {
            Log.debug("No audio to transcribe", category: "SpeechRecognizer")
            errorMessage = "No audio recorded. Try speaking louder or check your microphone."
            return
        }
        
        // Debug stats
        let maxAmplitude = audioSamples.map { abs($0) }.max() ?? 0
        let avgAmplitude = audioSamples.reduce(0) { $0 + abs($1) } / Float(audioSamples.count)
        let durationSeconds = Double(audioSamples.count) / 16000.0
        Log.debug("Transcribing \(audioSamples.count) samples (\(String(format: "%.1f", durationSeconds))s @ 16kHz)", category: "SpeechRecognizer")
        Log.debug("Amplitude - max: \(String(format: "%.3f", maxAmplitude)), avg: \(String(format: "%.4f", avgAmplitude))", category: "SpeechRecognizer")
        
        do {
            // WhisperKit expects [Float] at 16kHz (already converted by processor)
            let results = try await pipe.transcribe(audioArray: audioSamples)
            
            if let text = results.first?.text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                transcript = text.trimmingCharacters(in: .whitespaces)
                Log.debug("Transcription: \(transcript)", category: "SpeechRecognizer")
                
                await sendToGrok(prompt: transcript)
            } else {
                Log.debug("No speech detected", category: "SpeechRecognizer")
                errorMessage = "No speech detected. Please try again."
            }
        } catch {
            Log.error("Transcription error: \(error)", category: "SpeechRecognizer")
            errorMessage = "Failed to transcribe speech. Please try again."
        }
    }
    
    private func sendToGrok(prompt: String) async {
        isProcessingAI = true
        aiResponse = ""
        
        Log.debug("Sending to Grok: \(prompt)", category: "SpeechRecognizer")
        
        await grokService.streamResponse(
            prompt: prompt,
            onToken: { [weak self] token in
                self?.aiResponse += token
            },
            onComplete: { [weak self] in
                self?.isProcessingAI = false
                Log.debug("Grok response complete", category: "SpeechRecognizer")
            },
            onError: { [weak self] error in
                self?.isProcessingAI = false
                self?.aiResponse = "Error: \(error.localizedDescription)"
                Log.error("Grok error: \(error)", category: "SpeechRecognizer")
            }
        )
    }
}
