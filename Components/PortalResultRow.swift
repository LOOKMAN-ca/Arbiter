import SwiftUI

// MARK: - Portal Result Row

struct PortalResultRow: View {
    let item: FAEResultItem
    let onToggleAttach: () -> Void
    let isAttached: () -> Bool

    private var portal: FAEPortal? {
        FAEPortal.registry.first { $0.id == item.portalID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: portal badge + tier + attach
            HStack(spacing: 8) {
                portalBadge
                Spacer()
                tierBadge
                attachButton
            }

            // Title
            Text(item.title)
                .font(ArbiterFont.mono(10))
                .foregroundColor(.arbiterText)
                .lineLimit(2)

            // Snippet
            if let snippet = item.snippet {
                Text(snippet)
                    .font(ArbiterFont.mono(9))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(3)
            }

            // Source link
            if let url = item.sourceURL {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 8))
                    Text(url.host() ?? url.absoluteString)
                        .lineLimit(1)
                }
                .font(ArbiterFont.mono(8))
                .foregroundColor(.arbiterCyan.opacity(0.6))
            }
        }
        .padding(10)
        .background(isAttached() ? Color.arbiterCyan.opacity(0.04) : Color.clear)
        .modifier(ArbiterPanel())
    }

    // MARK: - Portal Badge

    private var portalBadge: some View {
        Text(portal?.name ?? item.portalID)
            .font(ArbiterFont.mono(8).bold())
            .foregroundColor(.white.opacity(0.6))
            .tracking(0.5)
    }

    // MARK: - Tier Badge

    private var tierBadge: some View {
        let tier = portal?.tier ?? .community
        let color: Color = switch tier {
        case .verified:  .green
        case .academic:  .blue
        case .community: .orange
        }

        return Text(tier.label)
            .font(ArbiterFont.mono(7).bold())
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Attach Button

    private var attachButton: some View {
        let attached = isAttached()
        return Button(action: onToggleAttach) {
            HStack(spacing: 3) {
                Image(systemName: attached ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 10))
                Text(attached ? "ATTACHED" : "ATTACH")
                    .font(ArbiterFont.mono(7).bold())
            }
            .foregroundColor(attached ? .green : .arbiterCyan.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(attached ? Color.green.opacity(0.08) : Color.arbiterCyan.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke((attached ? Color.green : Color.arbiterCyan).opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        PortalResultRow(
            item: FAEResultItem(
                id: UUID(),
                portalID: "ITA_GOV",
                title: "Dataset: Bilancio dello Stato 2024",
                snippet: "Dati relativi al bilancio di previsione dello Stato per l'anno finanziario 2024.",
                sourceURL: URL(string: "https://www.dati.gov.it/view-dataset/123"),
                publicationDate: nil
            ),
            onToggleAttach: {},
            isAttached: { false }
        )

        PortalResultRow(
            item: FAEResultItem(
                id: UUID(),
                portalID: "SCI_ZEN",
                title: "Research: Population dynamics in Mediterranean regions",
                snippet: "A comprehensive study on demographic shifts across Southern European coastal areas.",
                sourceURL: URL(string: "https://zenodo.org/record/999999"),
                publicationDate: nil
            ),
            onToggleAttach: {},
            isAttached: { true }
        )
    }
    .padding()
    .frame(width: 380)
    .background(Color.arbiterBg)
    .preferredColorScheme(.dark)
}
