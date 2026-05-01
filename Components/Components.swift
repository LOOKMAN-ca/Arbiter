import SwiftUI
import Speech

// MARK: — ArbiterButton
// Generic CTA button used across the whole interface.
// Handles idle / loading / disabled states consistently.

struct ArbiterButton: View {
    let title:    String
    var color:    Color  = .arbiterCyan
    var disabled: Bool   = false
    var loading:  Bool   = false
    let action:   () -> Void

    private var isInert: Bool { disabled || loading }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(color)
                }
                Text(title)
                    .font(ArbiterFont.mono(11).bold())
                    .tracking(1.5)
                    .foregroundColor(isInert ? color.opacity(0.45) : color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(isInert ? 0.02 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(isInert ? 0.01 : 0.06), Color.clear],
                    startPoint: .top, endPoint: .init(x: 0.5, y: 0.7)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isInert ? 0.15 : 0.5), lineWidth: 0.5)
            )
            .shadow(color: isInert ? .clear : color.opacity(0.12), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isInert)
    }
}

// MARK: — ArbiterDivider
// Labelled horizontal rule used as a section separator.

struct ArbiterDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.arbiterBorder)
                .frame(height: 0.5)
            Text(label.uppercased())
                .font(ArbiterFont.mono(8))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.5)
                .fixedSize()
            Rectangle()
                .fill(Color.arbiterBorder)
                .frame(height: 0.5)
        }
    }
}

// MARK: — ArbiterModeSelector
// Two-button toggle for Sequential / Iterative pipeline mode.

struct ArbiterModeSelector: View {
    @Binding var selectedMode: PipelineMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArbiterDivider(label: "Pipeline Mode")
            HStack(spacing: 8) {
                ForEach(PipelineMode.allCases) { mode in
                    modeCell(mode)
                }
            }
        }
    }

    private func modeCell(_ mode: PipelineMode) -> some View {
        let active = selectedMode == mode
        return Button { selectedMode = mode } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.displayName)
                    .font(ArbiterFont.mono(10).bold())
                    .foregroundColor(active ? .arbiterCyan : .white.opacity(0.5))
                    .tracking(1.5)
                Text(mode.description)
                    .font(ArbiterFont.mono(8))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.arbiterCyan.opacity(0.06) : Color.black.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(active ? 0.05 : 0.02), Color.clear],
                    startPoint: .top, endPoint: .init(x: 0.5, y: 0.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        active ? Color.arbiterCyan.opacity(0.45) : Color.arbiterBorder,
                        lineWidth: 0.5
                    )
            )
            .shadow(color: active ? Color.arbiterCyan.opacity(0.1) : .black.opacity(0.2), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: — StepCardView
// Renders a single pipeline step — header badge + streaming content area.

struct StepCardView: View {
    let step: PipelineStep

    private var modelColor: Color {
        step.model == .claude ? .arbiterCyan : Color.white.opacity(0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            contentArea
        }
        .background(.ultraThinMaterial)
        .background(Color.arbiterSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [
                            modelColor.opacity(step.status == .running ? 0.65 : 0.2),
                            modelColor.opacity(step.status == .running ? 0.15 : 0.04)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: step.status == .running ? modelColor.opacity(0.22) : .clear, radius: 26, x: 0, y: 0)
        .shadow(color: .black.opacity(0.55), radius: 16, x: 0, y: 6)
    }

    // ── Header ────────────────────────────────────────────────────────────
    private var header: some View {
        HStack(spacing: 8) {
            statusDot
            Text(step.model.displayName)
                .font(ArbiterFont.mono(9).bold())
                .foregroundColor(modelColor)
                .tracking(2)
            Text("//")
                .font(ArbiterFont.mono(9))
                .foregroundColor(.white.opacity(0.4))
            Text(step.label)
                .font(ArbiterFont.mono(9))
                .foregroundColor(.white.opacity(0.65))
                .tracking(1)
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [modelColor.opacity(step.status == .running ? 0.16 : 0.1), modelColor.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var statusDot: some View {
        ZStack {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .shadow(color: dotColor.opacity(0.8), radius: 4, x: 0, y: 0)
            if step.status == .running {
                Circle()
                    .stroke(modelColor.opacity(0.35), lineWidth: 1)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var dotColor: Color {
        switch step.status {
        case .running: return modelColor
        case .done:    return .green
        case .failed:  return .red
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch step.status {
        case .running:
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.45).tint(modelColor)
                Text("STREAMING")
                    .font(ArbiterFont.mono(8))
                    .foregroundColor(modelColor.opacity(0.85))
            }
        case .done:
            Text("\(step.tokenCount) tok")
                .font(ArbiterFont.mono(8))
                .foregroundColor(.white.opacity(0.45))
        case .failed:
            Text("FAILED")
                .font(ArbiterFont.mono(8))
                .foregroundColor(.red.opacity(0.9))
        }
    }

    // ── Content ───────────────────────────────────────────────────────────
    @ViewBuilder
    private var contentArea: some View {
        if !step.content.isEmpty {
            Text(step.content)
                .font(ArbiterFont.mono(11))
                .foregroundColor(.arbiterText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else if step.status == .running {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(modelColor.opacity(0.35))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(12)
        }
    }
}

// MARK: — VocalInterfaceHUD
// Bottom-pinned vocal control strip: locale selector + mic toggle + live transcript.

struct VocalInterfaceHUD: View {
    @EnvironmentObject var speech:   SpeechManager
    @EnvironmentObject var feedback: FeedbackManager
    @Binding var selectedLocale: String

    private let locales: [(id: String, label: String)] = [
        ("en-US", "EN-US"),
        ("it-IT", "IT-IT")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArbiterDivider(label: "Vocal Interface")

            HStack(spacing: 10) {
                localeSelector
                Spacer()
                micButton
            }

            if !speech.transcript.isEmpty {
                transcriptStrip
            }
        }
    }

    // ── Locale pills ──────────────────────────────────────────────────────
    private var localeSelector: some View {
        HStack(spacing: 0) {
            ForEach(locales, id: \.id) { locale in
                Button { selectedLocale = locale.id } label: {
                    Text(locale.label)
                        .font(ArbiterFont.mono(8).bold())
                        .tracking(1)
                        .foregroundColor(selectedLocale == locale.id ? .arbiterCyan : .white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            selectedLocale == locale.id
                                ? Color.arbiterCyan.opacity(0.08)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)

                if locale.id != locales.last?.id {
                    Divider()
                        .background(Color.arbiterBorder)
                        .frame(height: 12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.arbiterBorder, lineWidth: 0.5)
        )
    }

    // ── Mic button ────────────────────────────────────────────────────────
    private var micButton: some View {
        let active = speech.isRecording
        let accent: Color = active ? .red : .arbiterCyan

        return Button { speech.toggleRecording(locale: selectedLocale) } label: {
            HStack(spacing: 6) {
                Image(systemName: active ? "mic.fill" : "mic")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(accent.opacity(0.8))
                Text(active ? "LISTENING" : "VOCAL INPUT")
                    .font(ArbiterFont.mono(9).bold())
                    .tracking(1)
                    .foregroundColor(accent.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.clear],
                    startPoint: .top, endPoint: .init(x: 0.5, y: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: active ? accent.opacity(0.3) : .clear, radius: 10, x: 0, y: 0)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // ── Transcript strip ──────────────────────────────────────────────────
    private var transcriptStrip: some View {
        Text(speech.transcript)
            .font(ArbiterFont.mono(9))
            .foregroundColor(.white.opacity(0.55))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.arbiterBorder, lineWidth: 0.5)
            )
    }
}
