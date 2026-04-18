import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject var engine: OrchestrationEngine
    let mode:       PipelineMode
    let iterations: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if engine.steps.isEmpty {
                        emptyStateHUD
                    } else {
                        ForEach(engine.steps) { step in
                            StepCardView(step: step)
                                .id(step.id)
                        }
                    }

                    if !engine.finalOutput.isEmpty {
                        finalOutputSection
                            .id("final")
                    }

                    if let errMsg = engine.errorMessage {
                        errorBanner(errMsg)
                    }
                }
                .padding(20)
            }
            // macOS 14 two-argument onChange — auto-scroll when a new step appears
            .onChange(of: engine.steps.count) { _, _ in
                if let last = engine.steps.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            // Scroll to final output when the pipeline completes
            .onChange(of: engine.phase) { _, newPhase in
                if newPhase == .done {
                    withAnimation { proxy.scrollTo("final", anchor: .bottom) }
                }
            }
        }
        .background(Color.arbiterBg)
    }

    // MARK: — Empty state

    private var emptyStateHUD: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 50)
            Text("Awaiting Pipeline Init")
                .font(ArbiterFont.mono(12))
                .foregroundColor(.arbiterCyan.opacity(0.5))
                .tracking(2)
            ArbiterDivider(label: "Pipeline Logic Preview")
            PipelinePreviewView(mode: mode, iterations: iterations)
        }
    }

    // MARK: — Final output panel

    private var finalOutputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArbiterDivider(label: "Final Synthesized Data")
            Text(engine.finalOutput)
                .font(ArbiterFont.mono(13))
                .foregroundColor(.white)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .modifier(ArbiterPanel())
        }
    }

    // MARK: — Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
                .font(.system(size: 11))
            Text(message)
                .font(ArbiterFont.mono(10))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
        )
    }
}
