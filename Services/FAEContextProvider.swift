import Foundation
import SwiftUI
import Combine
import os

// MARK: - FAE Manager
//
// Coordinates FAEEngine (planner) and FAEFetcher (executor).
// Holds UI state for FAE panel and serves as the conversation
// context provider for model augmentation.

private let managerLogger = Logger(subsystem: "com.LOOKMAN.Arbiter", category: "FAEManager")

@MainActor
final class FAEManager: ObservableObject {

    // MARK: - Published State

    @Published var results: [FAEResultItem] = []
    @Published var attachedResults: [FAEResultItem] = []
    @Published var isSearching = false
    @Published var completedPortals: Set<String> = []
    @Published var failedPortals: [String: String] = [:]
    @Published var activePlans: [FAEQueryPlan] = []

    @Published var filterTier: FAEAccuracyTier?
    @Published var filterMode: FAEMode = .currentSnapshot
    @Published var strictAccuracy = true

    // MARK: - Private

    private let fetcher = FAEFetcher()
    private var searchTask: Task<Void, Never>?
    private var searchPortals: [FAEPortal] = []

    // MARK: - Search

    func search(topic: String, portals: [FAEPortal]? = nil) {
        guard !topic.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        searchTask?.cancel()
        results = []
        completedPortals = []
        failedPortals = [:]
        activePlans = []
        isSearching = true
        searchPortals = portals ?? FAEPortal.registry

        searchTask = Task {
            let expanded = FAEEngine.expand(topic: topic)
            let plans = FAEEngine.plan(expanded: expanded, portals: portals ?? FAEPortal.registry, strictAccuracy: strictAccuracy)
            activePlans = plans

            managerLogger.info("FAE search: '\(topic)' → \(plans.count) plans")

            let stream = await fetcher.execute(plans)

            for await event in stream {
                guard !Task.isCancelled else { break }

                switch event {
                case .started:
                    break

                case .completed(let plan, let items):
                    completedPortals.insert(plan.portal.id)
                    let deduped = deduplicate(newItems: items, existing: results)
                    results.append(contentsOf: deduped)

                case .failed(let plan, let error):
                    failedPortals[plan.portal.id] = error.message
                    managerLogger.warning("Portal \(plan.portal.id) failed: \(error.message)")
                }
            }

            isSearching = false
            managerLogger.info("FAE search complete: \(self.results.count) results from \(self.completedPortals.count) portals")
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    // MARK: - Attach / Detach

    func attach(_ item: FAEResultItem) {
        guard !attachedResults.contains(where: { $0.id == item.id }) else { return }
        attachedResults.append(item)
    }

    func detach(_ item: FAEResultItem) {
        attachedResults.removeAll { $0.id == item.id }
    }

    func detachAll() {
        attachedResults.removeAll()
    }

    var hasAttachedContext: Bool {
        !attachedResults.isEmpty
    }

    // MARK: - Context Block

    /// Formats attached results as a structured context string for
    /// injection into the model prompt. Returns nil if nothing attached.
    var contextBlock: String? {
        guard !attachedResults.isEmpty else { return nil }

        var lines: [String] = ["[FAE CONTEXT — Factual Augmentation Engine Results]"]
        lines.append("The following are verified open-data results attached as evidence:\n")

        for (i, item) in attachedResults.enumerated() {
            lines.append("[\(i + 1)] \(item.title)")
            if let snippet = item.snippet {
                lines.append("    \(String(snippet.prefix(200)))")
            }
            if let url = item.sourceURL {
                lines.append("    Source: \(url.absoluteString)")
            }
            let portal = searchPortals.first { $0.id == item.portalID }
                ?? FAEPortal.registry.first { $0.id == item.portalID }
            if let portal {
                lines.append("    Portal: \(portal.name) (\(portal.tier.label))")
            }
            lines.append("")
        }

        lines.append("[END FAE CONTEXT]\n")
        return lines.joined(separator: "\n")
    }

    // MARK: - Filtering

    var filteredResults: [FAEResultItem] {
        results.filter { item in
            if let tierFilter = filterTier {
                let portal = searchPortals.first { $0.id == item.portalID }
                    ?? FAEPortal.registry.first { $0.id == item.portalID }
                if portal?.tier != tierFilter { return false }
            }
            return true
        }
    }

    // MARK: - Deduplication

    /// Cheap dedup on (normalizedTitle, sourceHost).
    /// Fixes Python source defect §8.6.
    private func deduplicate(newItems: [FAEResultItem], existing: [FAEResultItem]) -> [FAEResultItem] {
        let existingKeys = Set(existing.map { deduplicationKey(for: $0) })
        return newItems.filter { item in
            !existingKeys.contains(deduplicationKey(for: item))
        }
    }

    private func deduplicationKey(for item: FAEResultItem) -> String {
        let normalizedTitle = item.title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = item.sourceURL?.host() ?? item.portalID
        return "\(normalizedTitle)|\(host)"
    }
}

// MARK: - ConversationContextProvider Conformance

extension FAEManager: ConversationContextProvider {
    nonisolated var providerID: String { "fae" }

    func contextFragments(for prompt: String) async -> [ContextFragment] {
        let expanded = FAEEngine.expand(topic: prompt)
        let portals = searchPortals.isEmpty ? FAEPortal.registry : searchPortals
        let plans = FAEEngine.plan(expanded: expanded, portals: portals, strictAccuracy: strictAccuracy)
        let limitedPlans = Array(plans.prefix(20))

        var allItems: [FAEResultItem] = []

        let stream = await fetcher.execute(limitedPlans)
        for await event in stream {
            if case .completed(_, let items) = event {
                allItems.append(contentsOf: items)
            }
        }

        let topItems = Array(allItems.prefix(5))
        return topItems.map { item in
            ContextFragment(
                providerID: providerID,
                title: item.title,
                body: item.snippet ?? item.title,
                sourceURL: item.sourceURL
            )
        }
    }
}
