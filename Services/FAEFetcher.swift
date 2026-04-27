import Foundation
import os

// MARK: - FAE Fetcher (Executor)
//
// Actor-isolated network executor. Runs query plans concurrently
// with a global concurrency cap, streams results via AsyncStream.
// Implements retry on transient errors (5xx, timeout) and per-API
// response normalization.
//
// DECIDE §4.8: No on-disk cache in v1. The cache layer would add
// complexity without clear benefit until usage patterns are known.
// The TTL and key scheme are documented in the brief for future work.
//
// DECIDE §4.9: Global concurrency cap of 10. Per-host throttling
// deferred to v2 — most queries hit distinct hosts anyway.

private let fetcherLogger = Logger(subsystem: "com.LOOKMAN.Arbiter", category: "FAEFetcher")

actor FAEFetcher {
    private let session: URLSession
    private let maxConcurrent: Int
    private let perRequestTimeout: TimeInterval

    init(session: URLSession = .shared, maxConcurrent: Int = 10, timeout: TimeInterval = 8) {
        self.session = session
        self.maxConcurrent = maxConcurrent
        self.perRequestTimeout = timeout
    }

    // MARK: - Execute Plans

    func execute(_ plans: [FAEQueryPlan]) -> AsyncStream<FAEFetchEvent> {
        let cap = maxConcurrent
        let sess = session
        let timeout = perRequestTimeout

        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: Void.self) { group in
                    var iterator = plans.makeIterator()
                    let batchSize = min(cap, plans.count)

                    for _ in 0..<batchSize {
                        guard let plan = iterator.next() else { break }
                        group.addTask {
                            await Self.executeSingle(plan, session: sess, timeout: timeout, continuation: continuation)
                        }
                    }

                    for await _ in group {
                        if let plan = iterator.next() {
                            group.addTask {
                                await Self.executeSingle(plan, session: sess, timeout: timeout, continuation: continuation)
                            }
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Single Plan Execution

    private static func executeSingle(
        _ plan: FAEQueryPlan,
        session: URLSession,
        timeout: TimeInterval,
        continuation: AsyncStream<FAEFetchEvent>.Continuation
    ) async {
        continuation.yield(.started(plan))

        var request = URLRequest(url: plan.endpoint)
        request.timeoutInterval = timeout
        request.setValue("Arbiter/1.0 FAE", forHTTPHeaderField: "User-Agent")

        if plan.portal.api == .github {
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        }

        do {
            let data = try await fetchWithRetry(request: request, session: session, portalID: plan.portal.id)
            let items = normalize(data: data, plan: plan)
            continuation.yield(.completed(plan, items))
        } catch let error as FAEFetchError {
            continuation.yield(.failed(plan, error))
        } catch {
            continuation.yield(.failed(plan, FAEFetchError(portalID: plan.portal.id, message: error.localizedDescription)))
        }
    }

    // MARK: - Retry Logic

    private static func fetchWithRetry(request: URLRequest, session: URLSession, portalID: String) async throws -> Data {
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw FAEFetchError(portalID: portalID, message: "Non-HTTP response")
                }

                if (400..<500).contains(http.statusCode) {
                    throw FAEFetchError(portalID: portalID, message: "HTTP \(http.statusCode)")
                }

                if http.statusCode >= 500 {
                    if attempt == 0 {
                        fetcherLogger.warning("Portal \(portalID): HTTP \(http.statusCode), retrying...")
                        continue
                    }
                    throw FAEFetchError(portalID: portalID, message: "HTTP \(http.statusCode) after retry")
                }

                return data
            } catch let error as FAEFetchError {
                throw error
            } catch {
                if attempt == 0 {
                    fetcherLogger.warning("Portal \(portalID): \(error.localizedDescription), retrying...")
                    continue
                }
                throw FAEFetchError(portalID: portalID, message: error.localizedDescription)
            }
        }

        throw FAEFetchError(portalID: portalID, message: "Exhausted retries")
    }

    // MARK: - Response Normalization

    private static func normalize(data: Data, plan: FAEQueryPlan) -> [FAEResultItem] {
        switch plan.portal.api {
        case .ckan:     return normalizeCKAN(data, portalID: plan.portal.id)
        case .github:   return normalizeGitHub(data, portalID: plan.portal.id)
        case .sparql:   return normalizeSPARQL(data, portalID: plan.portal.id)
        case .rest:     return normalizeGenericJSON(data, portalID: plan.portal.id)
        case .json:     return normalizeGenericJSON(data, portalID: plan.portal.id)
        case .sdmx:     return normalizeSDMX(data, portalID: plan.portal.id)
        default:        return normalizeGenericJSON(data, portalID: plan.portal.id)
        }
    }

    // MARK: CKAN Normalizer

    private static func normalizeCKAN(_ data: Data, portalID: String) -> [FAEResultItem] {
        struct Response: Decodable {
            let result: ResultContainer?
            struct ResultContainer: Decodable {
                let results: [Package]?
            }
            struct Package: Decodable {
                let title: String?
                let notes: String?
                let url: String?
                let metadata_modified: String?
            }
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let packages = response.result?.results
        else {
            fetcherLogger.debug("CKAN parse failed for \(portalID)")
            return []
        }

        return packages.compactMap { pkg in
            guard let title = pkg.title, !title.isEmpty else { return nil }
            return FAEResultItem(
                id: UUID(),
                portalID: portalID,
                title: title,
                snippet: pkg.notes.map { String($0.prefix(300)) },
                sourceURL: pkg.url.flatMap(URL.init(string:)),
                publicationDate: parseISO8601(pkg.metadata_modified)
            )
        }
    }

    // MARK: GitHub Normalizer

    private static func normalizeGitHub(_ data: Data, portalID: String) -> [FAEResultItem] {
        struct Response: Decodable {
            let items: [Repo]?
            struct Repo: Decodable {
                let full_name: String?
                let description: String?
                let html_url: String?
                let updated_at: String?
            }
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let items = response.items
        else { return [] }

        return items.compactMap { repo in
            guard let name = repo.full_name else { return nil }
            return FAEResultItem(
                id: UUID(),
                portalID: portalID,
                title: name,
                snippet: repo.description,
                sourceURL: repo.html_url.flatMap(URL.init(string:)),
                publicationDate: parseISO8601(repo.updated_at)
            )
        }
    }

    // MARK: SPARQL Normalizer

    private static func normalizeSPARQL(_ data: Data, portalID: String) -> [FAEResultItem] {
        struct Response: Decodable {
            let results: Bindings?
            struct Bindings: Decodable {
                let bindings: [Binding]?
            }
            struct Binding: Decodable {
                let s: RDFTerm?
                let p: RDFTerm?
                let o: RDFTerm?
            }
            struct RDFTerm: Decodable {
                let type: String?
                let value: String?
            }
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let bindings = response.results?.bindings
        else { return [] }

        return bindings.compactMap { binding in
            let subject = binding.s?.value ?? "Unknown"
            let predicate = binding.p?.value?.components(separatedBy: "/").last ?? ""
            let object = binding.o?.value ?? ""

            guard !object.isEmpty else { return nil }

            return FAEResultItem(
                id: UUID(),
                portalID: portalID,
                title: "\(predicate): \(String(object.prefix(100)))",
                snippet: object.count > 100 ? String(object.prefix(300)) : nil,
                sourceURL: URL(string: subject),
                publicationDate: nil
            )
        }
    }

    // MARK: SDMX Normalizer (basic)

    private static func normalizeSDMX(_ data: Data, portalID: String) -> [FAEResultItem] {
        guard let xmlString = String(data: data, encoding: .utf8) else { return [] }

        var items: [FAEResultItem] = []
        let seriesPattern = #"<generic:SeriesKey>.*?</generic:SeriesKey>"#
        let range = xmlString.startIndex..<xmlString.endIndex
        let regex = try? NSRegularExpression(pattern: seriesPattern, options: [.dotMatchesLineSeparators])
        let matches = regex?.matches(in: xmlString, range: NSRange(range, in: xmlString)) ?? []

        for match in matches.prefix(10) {
            if let matchRange = Range(match.range, in: xmlString) {
                let snippet = String(xmlString[matchRange])
                items.append(FAEResultItem(
                    id: UUID(),
                    portalID: portalID,
                    title: "SDMX Series (\(portalID))",
                    snippet: String(snippet.prefix(300)),
                    sourceURL: nil,
                    publicationDate: nil
                ))
            }
        }

        if items.isEmpty && !xmlString.isEmpty {
            items.append(FAEResultItem(
                id: UUID(),
                portalID: portalID,
                title: "SDMX Data (\(portalID))",
                snippet: String(xmlString.prefix(300)),
                sourceURL: nil,
                publicationDate: nil
            ))
        }

        return items
    }

    // MARK: Generic JSON Normalizer

    private static func normalizeGenericJSON(_ data: Data, portalID: String) -> [FAEResultItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let candidateArrayKeys = ["results", "items", "data", "records", "hits", "documents", "entries"]
        var rawItems: [[String: Any]] = []

        for key in candidateArrayKeys {
            if let arr = json[key] as? [[String: Any]] {
                rawItems = arr
                break
            }
            if let nested = json[key] as? [String: Any] {
                for subKey in candidateArrayKeys {
                    if let arr = nested[subKey] as? [[String: Any]] {
                        rawItems = arr
                        break
                    }
                }
                if !rawItems.isEmpty { break }
            }
        }

        if rawItems.isEmpty, let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            rawItems = root
        }

        let titleKeys = ["title", "name", "label", "full_name", "display_name"]
        let snippetKeys = ["description", "notes", "snippet", "abstract", "summary", "text"]
        let urlKeys = ["url", "link", "href", "html_url", "web_url", "source_url"]

        return rawItems.prefix(10).compactMap { item in
            let title = titleKeys.compactMap { item[$0] as? String }.first
            let snippet = snippetKeys.compactMap { item[$0] as? String }.first
            let urlString = urlKeys.compactMap { item[$0] as? String }.first

            guard let t = title, !t.isEmpty else { return nil }

            return FAEResultItem(
                id: UUID(),
                portalID: portalID,
                title: t,
                snippet: snippet.map { String($0.prefix(300)) },
                sourceURL: urlString.flatMap(URL.init(string:)),
                publicationDate: nil
            )
        }
    }

    // MARK: - Date Parsing

    private static func parseISO8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }()
    }
}
