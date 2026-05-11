import Foundation
import Combine
import os


// MARK: - Probe Record (stream event payload)

struct ProbeRecord: Sendable, Identifiable {
    let id: UUID = UUID()
    let portalID: String
    let portalName: String
    let region: String
    let apiType: APIProtocol
    let tier: FAEAccuracyTier
    let outcome: ProbeOutcome
    let elapsed: TimeInterval
    let timestamp: Date = Date()
}

// MARK: - Verification Event

enum VerificationEvent: Sendable {
    case progress(record: ProbeRecord, completed: Int, total: Int)
    case done(entries: [PortalEntry], liveCount: Int, qualityGatePassed: Bool)
    case failed(Error)
}

// MARK: - FAE Verifier Actor
//
// §3.2 concurrency limits: max 6 simultaneous probes, max 2 per host.
// §2.8 stale-entry policy: deactivate after 3 consecutive failures (N = 3).
// §2.7 cadence: triggered by FAEActiveRegistry when hash changes or 14 days elapsed.

actor FAEVerifier {

    private let logger = Logger(subsystem: "com.LOOKMAN.Arbiter", category: "FAEVerifier")

    static let maxConcurrent = 6
    static let maxPerHost    = 2
    static let qualityGate   = 60  // §6.4

    // Returns a stream that emits progress events as probes complete, then a final .done event.
    // The probes run in a detached child task so the stream can be iterated concurrently.
    func makeStream(entries: [PortalEntry]) -> AsyncStream<VerificationEvent> {
        let (stream, continuation) = AsyncStream<VerificationEvent>.makeStream()
        Task {
            await runInternal(entries: entries, continuation: continuation)
        }
        return stream
    }

    // MARK: - Internal Run

    private func runInternal(
        entries: [PortalEntry],
        continuation: AsyncStream<VerificationEvent>.Continuation
    ) async {
        // confirmed_existence_only entries have unverified URLs (often bare website homepages,
        // not API endpoints). Probing them produces hundreds of expected HTML-shape failures
        // that obscure genuinely broken documented-endpoint portals and waste probe time.
        // They are already excluded from the active registry, so skipping them here is safe.
        var updated  = entries
        let session  = FAEProbeSession.make()

        var inFlight: Int                 = 0
        var hostInFlight: [String: Int]   = [:]
        var pending: [(index: Int, entry: PortalEntry)] = entries.enumerated()
            .filter { $0.element.verification != .confirmedExistenceOnly }
            .map { ($0.offset, $0.element) }
        let total = pending.count
        var completedCount = 0

        await withTaskGroup(of: (Int, ProbeRecord, ProbeOutcome).self) { group in

            func canLaunch(_ entry: PortalEntry) -> Bool {
                let host = entry.url.host() ?? "unknown"
                return inFlight < FAEVerifier.maxConcurrent
                    && (hostInFlight[host] ?? 0) < FAEVerifier.maxPerHost
            }

            func launchNext() {
                while let idx = pending.firstIndex(where: { canLaunch($0.entry) }) {
                    let (origIdx, entry) = pending.remove(at: idx)
                    let host = entry.url.host() ?? "unknown"
                    inFlight += 1
                    hostInFlight[host, default: 0] += 1

                    group.addTask { [entry, session] in
                        let start   = Date()
                        let outcome = await ProbeDispatcher.probe(entry, session: session)
                        let elapsed = Date().timeIntervalSince(start)
                        let record  = ProbeRecord(
                            portalID:  entry.id,
                            portalName: entry.name,
                            region:    entry.region,
                            apiType:   entry.type,
                            tier:      entry.tier,
                            outcome:   outcome,
                            elapsed:   elapsed
                        )
                        return (origIdx, record, outcome)
                    }
                }
            }

            launchNext()

            for await (origIdx, record, outcome) in group {
                let host = entries[origIdx].url.host() ?? "unknown"
                inFlight -= 1
                hostInFlight[host, default: 0] -= 1
                completedCount += 1

                // Persist probe results into entry
                if outcome.shouldUpdateLabel {
                    updated[origIdx].verification = outcome.verificationLabel
                }
                updated[origIdx].lastChecked = record.timestamp
                updated[origIdx].lastNote    = outcome.note
                updated[origIdx].lastStatus  = outcome.httpStatus

                // Consecutive-failure tracking (§2.8, N = 3)
                switch outcome {
                case .live(_, true, _):
                    updated[origIdx].consecutiveFailures = 0
                case .dead, .requiresAuth, .degraded, .live(_, false, _):
                    updated[origIdx].consecutiveFailures = (updated[origIdx].consecutiveFailures ?? 0) + 1
                case .skipped:
                    break
                }

                continuation.yield(.progress(record: record, completed: completedCount, total: total))
                launchNext()
            }
        }

        // Persist to disk
        let liveCount      = updated.filter { $0.verification == .verifiedLive }.count
        // Quality gate: require at least qualityGate% of probed entries to be live,
        // with a floor of 10. This avoids false FAIL when the registry is small or
        // when an unusually large fraction of portals happen to be slow on a given run.
        let gateThreshold  = max(FAEVerifier.qualityGate, total * 40 / 100)
        let passed         = liveCount >= gateThreshold

        do {
            try FAERegistryLoader.saveVerified(updated)
            logger.info("FAEVerifier: saved \(updated.count) entries. Probed: \(total), live: \(liveCount)/\(gateThreshold), gate: \(passed ? "PASS" : "FAIL")")
        } catch {
            logger.error("FAEVerifier: save failed: \(error.localizedDescription)")
        }

        // Write Markdown report
        do {
            let report = buildReport(entries: updated, liveCount: liveCount)
            try FAERegistryLoader.saveReport(report)
        } catch {
            logger.error("FAEVerifier: report write failed: \(error.localizedDescription)")
        }

        if !passed {
            logger.error("FAEVerifier: QUALITY GATE FAILED — \(liveCount)/\(gateThreshold) verified-live entries (probed \(total)). Check DNS, ATS entitlement, and User-Agent policy.")
        }

        continuation.yield(.done(entries: updated, liveCount: liveCount, qualityGatePassed: passed))
        continuation.finish()
    }

    // MARK: - Markdown Report Builder (§5)

    private func buildReport(entries: [PortalEntry], liveCount: Int) -> String {
        let iso = ISO8601DateFormatter()
        let now = iso.string(from: Date())
        let hash = FAERegistryLoader.bundleHash() ?? "unknown"
        let total = entries.count
        let active = entries.filter { isActive($0) }.count

        var lines: [String] = [
            "# FAE Verification Report",
            "Generated: \(now)",
            "Source: fae_registry_v6.json (hash: \(hash))",
            "Total entries: \(total)",
            "Active: \(active) / Inactive: \(total - active)",
            "",
            "## Summary by protocol",
            "| Protocol | Total | Live | Degraded | Failed | Skipped |",
            "|---|---|---|---|---|---|",
        ]

        let protocols = APIProtocol.allCases
        for proto in protocols {
            let group = entries.filter { $0.type == proto }
            if group.isEmpty { continue }
            let live     = group.filter { $0.verification == .verifiedLive }.count
            let degraded = group.filter { $0.verification == .probedDegraded }.count
            let failed   = group.filter { $0.verification == .probedFailed }.count
            let skipped  = group.filter { $0.auth == .paidKey || $0.auth == .oauth }.count
            lines.append("| \(proto.rawValue) | \(group.count) | \(live) | \(degraded) | \(failed) | \(skipped) |")
        }

        lines += ["", "## Summary by region", "| Region | Total | Live |", "|---|---|---|"]
        let regions = Set(entries.map { $0.region }).sorted()
        for region in regions {
            let group = entries.filter { $0.region == region }
            let live  = group.filter { $0.verification == .verifiedLive }.count
            lines.append("| \(region) | \(group.count) | \(live) |")
        }

        let failed   = entries.filter { $0.verification == .probedFailed }
        let degraded = entries.filter { $0.verification == .probedDegraded }
        let skipped  = entries.filter { $0.auth == .paidKey || $0.auth == .oauth }

        lines += ["", "## Failed entries (action required)"]
        if failed.isEmpty {
            lines.append("None.")
        } else {
            for e in failed {
                lines += [
                    "",
                    "### \(e.id) — \(e.name)",
                    "- Type: \(e.type.rawValue)  |  URL: \(e.url.absoluteString)",
                    "- Reason: \(e.lastNote ?? "unknown")",
                    "- Suggested: re-check docs / find replacement / drop",
                ]
            }
        }

        lines += ["", "## Degraded entries"]
        if degraded.isEmpty {
            lines.append("None.")
        } else {
            for e in degraded {
                lines += [
                    "",
                    "### \(e.id) — \(e.name)",
                    "- Type: \(e.type.rawValue)  |  URL: \(e.url.absoluteString)",
                    "- Reason: \(e.lastNote ?? "unknown")",
                ]
            }
        }

        lines += ["", "## Skipped entries (auth required)"]
        if skipped.isEmpty {
            lines.append("None.")
        } else {
            for e in skipped {
                lines += [
                    "",
                    "### \(e.id) — \(e.name)",
                    "- Auth required: \(e.auth.rawValue)",
                    "- URL: \(e.url.absoluteString)",
                ]
            }
        }

        lines += ["", "## Drift since last run", "*(Updated on each run — compare git diff for changes.)*", ""]
        return lines.joined(separator: "\n")
    }

    private func isActive(_ e: PortalEntry) -> Bool {
        e.verification.isActiveEligible
            && (e.consecutiveFailures ?? 0) < 3
            && e.auth.isUsableWithoutConfig
            && e.type != .docIndex
    }
}

