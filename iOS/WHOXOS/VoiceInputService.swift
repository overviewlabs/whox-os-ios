import Foundation
import Observation
@preconcurrency import AVFoundation
@preconcurrency import Speech
import WHOXCore

@MainActor @Observable
final class VoiceInputService {
    var isRecording = false
    var transcript = ""
    var level: Double = 0
    var errorMessage: String?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var hasInputTap = false
    @ObservationIgnored private var prefix = ""

    func start(existingText: String) async {
        guard !isRecording else { return }
        errorMessage = nil

        guard await requestSpeechAuthorization() else {
            errorMessage = "Enable Speech Recognition for WHOX OS in Settings to transcribe audio."
            return
        }
        guard await requestMicrophoneAuthorization() else {
            errorMessage = "Enable Microphone access for WHOX OS in Settings to record audio."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition is temporarily unavailable."
            return
        }

        stopEngine()
        prefix = existingText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = prefix

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceInputError.noAudioInput
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self, request] buffer, _ in
                request.append(buffer)
                let visualLevel = Self.meterLevel(buffer)
                Task { @MainActor [weak self] in
                    self?.level = visualLevel
                }
            }
            hasInputTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let text {
                        self.transcript = self.prefix.isEmpty ? text : self.prefix + (text.isEmpty ? "" : " " + text)
                    }
                    if let error, !isFinal {
                        self.errorMessage = error.localizedDescription
                    }
                    if isFinal || error != nil {
                        self.stop()
                    }
                }
            }
        } catch {
            stopEngine()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The microphone could not start."
        }
    }

    func stop() {
        guard isRecording || recognitionRequest != nil else { return }
        recognitionRequest?.endAudio()
        stopEngine()
    }

    private func stopEngine() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
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
