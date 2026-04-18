import SwiftUI

struct PipelinePreviewView: View {
    let mode:       PipelineMode
    let iterations: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                if mode == .sequential {
                    sequentialFlow
                } else {
                    iterativeFlow
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
        }
    }

    // MARK: — Sequential Logic Flow

    private var sequentialFlow: some View {
        HStack(alignment: .center, spacing: 8) {
            nodeBox(label: "CLAUDE", sub: "INITIAL DRAFT",   color: .arbiterCyan)
            arrow
            nodeBox(label: "GEMINI", sub: "CRITICAL REVIEW", color: .white.opacity(0.75))
            arrow
            nodeBox(label: "CLAUDE", sub: "FINAL SYNTHESIS", color: .arbiterCyan)
        }
    }

    // MARK: — Iterative Logic Flow

    private var iterativeFlow: some View {
        HStack(alignment: .center, spacing: 8) {
            nodeBox(label: "CLAUDE", sub: "INITIAL DRAFT", color: .arbiterCyan)
            ForEach(0..<iterations, id: \.self) { i in
                HStack(alignment: .center, spacing: 6) {
                    arrow
                    loopBox(index: i + 1)
                }
            }
        }
    }

    private func loopBox(index: Int) -> some View {
        VStack(spacing: 6) {
            Text("CYCLE \(index)")
                .font(ArbiterFont.mono(8).bold())
                .foregroundColor(.white.opacity(0.5))
                .tracking(2)
            HStack(alignment: .center, spacing: 6) {
                nodeBox(label: "GEMINI", sub: "CRITIQUE",  color: .white.opacity(0.75), small: true)
                arrow
                nodeBox(label: "CLAUDE", sub: "REVISION",  color: .arbiterCyan,        small: true)
            }
            .padding(8)
            .background(Color.arbiterSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        Color.arbiterBorder,
                        style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
                    )
            )
        }
    }

    private func nodeBox(label: String, sub: String, color: Color, small: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(ArbiterFont.mono(small ? 9 : 10).bold())
                .foregroundColor(color)
                .tracking(1.5)
            Text(sub)
                .font(ArbiterFont.mono(small ? 7 : 8))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, small ? 10 : 14)
        .padding(.vertical,   small ? 6  : 8)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var arrow: some View {
        Text("→")
            .font(ArbiterFont.mono(12))
            .foregroundColor(.white.opacity(0.4))
    }
}