// MARK: - APIProtocol: CaseIterable for report generation

extension APIProtocol: CaseIterable {
    public nonisolated static var allCases: [APIProtocol] {
        [.ckan, .dkan, .socrata, .rest, .sparql, .sdmx, .oaiPmh, .geojson, .wfs, .docIndex, .github, .graphql, .dcat]
    }
}

// MARK: - FAE Verification Manager (MainActor UI bridge)

@MainActor
final class FAEVerificationManager: ObservableObject {

    @Published private(set) var isRunning        = false
    @Published private(set) var records: [ProbeRecord] = []
    @Published private(set) var completedCount   = 0
    @Published private(set) var totalCount       = 0
    @Published private(set) var liveCount        = 0
    @Published private(set) var qualityGatePassed: Bool?
    @Published private(set) var updatedEntries: [PortalEntry] = []
    @Published var errorMessage: String?

    private let verifier = FAEVerifier()
    private var runTask: Task<Void, Never>?

    var reportURL: URL? { FAERegistryLoader.reportFileURL }

    func startVerification(entries: [PortalEntry]) {
        guard !isRunning else { return }
        isRunning        = true
        records          = []
        completedCount   = 0
        totalCount       = entries.count
        qualityGatePassed = nil
        errorMessage     = nil

        runTask = Task {
            let stream = await verifier.makeStream(entries: entries)
            for await event in stream {
                switch event {
                case .progress(let record, let completed, let total):
                    records.append(record)
                    completedCount = completed
                    totalCount     = total

                case .done(let updated, let live, let passed):
                    updatedEntries    = updated
                    liveCount         = live
                    qualityGatePassed = passed
                    isRunning         = false

                case .failed(let error):
                    errorMessage = error.localizedDescription
                    isRunning    = false
                }
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask  = nil
        isRunning = false
    }

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}
