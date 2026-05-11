import SwiftUI

// MARK: - FAE Verification View
// Lets the developer kick off a full verification run, watch per-portal progress,
// and review the final quality-gate summary.

struct FAEVerificationView: View {
    @EnvironmentObject var registry:     FAEActiveRegistry
    @EnvironmentObject var verification: FAEVerificationManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.arbiterBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    if verification.isRunning { progressSection }
                    if let passed = verification.qualityGatePassed { gateCard(passed: passed) }
                    if !verification.records.isEmpty { resultsSection }
                    inactiveSection
                }
                .padding(16)
            }
        }
        .background(Color.arbiterBg)
        .onChange(of: verification.isRunning) { _, running in
            // Refresh active registry when a run completes.
            if !running && !verification.updatedEntries.isEmpty {
                registry.reloadAfterVerification(updatedEntries: verification.updatedEntries)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.arbiterCyan)
            Text("REGISTRY VERIFICATION")
                .font(ArbiterFont.mono(11).bold())
                .foregroundColor(.arbiterCyan)
                .tracking(2)
            Spacer()

            if verification.isRunning {
                Button("CANCEL") { verification.cancel() }
                    .font(ArbiterFont.mono(9))
                    .foregroundColor(.red.opacity(0.8))
                    .buttonStyle(.plain)
            } else {
                Button("VERIFY NOW") {
                    verification.startVerification(entries: registry.rawEntries)
                }
                .font(ArbiterFont.mono(9).bold())
                .foregroundColor(.arbiterCyan)
                .buttonStyle(.plain)
                .disabled(registry.rawEntries.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.black.opacity(0.2)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                stat(value: "\(registry.rawEntries.count)",  label: "TOTAL")
                stat(value: "\(registry.activeCount)",       label: "ACTIVE", color: .green)
                stat(value: "\(registry.inactiveCount)",     label: "INACTIVE", color: .white.opacity(0.4))
            }

            if registry.needsVerification {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                    Text("Verification recommended — registry may be stale")
                        .font(ArbiterFont.mono(9))
                        .foregroundColor(.orange.opacity(0.9))
                }
            }

            if let error = registry.loadError {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                    Text(error)
                        .font(ArbiterFont.mono(9))
                        .foregroundColor(.red.opacity(0.9))
                        .lineLimit(2)
                }
            }

            if let url = verification.reportURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 8))
                        Text("SHOW REPORT")
                            .font(ArbiterFont.mono(8))
                    }
                    .foregroundColor(.arbiterCyan.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .modifier(ArbiterPanel())
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView(value: verification.progressFraction)
                    .tint(.arbiterCyan)
                Text("\(verification.completedCount)/\(verification.totalCount)")
                    .font(ArbiterFont.mono(9))
                    .foregroundColor(.arbiterCyan.opacity(0.8))
            }

            let live     = verification.records.filter { if case .live(_, true, _) = $0.outcome { return true }; return false }.count
            let degraded = verification.records.filter { if case .live(_, false, _) = $0.outcome { return true }
                if case .degraded = $0.outcome { return true }; return false }.count
            let dead     = verification.records.filter { if case .dead = $0.outcome { return true }
                if case .requiresAuth = $0.outcome { return true }; return false }.count

            HStack(spacing: 12) {
                miniStat(value: "\(live)",     label: "LIVE",    color: .green)
                miniStat(value: "\(degraded)", label: "DEGRADED", color: .yellow)
                miniStat(value: "\(dead)",     label: "FAILED",   color: .red)
            }
        }
        .padding(12)
        .modifier(ArbiterPanel())
    }

    // MARK: - Quality Gate Card

    private func gateCard(passed: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: passed ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 14))
                .foregroundColor(passed ? .green : .red)

            VStack(alignment: .leading, spacing: 3) {
                Text(passed ? "QUALITY GATE PASSED" : "QUALITY GATE FAILED")
                    .font(ArbiterFont.mono(10).bold())
                    .foregroundColor(passed ? .green : .red)
                let threshold = max(FAEVerifier.qualityGate, verification.totalCount * 40 / 100)
                Text("\(verification.liveCount) / \(threshold) live — \(verification.totalCount) probed (\(registry.rawEntries.count - verification.totalCount) unverified URLs skipped)")
                    .font(ArbiterFont.mono(9))
                    .foregroundColor(.white.opacity(0.6))

                if !passed {
                    Text("Check individual portal errors in the list below. Unverified-URL entries are skipped automatically.")
                        .font(ArbiterFont.mono(8))
                        .foregroundColor(.red.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(passed ? Color.green.opacity(0.05) : Color.red.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(passed ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArbiterDivider(label: "Probe Results (\(verification.records.count))")
            // Show most recent 80 to avoid overwhelming the scroll view.
            ForEach(verification.records.suffix(80)) { record in
                PortalStatusRow(record: record)
            }
        }
    }

    // MARK: - Inactive Entries Browser

    private var inactiveSection: some View {
        Group {
            if !registry.inactiveEntries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ArbiterDivider(label: "Needs Review (\(registry.inactiveEntries.count))")
                    Text("Entries below are loaded but excluded from active queries.")
                        .font(ArbiterFont.mono(8))
                        .foregroundColor(.white.opacity(0.35))
                    ForEach(registry.inactiveEntries) { entry in
                        PortalEntryRow(entry: entry)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func stat(value: String, label: String, color: Color = .arbiterCyan) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(ArbiterFont.mono(18).bold())
                .foregroundColor(color)
            Text(label)
                .font(ArbiterFont.mono(8))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(value) \(label)")
                .font(ArbiterFont.mono(9))
                .foregroundColor(color.opacity(0.8))
        }
    }
}

// MARK: - Preview

#Preview {
    FAEVerificationView()
        .environmentObject(FAEActiveRegistry())
        .environmentObject(FAEVerificationManager())
        .frame(width: 480, height: 700)
        .preferredColorScheme(.dark)
}
