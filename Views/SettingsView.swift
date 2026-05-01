import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    @State private var claudeEmail          = ""
    @State private var claudePassword       = ""
    @State private var geminiEmail          = ""
    @State private var geminiPassword       = ""
    @State private var claudeModel          = ""
    @State private var geminiModel         = ""
    @State private var systemPromptOverride = ""

    @State private var claudeTest: TestState = .idle
    @State private var geminiTest: TestState = .idle

    enum TestState { case idle, testing, ok, fail }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    HStack(alignment: .top, spacing: 20) {
                        claudeColumn
                        Divider().background(Color.arbiterBorder)
                        geminiColumn
                    }
                    systemPromptSection
                }
                .padding(24)
            }
            footer
        }
        .background(Color.arbiterBg)
        .onAppear {
            claudeEmail          = settings.claudeEmail
            claudePassword       = settings.claudePassword
            geminiEmail          = settings.geminiEmail
            geminiPassword       = settings.geminiPassword
            claudeModel          = settings.claudeModel
            geminiModel          = settings.geminiModel
            systemPromptOverride = settings.systemPromptOverride
        }
    }

    // MARK: — Claude column

    private var claudeColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ANTHROPIC CLAUDE")
                .font(ArbiterFont.mono(10).bold())
                .foregroundColor(.arbiterCyan)

            TextField("EMAIL", text: $claudeEmail)
                .textFieldStyle(.roundedBorder)
                .font(ArbiterFont.mono(11))
                .onChange(of: claudeEmail) { _, _ in claudeTest = .idle }

            SecureField("PASSWORD", text: $claudePassword)
                .textFieldStyle(.roundedBorder)
                .font(ArbiterFont.mono(11))
                .onChange(of: claudePassword) { _, _ in claudeTest = .idle }

            Button(claudeTestLabel) { testClaude() }
                .font(ArbiterFont.mono(10))
                .foregroundColor(testStateColor(claudeTest))
                .disabled(claudeTest == .testing || claudePassword.isEmpty)

            Picker("MODEL", selection: $claudeModel) {
                ForEach(ModelCatalog.claude) { Text($0.label).tag($0.id) }
            }
            .font(ArbiterFont.mono(10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: — Gemini column

    private var geminiColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOOGLE GEMINI")
                .font(ArbiterFont.mono(10).bold())
                .foregroundColor(.arbiterCyan)

            TextField("EMAIL", text: $geminiEmail)
                .textFieldStyle(.roundedBorder)
                .font(ArbiterFont.mono(11))
                .onChange(of: geminiEmail) { _, _ in geminiTest = .idle }

            SecureField("PASSWORD", text: $geminiPassword)
                .textFieldStyle(.roundedBorder)
                .font(ArbiterFont.mono(11))
                .onChange(of: geminiPassword) { _, _ in geminiTest = .idle }

            Button(geminiTestLabel) { testGemini() }
                .font(ArbiterFont.mono(10))
                .foregroundColor(testStateColor(geminiTest))
                .disabled(geminiTest == .testing || geminiPassword.isEmpty)

            Picker("MODEL", selection: $geminiModel) {
                ForEach(ModelCatalog.gemini) { Text($0.label).tag($0.id) }
            }
            .font(ArbiterFont.mono(10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: — System prompt section

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYSTEM PROMPT OVERRIDE")
                .font(ArbiterFont.mono(10))
                .foregroundColor(.arbiterCyan.opacity(0.75))
            TextEditor(text: $systemPromptOverride)
                .font(ArbiterFont.mono(11))
                .frame(minHeight: 100)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.arbiterBorder, lineWidth: 0.5)
                )
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: — Chrome

    private var header: some View {
        HStack {
            Text("SYSTEM CONFIGURATION")
                .font(ArbiterFont.mono(14).bold())
                .foregroundColor(.arbiterCyan)
            Spacer()
            Button("✕") { dismiss() }.buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.black.opacity(0.4))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("ENGAGE CHANGES") { saveAndDismiss() }
                .font(ArbiterFont.mono(11).bold())
                .foregroundColor(.arbiterCyan)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.arbiterCyan.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.arbiterCyan, lineWidth: 0.5)
                )
        }
        .padding(16)
        .background(Color.black.opacity(0.3))
    }

    // MARK: — Test helpers

    private var claudeTestLabel: String { testLabel(claudeTest) }
    private var geminiTestLabel: String { testLabel(geminiTest) }

    private func testLabel(_ state: TestState) -> String {
        switch state {
        case .idle:    return "TEST CONNECTION"
        case .testing: return "TESTING…"
        case .ok:      return "CONNECTION OK ✓"
        case .fail:    return "CONNECTION FAIL ✗"
        }
    }

    private func testStateColor(_ state: TestState) -> Color {
        switch state {
        case .ok:   return .green
        case .fail: return .red
        default:    return .arbiterCyan.opacity(0.8)
        }
    }

    // MARK: — Async ping implementations

    private func testClaude() {
        claudeTest = .testing
        let key   = claudePassword
        let model = claudeModel.isEmpty ? ModelCatalog.claude.first!.id : claudeModel
        Task {
            do {
                _ = try await ClaudeClient.call(
                    messages: [["role": "user", "content": "Reply with the single word: OK"]],
                    system:   nil,
                    apiKey:   key,
                    model:    model
                )
                await MainActor.run {
                    claudeTest             = .ok
                    settings.claudeConnected = true
                }
            } catch {
                await MainActor.run {
                    claudeTest             = .fail
                    settings.claudeConnected = false
                }
            }
        }
    }

    private func testGemini() {
        geminiTest = .testing
        let key   = geminiPassword
        let model = geminiModel.isEmpty ? ModelCatalog.gemini.first!.id : geminiModel
        Task {
            do {
                try await GeminiClient.ping(apiKey: key, model: model)
                await MainActor.run {
                    geminiTest             = .ok
                    settings.geminiConnected = true
                }
            } catch {
                await MainActor.run {
                    geminiTest             = .fail
                    settings.geminiConnected = false
                }
            }
        }
    }

    // MARK: — Save

    private func saveAndDismiss() {
        settings.claudeEmail          = claudeEmail
        settings.claudePassword       = claudePassword
        settings.geminiEmail          = geminiEmail
        settings.geminiPassword       = geminiPassword
        settings.claudeModel          = claudeModel
        settings.geminiModel          = geminiModel
        settings.systemPromptOverride = systemPromptOverride
        dismiss()
    }
}
