import SwiftUI

struct ValidationResultView: View {
    let result:    ValidationResult
    @Binding var prompt: String
    let onExecute: () -> Void
    let canExecute: Bool

    var verdictColor: Color {
        switch result.verdict {
        case .green: return .green
        case .amber: return .orange
        case .red:   return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Verdict banner ────────────────────────────────────────────
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Circle().fill(result.verdict == .red   ? Color.red    : Color.white.opacity(0.1)).frame(width: 8, height: 8)
                    Circle().fill(result.verdict == .amber ? Color.orange : Color.white.opacity(0.1)).frame(width: 8, height: 8)
                    Circle().fill(result.verdict == .green ? Color.green  : Color.white.opacity(0.1)).frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.verdict.label)
                        .font(ArbiterFont.mono(11).bold())
                        .foregroundColor(verdictColor)
                    Text(result.summary)
                        .font(ArbiterFont.mono(10))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(verdictColor.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.clear],
                    startPoint: .top, endPoint: .init(x: 0.5, y: 0.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(verdictColor.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: verdictColor.opacity(0.15), radius: 8, x: 0, y: 3)

            // ── Score grid ────────────────────────────────────────────────
            scoreGrid

            // ── Suggestions ───────────────────────────────────────────────
            if !result.suggestions.isEmpty {
                suggestionsPanel
            }

            // ── Refined prompt ────────────────────────────────────────────
            if let refined = result.refinedPrompt, refined != prompt {
                refinedPromptPanel(refined)
            }

            // ── Execute CTA ───────────────────────────────────────────────
            ArbiterButton(
                title:    "ENGAGE PIPELINE",
                color:    verdictColor,
                disabled: !canExecute,
                action:   onExecute
            )
        }
        .padding(12)
        .modifier(ArbiterPanel())
    }

    // MARK: — Score grid

    private var scoreGrid: some View {
        HStack(spacing: 8) {
            scoreCell(label: "SPEC",   value: result.specificity,   good: true)
            scoreCell(label: "VERIF",  value: result.verifiability,  good: true)
            scoreCell(label: "AMBIG",  value: result.ambiguity,      good: false)
            scoreCell(label: "SCOPE",  value: result.scope,          good: false)
        }
    }

    private func scoreCell(label: String, value: Int, good: Bool) -> some View {
        // "good" means high score is positive; "bad" means high score is negative
        let accent: Color = good
            ? (value >= 3 ? .green : .red)
            : (value <= 2 ? .green : .red)

        return VStack(spacing: 3) {
            Text("\(value)")
                .font(ArbiterFont.mono(14).bold())
                .foregroundColor(accent)
            Text(label)
                .font(ArbiterFont.mono(7))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(accent.opacity(0.05))
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
                .stroke(accent.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: accent.opacity(0.18), radius: 6, x: 0, y: 2)
    }

    // MARK: — Suggestions

    private var suggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IMPROVEMENT VECTORS")
                .font(ArbiterFont.mono(9))
                .foregroundColor(.arbiterCyan.opacity(0.7))
            ForEach(result.suggestions, id: \.self) { tip in
                HStack(alignment: .top, spacing: 6) {
                    Text("›")
                        .font(ArbiterFont.mono(10))
                        .foregroundColor(.arbiterCyan.opacity(0.6))
                    Text(tip)
                        .font(ArbiterFont.mono(10))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.02))
    }

    // MARK: — Refined prompt

    private func refinedPromptPanel(_ refined: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REFINED PROMPT SUGGESTION")
                .font(ArbiterFont.mono(9))
                .foregroundColor(.arbiterCyan.opacity(0.75))
            Text(refined)
                .font(ArbiterFont.mono(10))
                .italic()
                .foregroundColor(.white.opacity(0.8))
            Button("ADOPT REFINEMENT") { prompt = refined }
                .font(ArbiterFont.mono(10))
                .foregroundColor(.arbiterCyan)
                .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
    }
}
