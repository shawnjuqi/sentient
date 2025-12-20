import Foundation
import WhisperKit
import AVFoundation

// MARK: - Speech Service Errors

/// Errors that can occur during speech recognition.
///
/// **Design Note:**
/// We use a dedicated error enum instead of generic errors because:
/// 1. Callers can handle specific cases (e.g., show "Open Settings" for permission errors)
/// 2. Error messages are centralized here, not scattered in catch blocks
/// 3. Errors are self-documenting
enum SpeechServiceError: LocalizedError {
    case modelNotLoaded
    case microphonePermissionDenied
    case microphonePermissionNotDetermined
    case audioEngineFailure(underlying: Error)
    case transcriptionFailed(underlying: Error)
    case noAudioRecorded
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Speech recognition model not loaded"
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .microphonePermissionNotDetermined:
            return "Microphone permission not yet requested"
        case .audioEngineFailure(let error):
            return "Audio engine error: \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "Transcription error: \(error.localizedDescription)"
        case .noAudioRecorded:
            return "No audio was recorded"
        }
    }
}

// MARK: - Audio Processor

/// Handles raw audio processing on a background thread to avoid blocking the Main Actor.
///
/// **Thread Safety Pattern:**
/// Audio callbacks run on a realtime audio thread, not the main thread.
/// We use NSLock to protect shared state (the audio buffer).
///
/// **@unchecked Sendable:**
/// We mark this as Sendable (can be passed between threads) but "unchecked"
/// because Swift can't verify our manual locking is correct.
/// We're promising the compiler: "trust me, I handle thread safety manually."
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
    ///
    /// **Called from audio thread** - must be thread-safe.
    func process(buffer: AVAudioPCMBuffer) {
        let inputFormat = buffer.format
        
        // --- LOCK: Access/initialize converter ---
        lock.lock()
        
        // Lazy initialization of converter on first buffer
        if converter == nil {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            if converter == nil {
                Log.error("Failed to create audio converter", category: "AudioProcessor")
                lock.unlock()
                return
            }
        }
        
        let conv = converter!
        lock.unlock()
        // --- UNLOCK: Conversion is CPU-bound, don't hold lock during it ---
        
        // Calculate output buffer capacity based on sample rate ratio
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = UInt32(ceil(Double(buffer.frameLength) * ratio))
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            Log.error("Failed to create output buffer", category: "AudioProcessor")
            return
        }
        
        // Track if input has been consumed
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
    func retrieveAndClearAudio() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        let data = audioBuffer
        audioBuffer.removeAll(keepingCapacity: true)
        converter?.reset()
        
        return data
    }
    
    /// Clears buffer and resets converter without returning data.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        audioBuffer.removeAll(keepingCapacity: true)
        converter?.reset()
        converter = nil
    }
}

// MARK: - Speech Service

/// Service for speech-to-text using WhisperKit.
///
/// ## Single Responsibility:
/// This service ONLY handles:
/// - Loading the WhisperKit model
/// - Capturing audio from the microphone
/// - Transcribing audio to text
///
/// It does NOT handle:
/// - UI state management (that's OverlayViewModel's job)
/// - AI responses (that's GrokService's job)
/// - Presenting errors to users (that's the View's job)
///
/// ## Why @MainActor?
/// AVAudioEngine and some WhisperKit operations need to run on the main thread.
/// Rather than sprinkling DispatchQueue.main everywhere, we isolate the whole class.
@MainActor
class SpeechService {
    
    // MARK: - Properties
    
    /// WhisperKit speech recognition pipeline
    private var whisperPipe: WhisperKit?
    
    /// Audio engine for capturing microphone input
    private let audioEngine = AVAudioEngine()
    
    /// Thread-safe audio processor
    private let audioProcessor = AudioProcessor()
    
    /// Whether the model has been loaded successfully
    var isModelLoaded: Bool {
        whisperPipe != nil
    }
    
    // MARK: - Model Loading
    
    /// Loads the WhisperKit model.
    /// Call this once at startup. Throws if loading fails.
    func loadModel() async throws {
        Log.debug("Loading WhisperKit model...", category: "SpeechService")
        whisperPipe = try await WhisperKit(model: "distil-large-v3")
        Log.debug("WhisperKit model loaded successfully", category: "SpeechService")
    }
    
    // MARK: - Microphone Permission
    
    /// Requests microphone permission asynchronously.
    /// - Parameter completion: Called with the result (granted or denied)
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
    
    // MARK: - Recording
    
    /// Starts recording audio from the microphone.
    /// - Throws: `SpeechServiceError` if permission denied or engine fails
    func startRecording() throws {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break // Continue below
        case .notDetermined:
            throw SpeechServiceError.microphonePermissionNotDetermined
        case .denied, .restricted:
            throw SpeechServiceError.microphonePermissionDenied
        @unknown default:
            throw SpeechServiceError.microphonePermissionDenied
        }
        
        // Setup and start the audio engine
        try setupAndStartEngine()
    }
    
    /// Stops recording and prepares audio for transcription.
    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
    }
    
    /// Clears any recorded audio without transcribing.
    func clearAudio() {
        audioProcessor.clear()
    }
    
    // MARK: - Transcription
    
    /// Transcribes the recorded audio and returns the text.
    /// - Returns: The transcribed text
    /// - Throws: `SpeechServiceError` if transcription fails
    func transcribe() async throws -> String {
        guard let pipe = whisperPipe else {
            throw SpeechServiceError.modelNotLoaded
        }
        
        // Retrieve audio from processor
        let audioSamples = audioProcessor.retrieveAndClearAudio()
        
        guard !audioSamples.isEmpty else {
            throw SpeechServiceError.noAudioRecorded
        }
        
        // Debug stats
        let durationSeconds = Double(audioSamples.count) / 16000.0
        Log.debug("Transcribing \(audioSamples.count) samples (\(String(format: "%.1f", durationSeconds))s)", category: "SpeechService")
        
        do {
            let results = try await pipe.transcribe(audioArray: audioSamples)
            
            // results.first is optional (array might be empty)
            // but .text is a non-optional String
            if let result = results.first {
                let text = result.text.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    return text
                }
            }
            return ""
        } catch {
            throw SpeechServiceError.transcriptionFailed(underlying: error)
        }
    }
    
    // MARK: - Private Helpers
    
    private func setupAndStartEngine() throws {
        // Stop engine if already running
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        let inputNode = audioEngine.inputNode
        
        // Remove existing tap and reset
        inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        
        // Clear previous audio
        audioProcessor.clear()
        
        // Get hardware's native format
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        Log.debug("Hardware format: \(hardwareFormat.sampleRate) Hz, \(hardwareFormat.channelCount) ch", category: "SpeechService")
        
        // Capture local reference to processor to avoid capturing 'self'
        let processor = self.audioProcessor
        
        // Install tap - closure captures only 'processor', not 'self'
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            processor.process(buffer: buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            audioEngine.reset()
            throw SpeechServiceError.audioEngineFailure(underlying: error)
        }
    }
}
