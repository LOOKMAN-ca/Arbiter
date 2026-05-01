import SwiftUI

struct ContentView: View {
    // System Core
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var engine:   OrchestrationEngine
    @EnvironmentObject var speech:   SpeechManager
    @EnvironmentObject var feedback: FeedbackManager
    @EnvironmentObject var fae:      FAEManager

    // Interface State
    @State private var prompt:          String = ""
    @State private var mode:            PipelineMode = .sequential
    @State private var iterations:      Int = 2
    @State private var showSettings     = false
    @State private var showFAE          = false
    @State private var selectedLocale   = "en-US"

    var body: some View {
        VStack(spacing: 0) {
            arbiterTopBar

            Divider().background(Color.arbiterBorder)

            HSplitView {
                // Control Column
                VStack(spacing: 0) {
                    LeftPanelView(
                        prompt:       $prompt,
                        mode:         $mode,
                        iterations:   $iterations,
                        showSettings: $showSettings
                    )

                    Spacer(minLength: 0)

                    VocalInterfaceHUD(selectedLocale: $selectedLocale)
                        .padding(12)
                        .background(Color.black.opacity(0.25))
                        .overlay(
                            Rectangle()
                                .fill(Color.arbiterBorder)
                                .frame(height: 0.5),
                            alignment: .top
                        )
                }
                .frame(minWidth: 320, idealWidth: 350, maxWidth: 400)
                .background(Color.black.opacity(0.2))

                // Output Column
                HStack(spacing: 0) {
                    RightPanelView(mode: mode, iterations: iterations)
                        .frame(minWidth: 400)

                    if showFAE {
                        Divider().background(Color.arbiterBorder)
                        FAEPanelView()
                            .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
                    }
                }
            }
        }
        .background(Color.arbiterBg)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(engine)
                .frame(minWidth: 600, minHeight: 420)
        }

        // --- FocusedValue: expose actions to menu commands ---
        .focusedValue(\.arbiterActions, ArbiterActions(
            execute: {
                guard engine.phase != .running else { return }
                engine.execute(prompt: prompt, mode: mode, iterations: iterations, settings: settings, faeContext: fae.contextBlock)
            },
            validate: {
                guard !prompt.isEmpty, engine.phase != .running else { return }
                engine.validate(prompt: prompt, settings: settings)
            },
            abort: {
                engine.abort()
            }
        ))

        // --- System Handlers ---

        // Vocal Command Listener
        .onChange(of: speech.lastDetectedCommand) { _, newCommand in
            guard newCommand != .none else { return }
            feedback.acknowledge(command: newCommand, locale: selectedLocale)
            switch newCommand {
            case .execute:
                engine.execute(
                    prompt:     speech.transcript,
                    mode:       mode,
                    iterations: iterations,
                    settings:   settings,
                    faeContext:  fae.contextBlock
                )
            case .abort:
                engine.abort()
            case .validate:
                engine.validate(prompt: speech.transcript, settings: settings)
            case .none:
                break
            }
            speech.lastDetectedCommand = .none
        }

        // Sync vocal transcript to text editor while recording
        .onChange(of: speech.transcript) { _, newText in
            if speech.isRecording { self.prompt = newText }
        }
    }

    // MARK: — Arbiter Top Bar

    private var arbiterTopBar: some View {
        HStack(spacing: 16) {
            // Branding
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.arbiterCyan.opacity(0.08))
                        .frame(width: 30, height: 30)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.arbiterCyan.opacity(0.35), lineWidth: 1)
                        .frame(width: 30, height: 30)
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.arbiterCyan)
                }
                .glassEffect(.regular.tint(.cyan), in: .rect(cornerRadius: 8))
                Text("ARBITER")
                    .font(ArbiterFont.mono(15).bold())
                    .foregroundColor(.arbiterCyan)
                    .tracking(5)
            }

            Spacer()

            // Status strip
            HStack(spacing: 20) {
                statusIndicator(label: "CLAUDE", active: !settings.claudePassword.isEmpty)
                statusIndicator(label: "GEMINI", active: !settings.geminiPassword.isEmpty)

                Divider().frame(height: 14).background(Color.arbiterBorder)

                Text(engine.phase.displayLabel)
                    .font(ArbiterFont.mono(10).bold())
                    .foregroundColor(phaseColor)

                Button { showFAE.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe.desk")
                            .foregroundColor(showFAE ? .arbiterCyan : .arbiterCyan.opacity(0.5))
                        Text("FAE")
                            .font(ArbiterFont.mono(8).bold())
                            .foregroundColor(showFAE ? .arbiterCyan : .arbiterCyan.opacity(0.5))
                        if fae.hasAttachedContext {
                            Text("\(fae.attachedResults.count)")
                                .font(ArbiterFont.mono(7).bold())
                                .foregroundColor(.arbiterCyan)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.arbiterCyan.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.arbiterCyan.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.3))
    }

    private func statusIndicator(label: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Color.arbiterCyan : Color.white.opacity(0.1))
                .frame(width: 5, height: 5)
            Text(label)
                .font(ArbiterFont.mono(9))
                .foregroundColor(active ? .white : .white.opacity(0.5))
        }
    }

    private var phaseColor: Color {
        switch engine.phase {
        case .running:   return .arbiterCyan
        case .done:      return .green
        case .aborted:   return .red
        case .error:     return .red
        case .validated: return .orange
        default:         return .white.opacity(0.6)
        }
    }
}
