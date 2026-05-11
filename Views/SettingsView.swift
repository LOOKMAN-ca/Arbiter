import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    @State private var claudeApiKey          = ""
    @State private var geminiApiKey          = ""
    @State private var claudeModel           = ""
    @State private var geminiModel           = ""
    @State private var systemPromptOverride  = ""

    @State private var claudeTest: TestState = .idle
    @State private var geminiTest: TestState = .idle

    @State private var showClaudeAuth = false
    @State private var showGeminiAuth = false

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
            claudeApiKey         = settings.claudeApiKey
            geminiApiKey         = settings.geminiApiKey
            claudeModel          = settings.claudeModel
            geminiModel          = settings.geminiModel
            systemPromptOverride = settings.systemPromptOverride
        }
        .sheet(isPresented: $showClaudeAuth) {
            WebAuthSheet(
                title:    "Sign in — Anthropic Console",
                loginURL: URL(string: "https://console.anthropic.com/login")!,
                apiKey:   $claudeApiKey
            )
        }
        .sheet(isPresented: $showGeminiAuth) {
            WebAuthSheet(
                title:    "Sign in — Google AI Studio",
                loginURL: URL(string: "https://aistudio.google.com")!,
                apiKey:   $geminiApiKey
            )
        }
    }

    // MARK: — Claude column

    private var claudeColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("ANTHROPIC CLAUDE")
                    .font(ArbiterFont.mono(10).bold())
                    .foregroundColor(.arbiterCyan)
                Spacer()
                connectionBadge(claudeTest)
            }

            // Sign-in card
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to the Anthropic Console with your email and password to access your API keys.")
                    .font(ArbiterFont.mono(9))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    claudeTest = .idle
                    showClaudeAuth = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 11))
                        Text("SIGN IN TO ANTHROPIC CONSOLE")
                            .font(ArbiterFont.mono(9).bold())
                    }
                    .foregroundColor(.arbiterCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.arbiterCyan.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.arbiterCyan.opacity(0.35), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.arbiterCyan.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.arbiterCyan.opacity(0.15), lineWidth: 0.5)
            )

            // Manual key entry
            VStack(alignment: .leading, spacing: 5) {
                Text("API KEY")
                    .font(ArbiterFont.mono(8))
                    .foregroundColor(.white.opacity(0.35))
                SecureField("Paste key here", text: $claudeApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(ArbiterFont.mono(11))
                    .onChange(of: claudeApiKey) { _, _ in claudeTest = .idle }
            }

            Button(claudeTestLabel) { testClaude() }
                .font(ArbiterFont.mono(9))
                .foregroundColor(testStateColor(claudeTest))
                .disabled(claudeTest == .testing || claudeApiKey.isEmpty)

            Picker("MODEL", selection: $claudeModel) {
                ForEach(ModelCatalog.claude) { Text($0.label).tag($0.id) }
            }
            .font(ArbiterFont.mono(10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: — Gemini column

    private var geminiColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("GOOGLE GEMINI")
                    .font(ArbiterFont.mono(10).bold())
                    .foregroundColor(.arbiterCyan)
                Spacer()
                connectionBadge(geminiTest)
            }

            // Sign-in card
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to Google AI Studio with your Google account to access your API keys.")
                    .font(ArbiterFont.mono(9))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    geminiTest = .idle
                    showGeminiAuth = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 11))
                        Text("SIGN IN TO GOOGLE AI STUDIO")
                            .font(ArbiterFont.mono(9).bold())
                    }
                    .foregroundColor(.arbiterCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.arbiterCyan.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.arbiterCyan.opacity(0.35), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.arbiterCyan.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.arbiterCyan.opacity(0.15), lineWidth: 0.5)
            )

            // Manual key entry
            VStack(alignment: .leading, spacing: 5) {
                Text("API KEY")
                    .font(ArbiterFont.mono(8))
                    .foregroundColor(.white.opacity(0.35))
                SecureField("Paste key here", text: $geminiApiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(ArbiterFont.mono(11))
                    .onChange(of: geminiApiKey) { _, _ in geminiTest = .idle }
            }

            Button(geminiTestLabel) { testGemini() }
                .font(ArbiterFont.mono(9))
                .foregroundColor(testStateColor(geminiTest))
                .disabled(geminiTest == .testing || geminiApiKey.isEmpty)

            Picker("MODEL", selection: $geminiModel) {
                ForEach(ModelCatalog.gemini) { Text($0.label).tag($0.id) }
            }
            .font(ArbiterFont.mono(10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: — Connection badge

    @ViewBuilder
    private func connectionBadge(_ state: TestState) -> some View {
        switch state {
        case .ok:
            Label("CONNECTED", systemImage: "checkmark.circle.fill")
                .font(ArbiterFont.mono(8).bold())
                .foregroundColor(.green)
        case .fail:
            Label("FAILED", systemImage: "xmark.circle.fill")
                .font(ArbiterFont.mono(8).bold())
                .foregroundColor(.red)
        case .testing:
            Label("VERIFYING", systemImage: "arrow.triangle.2.circlepath")
                .font(ArbiterFont.mono(8))
                .foregroundColor(.arbiterCyan.opacity(0.7))
        case .idle:
            EmptyView()
        }
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
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.black.opacity(0.3)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .fill(Color.arbiterBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
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
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        startPoint: .top, endPoint: .init(x: 0.5, y: 0.7)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.arbiterCyan.opacity(0.6), lineWidth: 0.5)
                )
                .shadow(color: Color.arbiterCyan.opacity(0.15), radius: 8, x: 0, y: 3)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.black.opacity(0.4)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .fill(Color.arbiterBorder)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: — Test helpers

    private var claudeTestLabel: String { testLabel(claudeTest) }
    private var geminiTestLabel: String { testLabel(geminiTest) }

    private func testLabel(_ state: TestState) -> String {
        switch state {
        case .idle:    return "VERIFY KEY"
        case .testing: return "VERIFYING…"
        case .ok:      return "KEY VERIFIED ✓"
        case .fail:    return "VERIFICATION FAILED ✗"
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
        let key   = claudeApiKey
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
                    claudeTest               = .ok
                    settings.claudeConnected = true
                }
            } catch {
                await MainActor.run {
                    claudeTest               = .fail
                    settings.claudeConnected = false
                }
            }
        }
    }

    private func testGemini() {
        geminiTest = .testing
        let key   = geminiApiKey
        let model = geminiModel.isEmpty ? ModelCatalog.gemini.first!.id : geminiModel
        Task {
            do {
                try await GeminiClient.ping(apiKey: key, model: model)
                await MainActor.run {
                    geminiTest               = .ok
                    settings.geminiConnected = true
                }
            } catch {
                await MainActor.run {
                    geminiTest               = .fail
                    settings.geminiConnected = false
                }
            }
        }
    }

    // MARK: — Save

    private func saveAndDismiss() {
        settings.claudeApiKey        = claudeApiKey
        settings.geminiApiKey        = geminiApiKey
        settings.claudeModel         = claudeModel
        settings.geminiModel         = geminiModel
        settings.systemPromptOverride = systemPromptOverride
        dismiss()
    }
}
