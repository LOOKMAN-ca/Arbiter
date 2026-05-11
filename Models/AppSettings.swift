import SwiftUI
import Combine

final class AppSettings: ObservableObject {

    // MARK: — API Keys (Keychain-backed)

    @Published var claudeApiKey: String = "" {
        didSet { KeychainHelper.save(key: "claudeApiKey", value: claudeApiKey) }
    }
    @Published var geminiApiKey: String = "" {
        didSet { KeychainHelper.save(key: "geminiApiKey", value: geminiApiKey) }
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
        // Load from new key, fall back to legacy key on first migration
        let claudeKey = KeychainHelper.load(key: "claudeApiKey")
        self.claudeApiKey = claudeKey.isEmpty ? KeychainHelper.load(key: "claudePassword") : claudeKey

        let geminiKey = KeychainHelper.load(key: "geminiApiKey")
        self.geminiApiKey = geminiKey.isEmpty ? KeychainHelper.load(key: "geminiPassword") : geminiKey

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
