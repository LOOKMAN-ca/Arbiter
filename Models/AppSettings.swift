import SwiftUI
import Combine

final class AppSettings: ObservableObject {

    // MARK: — Login Credentials (Keychain-backed)

    @Published var claudeEmail:    String = "" {
        didSet { KeychainHelper.save(key: "claudeEmail",    value: claudeEmail) }
    }
    @Published var claudePassword: String = "" {
        didSet { KeychainHelper.save(key: "claudePassword", value: claudePassword) }
    }
    @Published var geminiEmail:    String = "" {
        didSet { KeychainHelper.save(key: "geminiEmail",    value: geminiEmail) }
    }
    @Published var geminiPassword: String = "" {
        didSet { KeychainHelper.save(key: "geminiPassword", value: geminiPassword) }
    }

    // MARK: — Model Selection (UserDefaults-backed)

    @Published var claudeModel: String = ModelCatalog.claude.first!.id {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }
    @Published var geminiModel: String = ModelCatalog.gemini.first!.id {
        didSet { UserDefaults.standard.set(geminiModel, forKey: "geminiModel") }
    }

    // MARK: — System Prompt (UserDefaults-backed)

    @Published var systemPromptOverride: String = "" {
        didSet { UserDefaults.standard.set(systemPromptOverride, forKey: "systemPromptOverride") }
    }

    // MARK: — Transient State

    @Published var claudeConnected: Bool = false
    @Published var geminiConnected: Bool = false

    var effectiveSystemPrompt: String {
        systemPromptOverride.isEmpty
            ? "You are Arbiter, a high-fidelity AI orchestrator."
            : systemPromptOverride
    }

    // MARK: — Init

    init() {
        self.claudeEmail    = KeychainHelper.load(key: "claudeEmail")
        self.claudePassword = KeychainHelper.load(key: "claudePassword")
        self.geminiEmail    = KeychainHelper.load(key: "geminiEmail")
        self.geminiPassword = KeychainHelper.load(key: "geminiPassword")

        if let saved = UserDefaults.standard.string(forKey: "claudeModel"), !saved.isEmpty {
            self.claudeModel = saved
        }
        if let saved = UserDefaults.standard.string(forKey: "geminiModel"), !saved.isEmpty {
            self.geminiModel = saved
        }
        if let saved = UserDefaults.standard.string(forKey: "systemPromptOverride") {
            self.systemPromptOverride = saved
        }
    }
}
