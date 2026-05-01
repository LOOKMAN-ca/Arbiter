import SwiftUI

// MARK: - Portal Status Row
// Displays a PortalEntry (or a ProbeRecord) with its verification status,
// tier, region, API type, and last-checked timestamp.

struct PortalStatusRow: View {
    let record: ProbeRecord

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            statusDot

            // Name + metadata
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.portalName)
                        .font(ArbiterFont.mono(10).bold())
                        .foregroundColor(nameColor)
                        .lineLimit(1)
                    typeBadge
                    tierBadge
                }
                HStack(spacing: 8) {
                    Text(record.region.uppercased())
                        .font(ArbiterFont.mono(8))
                        .foregroundColor(.white.opacity(0.35))
                    if let note = record.outcome.note {
                        Text(note)
                            .font(ArbiterFont.mono(8))
                            .foregroundColor(noteColor)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            // Elapsed + outcome label
            VStack(alignment: .trailing, spacing: 2) {
                outcomeLabel
                Text(String(format: "%.1fs", record.elapsed))
                    .font(ArbiterFont.mono(7))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Sub-views

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 5, height: 5)
    }

    private var typeBadge: some View {
        Text(record.apiType.rawValue)
            .font(ArbiterFont.mono(7).bold())
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var tierBadge: some View {
        let color: Color = switch record.tier {
        case .verified:  .green
        case .academic:  .blue
        case .community: .orange
        }
        return Text(record.tier.label)
            .font(ArbiterFont.mono(7).bold())
            .foregroundColor(color.opacity(0.8))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var outcomeLabel: some View {
        let (label, color) = outcomeDescriptor
        return Text(label)
            .font(ArbiterFont.mono(8).bold())
            .foregroundColor(color)
    }

    // MARK: - Colors / Helpers

    private var outcomeDescriptor: (String, Color) {
        switch record.outcome {
        case .live(_, true, _):  return ("LIVE",      .green)
        case .live(_, false, _): return ("DEGRADED",  .yellow)
        case .degraded:          return ("DEGRADED",  .yellow)
        case .dead:              return ("DEAD",       .red)
        case .requiresAuth:      return ("AUTH REQ",   .orange)
        case .skipped:           return ("SKIPPED",    .white.opacity(0.3))
        }
    }

    private var dotColor: Color { outcomeDescriptor.1 }

    private var nameColor: Color {
        switch record.outcome {
        case .live(_, true, _): return .arbiterText
        case .skipped:          return .white.opacity(0.35)
        default:                return .white.opacity(0.6)
        }
    }

    private var noteColor: Color {
        switch record.outcome {
        case .dead, .requiresAuth: return .red.opacity(0.7)
        case .degraded, .live(_, false, _): return .yellow.opacity(0.7)
        default: return .white.opacity(0.3)
        }
    }

    private var rowBackground: Color {
        switch record.outcome {
        case .live(_, true, _): return Color.green.opacity(0.03)
        case .dead:             return Color.red.opacity(0.04)
        case .degraded, .live(_, false, _): return Color.yellow.opacity(0.03)
        default:                return Color.clear
        }
    }
}

// MARK: - Compact Entry Row (for registry browser, not probe results)

struct PortalEntryRow: View {
    let entry: PortalEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(ArbiterFont.mono(10))
                        .foregroundColor(.arbiterText)
                        .lineLimit(1)
                    Text(entry.type.rawValue)
                        .font(ArbiterFont.mono(7))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(entry.verification.displayLabel + "  ·  " + entry.region.uppercased())
                    .font(ArbiterFont.mono(8))
                    .foregroundColor(statusColor.opacity(0.7))
            }

            Spacer()

            if let checked = entry.lastChecked {
                Text(checked.relativeLabel)
                    .font(ArbiterFont.mono(7))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch entry.verification {
        case .verifiedLive:           return .green
        case .verifiedThisSession:    return .green.opacity(0.7)
        case .documentedEndpoint:     return .arbiterCyan
        case .confirmedExistenceOnly: return .white.opacity(0.4)
        case .probedFailed:           return .red
        case .probedDegraded:         return .yellow
        }
    }
}

// MARK: - Date helper

private extension Date {
    var relativeLabel: String {
        let days = Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "1d ago" }
        return "\(days)d ago"
    }
}
