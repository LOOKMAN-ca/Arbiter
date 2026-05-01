import Foundation
import Combine
import os

// MARK: - FAE Active Registry
//
// Owns the portal list for the lifetime of the app.
// Loads from FAERegistryLoader (bundle → verified → user-override priority chain).
// Computes the active subset per §3.4 rules.
//
// §2.7 cadence: re-verification is triggered when:
//   - The bundle JSON hash has changed since the last run, OR
//   - More than 14 days have elapsed since the last verification run.

private let registryLogger = Logger(subsystem: "com.LOOKMAN.Arbiter", category: "FAEActiveRegistry")

@MainActor
final class FAEActiveRegistry: ObservableObject {

    // MARK: Published State

    @Published private(set) var rawEntries:      [PortalEntry] = []
    @Published private(set) var activeEntries:   [PortalEntry] = []
    @Published private(set) var inactiveEntries: [PortalEntry] = []
    @Published private(set) var isLoaded:        Bool = false
    @Published private(set) var loadError:       String?
    @Published private(set) var needsVerification: Bool = false

    // MARK: Derived

    /// Bridge to legacy FAEPortal type for FAEEngine / FAEFetcher.
    var activeFAEPortals: [FAEPortal] {
        activeEntries.map { $0.asFAEPortal }
    }

    var activeCount:   Int { activeEntries.count }
    var inactiveCount: Int { inactiveEntries.count }

    // MARK: Load

    func load() {
        do {
            let entries = try FAERegistryLoader.load()
            rawEntries      = entries
            activeEntries   = entries.filter(isActive)
            inactiveEntries = entries.filter { !isActive($0) }
            isLoaded        = true
            loadError       = nil
            needsVerification = shouldVerify(entries: entries)

            registryLogger.info("FAEActiveRegistry: \(entries.count) raw, \(self.activeEntries.count) active, \(self.inactiveEntries.count) inactive")

            if needsVerification {
                registryLogger.info("FAEActiveRegistry: verification recommended (hash changed or 14-day cadence elapsed)")
            }
        } catch {
            loadError = error.localizedDescription
            registryLogger.error("FAEActiveRegistry: load failed — \(error.localizedDescription)")
            // Fall back to the static hardcoded registry so FAE is still usable.
            let fallback = FAEPortal.registry.map(\.asPortalEntry)
            rawEntries      = fallback
            activeEntries   = fallback
            inactiveEntries = []
            isLoaded        = true
            needsVerification = true
        }
    }

    /// Called by FAEVerificationView after a run completes to refresh the active set.
    func reloadAfterVerification(updatedEntries: [PortalEntry]) {
        rawEntries      = updatedEntries
        activeEntries   = updatedEntries.filter(isActive)
        inactiveEntries = updatedEntries.filter { !isActive($0) }
        needsVerification = false
        registryLogger.info("FAEActiveRegistry: refreshed after verification — \(self.activeEntries.count) active")
    }

    // MARK: Active-Registry Rule (§3.4)
    //
    // An entry is active iff:
    //   - verification ∈ {verifiedLive, verifiedThisSession, documentedEndpoint}
    //   - consecutiveFailures < 3
    //   - auth ∈ {none, freeKey}  (no credentials configured)
    //   - type ≠ .docIndex

    private func isActive(_ e: PortalEntry) -> Bool {
        guard e.type != .docIndex                          else { return false }
        guard e.verification.isActiveEligible              else { return false }
        guard (e.consecutiveFailures ?? 0) < 3            else { return false }
        guard e.auth.isUsableWithoutConfig                 else { return false }
        return true
    }

    // MARK: Verification Cadence (§2.7)

    private func shouldVerify(entries: [PortalEntry]) -> Bool {
        // If no entry has ever been probed, verification is needed.
        guard entries.contains(where: { $0.lastChecked != nil }) else { return true }

        // Check 14-day cadence.
        let mostRecent = entries.compactMap { $0.lastChecked }.max() ?? .distantPast
        let daysSince  = Calendar.current.dateComponents([.day], from: mostRecent, to: Date()).day ?? Int.max
        if daysSince >= 14 { return true }

        // Check bundle hash drift.
        let currentHash = FAERegistryLoader.bundleHash() ?? ""
        let storedHash  = UserDefaults.standard.string(forKey: "FAE.lastBundleHash") ?? ""
        if currentHash != storedHash {
            UserDefaults.standard.set(currentHash, forKey: "FAE.lastBundleHash")
            return true
        }
        return false
    }
}

// MARK: - FAEPortal → PortalEntry bridge (fallback path)

private extension FAEPortal {
    var asPortalEntry: PortalEntry {
        let json = """
        {"id":"\(id)","name":"\(name)","type":"\(api.rawValue)","acc":\(tier.rawValue),"url":"\(baseURL.absoluteString)","lang":["en"],"region":"unknown","domains":\(Array(domains).jsonEncoded),"license":"unknown","historical":\(supportsHistorical),"auth":"none","verification":"documented_endpoint"}
        """
        let decoder = JSONDecoder()
        return (try? decoder.decode(PortalEntry.self, from: Data(json.utf8))) ?? PortalEntry.placeholder(id: id, name: name)
    }
}

private extension Array where Element == String {
    var jsonEncoded: String {
        let escaped = map { "\"\($0)\"" }.joined(separator: ",")
        return "[\(escaped)]"
    }
}

private extension PortalEntry {
    static func placeholder(id: String, name: String) -> PortalEntry {
        // Synthesise a minimal valid entry for the fallback path.
        // This should never be reached in practice, but keeps the registry non-empty
        // if JSON decoding of the bridge string somehow fails.
        let json = """
        {"id":"\(id)","name":"\(name)","type":"REST","acc":3,"url":"https://example.com","lang":["en"],"region":"unknown","domains":["general"],"license":"unknown","historical":false,"auth":"none","verification":"confirmed_existence_only"}
        """
        let decoder = JSONDecoder()
        return try! decoder.decode(PortalEntry.self, from: Data(json.utf8))
    }
}
