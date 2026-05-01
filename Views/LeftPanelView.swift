import SwiftUI

struct LeftPanelView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var engine:   OrchestrationEngine
    @EnvironmentObject var fae:      FAEManager
    @Binding var prompt:       String
    @Binding var mode:         PipelineMode
    @Binding var iterations:   Int
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Warning: API Status ────────────────────────────────
                    if settings.claudePassword.isEmpty || settings.geminiPassword.isEmpty {
                        warningBanner
                    }

                    // ── Mode Selection ─────────────────────────────────────
                    ArbiterModeSelector(selectedMode: $mode)

                    if mode == .iterative {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ITERATION DEPTH: \(iterations)X")
                                .font(ArbiterFont.mono(10))
                                .foregroundColor(.arbiterCyan)
                            Slider(
                                value: Binding(get: { Double(iterations) }, set: { iterations = Int($0) }),
                                in: 1...5, step: 1
                            )
                            .tint(.arbiterCyan)
                        }
                        .padding(12)
                        .modifier(ArbiterPanel())
                    }

                    // ── Prompt Input ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        ArbiterDivider(label: "Command Input")
                        TextEditor(text: $prompt)
                            .font(ArbiterFont.mono(12))
                            .foregroundColor(.arbiterText)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 120, maxHeight: 200)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.arbiterBorder, lineWidth: 0.5)
                            )
                    }

                    // ── Actions ────────────────────────────────────────────
                    VStack(spacing: 12) {
                        ArbiterButton(
                            title:    "ANALYZE PROMPT",
                            disabled: prompt.isEmpty || engine.phase == .running,
                            loading:  engine.phase == .validating
                        ) {
                            engine.validate(prompt: prompt, settings: settings)
                        }

                        if let val = engine.validation {
                            ValidationResultView(
                                result:    val,
                                prompt:    $prompt,
                                onExecute: {
                                    engine.execute(
                                        prompt:     prompt,
                                        mode:       mode,
                                        iterations: iterations,
                                        settings:   settings,
                                        faeContext:  fae.contextBlock
                                    )
                                },
                                canExecute: true
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color.arbiterBg)
    }

    private var warningBanner: some View {
        HStack {
            Text("⚠ Login Credentials Missing")
                .font(ArbiterFont.mono(10))
                .foregroundColor(.orange)
            Spacer()
            Button("FIX") { showSettings = true }.buttonStyle(.link)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.75))
                .frame(width: 2)
                .padding(.vertical, 4)
                .padding(.leading, 4)
        }
        .shadow(color: .orange.opacity(0.15), radius: 10, x: 0, y: 3)
    }
}
