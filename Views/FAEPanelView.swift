import SwiftUI

// MARK: - FAE Panel View

struct FAEPanelView: View {
    @EnvironmentObject var faeManager:   FAEManager
    @EnvironmentObject var registry:     FAEActiveRegistry
    @EnvironmentObject var verification: FAEVerificationManager
    @State private var searchText        = ""
    @State private var showVerification  = false

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().background(Color.arbiterBorder)
            if showVerification {
                FAEVerificationView()
                    .environmentObject(registry)
                    .environmentObject(verification)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        searchSection
                        filterBar
                        if faeManager.isSearching { progressSection }
                        if !faeManager.filteredResults.isEmpty { resultsSection }
                        if !faeManager.failedPortals.isEmpty && !faeManager.isSearching { failedSection }
                        if !faeManager.attachedResults.isEmpty { attachedSection }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.arbiterBg)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.desk")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.arbiterCyan)
            Text("FAE")
                .font(ArbiterFont.mono(12).bold())
                .foregroundColor(.arbiterCyan)
                .tracking(3)
            Text("// FACTUAL AUGMENTATION")
                .font(ArbiterFont.mono(8))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            if faeManager.hasAttachedContext {
                attachedBadge
            }
            // Registry verification toggle
            Button {
                showVerification.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showVerification ? "checkmark.shield.fill" : "checkmark.shield")
                        .font(.system(size: 9))
                    Text("VERIFY")
                        .font(ArbiterFont.mono(8).bold())
                }
                .foregroundColor(registry.needsVerification ? .orange : .arbiterCyan.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Color.black.opacity(0.3))
    }

    private var attachedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.system(size: 8))
            Text("\(faeManager.attachedResults.count)")
                .font(ArbiterFont.mono(9).bold())
        }
        .foregroundColor(.arbiterCyan)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.arbiterCyan.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.arbiterCyan.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArbiterDivider(label: "Topic Search")
            HStack(spacing: 8) {
                TextField("e.g. spending trends in Lombardia", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(ArbiterFont.mono(11))
                    .foregroundColor(.arbiterText)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.arbiterBorder, lineWidth: 0.5)
                    )
                    .onSubmit { faeManager.search(topic: searchText, portals: registry.activeFAEPortals) }

                if faeManager.isSearching {
                    Button { faeManager.cancelSearch() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { faeManager.search(topic: searchText, portals: registry.activeFAEPortals) } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.arbiterCyan.opacity(searchText.isEmpty ? 0.3 : 0.9))
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.isEmpty)
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            Text("FILTER")
                .font(ArbiterFont.mono(8))
                .foregroundColor(.white.opacity(0.4))

            tierFilterPills
            Spacer()

            Toggle(isOn: $faeManager.strictAccuracy) {
                Text("STRICT")
                    .font(ArbiterFont.mono(8))
                    .foregroundColor(.white.opacity(0.5))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.arbiterCyan)
        }
    }

    private var tierFilterPills: some View {
        HStack(spacing: 0) {
            tierPill(label: "ALL", tier: nil)
            tierPill(label: "T1", tier: .verified)
            tierPill(label: "T2", tier: .academic)
            tierPill(label: "T3", tier: .community)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.arbiterBorder, lineWidth: 0.5)
        )
    }

    private func tierPill(label: String, tier: FAEAccuracyTier?) -> some View {
        let active = faeManager.filterTier == tier
        return Button { faeManager.filterTier = tier } label: {
            Text(label)
                .font(ArbiterFont.mono(8).bold())
                .foregroundColor(active ? .arbiterCyan : .white.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(active ? Color.arbiterCyan.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(.arbiterCyan)
                Text("SCANNING \(faeManager.completedPortals.count)/\(Set(faeManager.activePlans.map(\.portal.id)).count) PORTALS")
                    .font(ArbiterFont.mono(9))
                    .foregroundColor(.arbiterCyan.opacity(0.8))
                Spacer()
                Text("\(faeManager.results.count) results")
                    .font(ArbiterFont.mono(9))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(10)
        .modifier(ArbiterPanel())
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArbiterDivider(label: "Results (\(faeManager.filteredResults.count))")
            ForEach(faeManager.filteredResults) { item in
                PortalResultRow(item: item) {
                    if faeManager.attachedResults.contains(where: { $0.id == item.id }) {
                        faeManager.detach(item)
                    } else {
                        faeManager.attach(item)
                    }
                } isAttached: {
                    faeManager.attachedResults.contains(where: { $0.id == item.id })
                }
            }
        }
    }

    // MARK: - Failed Portals

    private var failedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArbiterDivider(label: "Failed Portals (\(faeManager.failedPortals.count))")
            ForEach(Array(faeManager.failedPortals.keys.sorted()), id: \.self) { portalID in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red.opacity(0.6))
                        .frame(width: 4, height: 4)
                    Text(portalID)
                        .font(ArbiterFont.mono(9))
                        .foregroundColor(.white.opacity(0.5))
                    Text(faeManager.failedPortals[portalID] ?? "")
                        .font(ArbiterFont.mono(8))
                        .foregroundColor(.red.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Attached Results

    private var attachedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ArbiterDivider(label: "Attached (\(faeManager.attachedResults.count))")
                Spacer()
                Button("CLEAR ALL") { faeManager.detachAll() }
                    .font(ArbiterFont.mono(8))
                    .foregroundColor(.red.opacity(0.7))
                    .buttonStyle(.plain)
            }
            ForEach(faeManager.attachedResults) { item in
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 9))
                        .foregroundColor(.arbiterCyan.opacity(0.7))
                    Text(item.title)
                        .font(ArbiterFont.mono(9))
                        .foregroundColor(.arbiterText)
                        .lineLimit(1)
                    Spacer()
                    Button { faeManager.detach(item) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color.arbiterCyan.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.arbiterCyan.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#Preview {
    FAEPanelView()
        .environmentObject(FAEManager())
        .environmentObject(FAEActiveRegistry())
        .environmentObject(FAEVerificationManager())
        .frame(width: 400, height: 600)
        .preferredColorScheme(.dark)
}
