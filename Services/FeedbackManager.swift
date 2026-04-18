import AVFoundation
import Combine
import SwiftUI

@MainActor
class FeedbackManager: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func acknowledge(command: ArbiterVoiceCommand, locale: String) {
        let message: String
        if locale.contains("it") {
            switch command {
            case .execute:  message = "Esecuzione avviata."
            case .abort:    message = "Protocollo interrotto."
            case .validate: message = "Analisi avviata."
            default: return
            }
        } else {
            switch command {
            case .execute:  message = "Sequence engaged."
            case .abort:    message = "Aborted."
            case .validate: message = "Validating parameters."
            default: return
            }
        }
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.pitchMultiplier = 0.85
        synthesizer.speak(utterance)
    }
}
