import Foundation
import Speech
import Combine
import SwiftUI
import AVFoundation

@MainActor
class SpeechManager: ObservableObject {
    @Published var transcript            = ""
    @Published var isRecording           = false
    @Published var lastDetectedCommand: ArbiterVoiceCommand = .none

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private let commands: [String: ArbiterVoiceCommand] = [
        "execute":  .execute,
        "esegui":   .execute,
        "abort":    .abort,
        "annulla":  .abort,
        "validate": .validate,
        "convalida": .validate
    ]

    // MARK: — Public API

    /// Toggle recording on/off. Requests speech-recognition authorization on first use.
    func toggleRecording(locale: String = "en-US") {
        if isRecording {
            stopRecording()
            return
        }

        // Always ask for authorization; the OS caches the answer after first grant.
        Task {
            let status = await withCheckedContinuation {
                (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            guard status == .authorized else {
                print("ARBITER_SPEECH_ERR: Authorization denied — status \(status.rawValue)")
                return
            }
            startRecording(locale: locale)
        }
    }

    // MARK: — Private

    private func startRecording(locale: String) {
        // 1. Cancel any in-flight task
        recognitionTask?.cancel()
        recognitionTask = nil

        // 2. Build recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        // 3. Build recognizer for the requested locale
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.isAvailable
        else {
            print("ARBITER_SPEECH_ERR: Recognizer unavailable for locale \(locale)")
            return
        }

        // 4. Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcript = result.bestTranscription.formattedString.lowercased()
                self.checkForCommands(self.transcript)
            }
            if error != nil || result?.isFinal == true {
                self.stopRecording()
            }
        }

        // 5. Configure audio engine (no AVAudioSession on macOS)
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // 6. Start engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            print("ARBITER_AUDIO_ERR: Could not start engine — \(error.localizedDescription)")
            stopRecording()
        }
    }

    private func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }

    private func checkForCommands(_ text: String) {
        for (keyword, command) in commands {
            if text.contains(keyword) {
                lastDetectedCommand = command
                stopRecording()
                return
            }
        }
    }
}
