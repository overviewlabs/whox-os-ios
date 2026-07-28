import Foundation
import Observation
@preconcurrency import AVFoundation
@preconcurrency import Speech
import WHOXCore

@MainActor @Observable
final class VoiceInputService {
    var isRecording = false
    var isStarting = false
    var isFinalizing = false
    var transcript = ""
    var level: Double = 0
    var errorMessage: String?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var finalizationTask: Task<Void, Never>?
    @ObservationIgnored private var hasInputTap = false
    @ObservationIgnored private var prefix = ""
    @ObservationIgnored private var startRequestID = UUID()
    @ObservationIgnored private var activeRecognitionID: UUID?
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording || self.isStarting else { return }
                    self.cancel()
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                guard let reason, VoiceCapturePolicy.shouldCancelForRouteChange(reasonRawValue: reason) else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording || self.isStarting else { return }
                    self.cancel()
                }
            },
        ]
    }

    func start(existingText: String) async {
        guard !isRecording, !isStarting, !isFinalizing else { return }
        discardRecognition()
        let requestID = UUID()
        startRequestID = requestID
        isStarting = true
        errorMessage = nil
        defer {
            if startRequestID == requestID { isStarting = false }
        }

        guard await requestSpeechAuthorization(), startRequestID == requestID else {
            if startRequestID == requestID {
                errorMessage = "Enable Speech Recognition for WHOX OS in Settings to transcribe audio."
            }
            return
        }
        guard await requestMicrophoneAuthorization(), startRequestID == requestID else {
            if startRequestID == requestID {
                errorMessage = "Enable Microphone access for WHOX OS in Settings to record audio."
            }
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            if startRequestID == requestID {
                errorMessage = "Speech recognition is temporarily unavailable."
            }
            return
        }

        prefix = existingText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = prefix
        let speechRequest = SFSpeechAudioBufferRecognitionRequest()
        speechRequest.shouldReportPartialResults = true
        speechRequest.taskHint = .dictation
        recognitionRequest = speechRequest
        let recognitionID = UUID()
        activeRecognitionID = recognitionID

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            guard startRequestID == requestID else {
                discardRecognition()
                return
            }

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceInputError.noAudioInput
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self, speechRequest] buffer, _ in
                speechRequest.append(buffer)
                let visualLevel = Self.meterLevel(buffer)
                Task { @MainActor [weak self] in
                    guard self?.activeRecognitionID == recognitionID else { return }
                    self?.level = visualLevel
                }
            }
            hasInputTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            isStarting = false

            recognitionTask = recognizer.recognitionTask(with: speechRequest) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                Task { @MainActor [weak self] in
                    guard let self, self.activeRecognitionID == recognitionID else { return }
                    if let text {
                        self.transcript = self.prefix.isEmpty ? text : self.prefix + (text.isEmpty ? "" : " " + text)
                    }
                    if let error, !isFinal {
                        self.errorMessage = error.localizedDescription
                    }
                    if isFinal || error != nil {
                        self.finishRecognition(recognitionID, cancel: false)
                    }
                }
            }
        } catch {
            discardRecognition()
            if startRequestID == requestID {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "The microphone could not start."
            }
        }
    }

    /// Stops capture but leaves the recognition task alive briefly so its final result is delivered.
    func stop() {
        startRequestID = UUID()
        isStarting = false
        guard isRecording, let recognitionID = activeRecognitionID else { return }
        recognitionRequest?.endAudio()
        stopAudioCapture()
        isFinalizing = true
        finalizationTask?.cancel()
        finalizationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.finishRecognition(recognitionID, cancel: true)
        }
    }

    /// Cancels pending authorization and active recognition without accepting late callbacks.
    func cancel() {
        startRequestID = UUID()
        isStarting = false
        discardRecognition()
    }

    private func finishRecognition(_ recognitionID: UUID, cancel: Bool) {
        guard activeRecognitionID == recognitionID else { return }
        finalizationTask?.cancel()
        finalizationTask = nil
        if cancel { recognitionTask?.cancel() }
        recognitionTask = nil
        recognitionRequest = nil
        activeRecognitionID = nil
        isFinalizing = false
        stopAudioCapture()
    }

    private func discardRecognition() {
        finalizationTask?.cancel()
        finalizationTask = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        activeRecognitionID = nil
        isFinalizing = false
        stopAudioCapture()
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated private static func meterLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        return AudioMeter.level(rms: sqrt(sum / Float(count)))
    }
}

private enum VoiceInputError: LocalizedError {
    case noAudioInput
    var errorDescription: String? { "No microphone input is available." }
}
