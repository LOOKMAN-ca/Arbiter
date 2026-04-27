import Foundation

// MARK: - Result Item

struct FAEResultItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let portalID: String
    let title: String
    let snippet: String?
    let sourceURL: URL?
    let publicationDate: Date?

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: FAEResultItem, rhs: FAEResultItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Fetch Error

struct FAEFetchError: Error, Sendable {
    let portalID: String
    let message: String
}

// MARK: - Fetch Event

enum FAEFetchEvent: Sendable {
    case started(FAEQueryPlan)
    case completed(FAEQueryPlan, [FAEResultItem])
    case failed(FAEQueryPlan, FAEFetchError)
}

// MARK: - Context Fragment

struct ContextFragment: Sendable {
    let providerID: String
    let title: String
    let body: String
    let sourceURL: URL?
}

// MARK: - Context Provider Protocol

protocol ConversationContextProvider: Sendable {
    var providerID: String { get }
    func contextFragments(for prompt: String) async -> [ContextFragment]
}
