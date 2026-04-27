import Foundation

// MARK: - FAE Mode

enum FAEMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case currentSnapshot
    case historical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .currentSnapshot: return "SNAPSHOT"
        case .historical:      return "HISTORICAL"
        }
    }
}

// MARK: - Expanded Topic

struct FAEExpandedTopic: Sendable {
    let originalTopic: String
    let keywords: [String]
    let mode: FAEMode
    let inferredDomains: Set<String>
}

// MARK: - Query Plan

struct FAEQueryPlan: Identifiable, Hashable, Sendable {
    let id: UUID
    let portal: FAEPortal
    let term: String
    let mode: FAEMode
    let endpoint: URL

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: FAEQueryPlan, rhs: FAEQueryPlan) -> Bool {
        lhs.id == rhs.id
    }
}
