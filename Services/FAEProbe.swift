import Foundation
import os

private let probeLogger = Logger(subsystem: "com.LOOKMAN.Arbiter", category: "FAEProbe")

// MARK: - Probe Outcome

enum ProbeOutcome: Sendable {
    case live(httpStatus: Int, shapeOK: Bool, sample: String)
    case degraded(reason: String)
    case dead(reason: String)
    case requiresAuth
    case skipped(reason: String)

    /// Maps to the VerificationLabel that FAEVerifier writes back into the entry.
    nonisolated var verificationLabel: VerificationLabel {
        switch self {
        case .live(_, true, _):  return .verifiedLive
        case .live(_, false, _): return .probedDegraded
        case .degraded:          return .probedDegraded
        case .dead:              return .probedFailed
        // 401/403 means the server is alive but auth-gated; degrade rather than fail.
        case .requiresAuth:      return .probedDegraded
        case .skipped:           return .documentedEndpoint  // existing label preserved by FAEVerifier
        }
    }

    /// Whether the verifier should update entry.verification for this outcome.
    nonisolated var shouldUpdateLabel: Bool {
        if case .skipped = self { return false }
        return true
    }

    nonisolated var note: String? {
        switch self {
        case .live(let s, let ok, let sample):
            return ok ? "HTTP \(s) — shape OK" : "HTTP \(s) — shape mismatch: \(sample)"
        case .degraded(let r): return "Degraded: \(r)"
        case .dead(let r):     return r
        case .requiresAuth:    return "Auth required but entry declares auth: none"
        case .skipped(let r):  return "Skipped: \(r)"
        }
    }

    nonisolated var httpStatus: Int? {
        if case .live(let s, _, _) = self { return s }
        return nil
    }
}

// MARK: - Shared Session Factory

enum FAEProbeSession {
    // Polite identification raises anonymous rate limits for Crossref, OpenAlex, GitHub (§3.2).
    nonisolated static var userAgent: String {
        "Arbiter-FAE/1.0 (+https://github.com/LOOKMAN-ca/Arbiter)"
    }

    nonisolated static func make() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 8   // connect timeout
        cfg.timeoutIntervalForResource = 12  // total timeout
        cfg.requestCachePolicy         = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache                   = nil
        cfg.httpAdditionalHeaders      = ["User-Agent": userAgent]
        return URLSession(configuration: cfg)
    }
}

// MARK: - Probe Dispatcher
// One static method per APIProtocol value. Accepts a shared URLSession so the
// caller (FAEVerifier) controls session lifecycle; tests inject a mock session.

enum ProbeDispatcher {

    nonisolated static func probe(_ entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        // Auth gate: skip paid/oauth portals when no credentials are configured.
        if entry.auth == .paidKey || entry.auth == .oauth {
            return .skipped(reason: "requires \(entry.auth.rawValue) credentials — not configured")
        }

        switch entry.type {
        case .ckan:     return await probeCKAN(entry: entry, session: session)
        case .dkan:     return await probeDKAN(entry: entry, session: session)
        case .socrata:  return await probeSocrata(entry: entry, session: session)
        case .sdmx:     return await probeSDMX(entry: entry, session: session)
        case .sparql:   return await probeSPARQL(entry: entry, session: session)
        case .oaiPmh:   return await probeOAIPMH(entry: entry, session: session)
        case .wfs:      return await probeWFS(entry: entry, session: session)
        case .geojson:  return await probeGeoJSON(entry: entry, session: session)
        case .docIndex: return await probeDocIndex(entry: entry, session: session)
        case .github:   return await probeGitHub(entry: entry, session: session)
        case .graphql:  return await probeGraphQL(entry: entry, session: session)
        case .dcat:     return await probeDCAT(entry: entry, session: session)
        case .rest:     return await probeREST(entry: entry, session: session)
        }
    }

    // MARK: - CKAN
    // GET {url}?q=*:*&rows=0 (append /api/3/action/package_search if not already present)
    // rows=0 with wildcard returns the success envelope without fetching any records,
    // which is less likely to trigger WAF blocks than a keyword search with results.
    // Shape: success:true AND result.results array

    private static func probeCKAN(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        var base = entry.url
        if !base.path.contains("package_search") {
            base = base.appendingPathComponent("api/3/action/package_search")
        }
        guard let url = url(base, queryItems: [qi("q", "*:*"), qi("rows", "0")]) else {
            return .dead(reason: "invalid URL construction")
        }
        return await fetchAndCheck(url: url, session: session, accept: "application/json") { data, status in
            guard let json = parseJSON(data) as? [String: Any],
                  let success = json["success"] as? Bool, success,
                  let result  = json["result"] as? [String: Any],
                  result["results"] != nil
            else {
                return (false, preview(data))
            }
            return (true, "CKAN \(status)")
        }
    }

    // MARK: - DKAN
    // GET {url}/api/3/action/package_search?q=*:*&limit=0
    // Same wildcard+zero-rows strategy as CKAN to avoid WAF fingerprinting.
    // Shape: same as CKAN

    private static func probeDKAN(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        let base = entry.url.appendingPathComponent("api/3/action/package_search")
        guard let url = url(base, queryItems: [qi("q", "*:*"), qi("limit", "0")]) else {
            return .dead(reason: "invalid URL construction")
        }
        return await fetchAndCheck(url: url, session: session, accept: "application/json") { data, status in
            guard let json = parseJSON(data) as? [String: Any],
                  let success = json["success"] as? Bool, success,
                  let result  = json["result"] as? [String: Any],
                  result["results"] != nil
            else {
                return (false, preview(data))
            }
            return (true, "DKAN \(status)")
        }
    }

    // MARK: - Socrata
    // GET {url}.json?$limit=1 (strip trailing slash, append .json)
    // Shape: top-level JSON array, no "error" key

    private static func probeSocrata(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        var urlStr = entry.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        urlStr += ".json"
        guard var components = URLComponents(string: urlStr) else {
            return .dead(reason: "invalid URL construction")
        }
        components.queryItems = [URLQueryItem(name: "$limit", value: "1")]
        guard let url = components.url else { return .dead(reason: "invalid URL construction") }

        return await fetchAndCheck(url: url, session: session, accept: "application/json") { data, status in
            // Accept top-level array with no "error" key
            if let arr = parseJSON(data) as? [[String: Any]] {
                return (true, "Socrata \(status) (\(arr.count) records)")
            }
            if let obj = parseJSON(data) as? [String: Any], obj["error"] != nil {
                return (false, "Socrata error field present: \(preview(data))")
            }
            return (false, preview(data))
        }
    }

    // MARK: - SDMX
    // GET {serviceRoot}/  Accept: application/vnd.sdmx.structure+xml;version=2.1
    // Navigate to the service root (strip any trailing "data" path segment) and request
    // the structure/dataflow catalogue — small XML response, avoids fetching actual data
    // which can be enormous and is what triggers timeouts and WAF blocks.
    // Shape: XML containing Structure, DataFlow, Header, or CompactData elements.

    private static func probeSDMX(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        var components = URLComponents(url: entry.url, resolvingAgainstBaseURL: false)
        var path = components?.path ?? ""
        // Strip trailing "data" path segment to reach the service root
        for suffix in ["/data/", "/data"] where path.hasSuffix(suffix) {
            path = String(path.dropLast(suffix.count))
        }
        if !path.hasSuffix("/") { path += "/" }
        components?.path = path
        let probeURL = components?.url ?? entry.url

        let accept = "application/vnd.sdmx.structure+xml;version=2.1, application/xml;q=0.9"
        return await fetchAndCheck(url: probeURL, session: session, accept: accept) { data, status in
            let text = String(data: data.prefix(1000), encoding: .utf8) ?? ""
            if text.lowercased().contains("<html") {
                return (false, "HTML response — not an SDMX endpoint")
            }
            if text.contains("Structure") || text.contains("DataFlow") || text.contains("Dataflow")
                || text.contains("Header") || text.contains("<?xml") || text.contains("<CompactData") {
                return (true, "SDMX \(status)")
            }
            if parseJSON(data) != nil {
                return (true, "SDMX \(status) (JSON)")
            }
            return (false, preview(data))
        }
    }

    // MARK: - SPARQL
    // GET {url}?query=SELECT * WHERE {} LIMIT 1&format=json
    // Empty graph pattern {} returns a single empty solution in ~0ms on any triplestore;
    // ?s ?p ?o requires a full-graph scan and can time out on large datasets.
    // Shape: JSON with "head" and "results.bindings"

    private static func probeSPARQL(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        let sparqlQuery = "SELECT * WHERE {} LIMIT 1"
        guard let url = url(entry.url, queryItems: [qi("query", sparqlQuery), qi("format", "json")]) else {
            return .dead(reason: "invalid URL construction")
        }
        return await fetchAndCheck(url: url, session: session, accept: "application/sparql-results+json") { data, status in
            guard let json = parseJSON(data) as? [String: Any],
                  json["head"] != nil,
                  let results = json["results"] as? [String: Any],
                  results["bindings"] != nil
            else {
                return (false, preview(data))
            }
            return (true, "SPARQL \(status)")
        }
    }

    // MARK: - OAI-PMH
    // GET {url}?verb=Identify
    // Shape: XML containing OAI-PMH namespace

    private static func probeOAIPMH(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        guard let url = url(entry.url, queryItems: [qi("verb", "Identify")]) else {
            return .dead(reason: "invalid URL construction")
        }
        return await fetchAndCheck(url: url, session: session, accept: "application/xml, text/xml") { data, status in
            let text = String(data: data.prefix(2000), encoding: .utf8) ?? ""
            if text.contains("OAI-PMH") {
                return (true, "OAI-PMH \(status)")
            }
            return (false, preview(data))
        }
    }

    // MARK: - WFS
    // GET {url}?SERVICE=WFS&REQUEST=GetCapabilities
    // Shape: XML with WFS_Capabilities

    private static func probeWFS(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        guard let url = url(entry.url, queryItems: [qi("SERVICE", "WFS"), qi("REQUEST", "GetCapabilities")]) else {
            return .dead(reason: "invalid URL construction")
        }
        return await fetchAndCheck(url: url, session: session, accept: "application/xml, text/xml") { data, status in
            let text = String(data: data.prefix(2000), encoding: .utf8) ?? ""
            if text.contains("WFS_Capabilities") || text.contains("wfs:WFS_Capabilities") {
                return (true, "WFS \(status)")
            }
            return (false, preview(data))
        }
    }

    // MARK: - GeoJSON
    // GET {url}?limit=1 — fetch one feature to confirm shape without downloading a full dataset

    private static func probeGeoJSON(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        guard let url = url(entry.url, queryItems: [qi("limit", "1")]) else {
            return .dead(reason: "invalid URL construction")
        }
        return await fetchAndCheck(url: url, session: session, accept: "application/geo+json, application/json") { data, status in
            if let json = parseJSON(data) as? [String: Any] {
                let ftype = json["type"] as? String
                if ftype == "FeatureCollection" || ftype == "Feature" {
                    return (true, "GeoJSON \(status)")
                }
                return (false, "JSON but not GeoJSON: \(preview(data))")
            }
            return (false, preview(data))
        }
    }

    // MARK: - DOC_INDEX
    // HEAD {url}; fall back to GET on 405. 2xx/3xx passes; HTML is acceptable.

    private static func probeDocIndex(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        var req = request(url: entry.url, method: "HEAD", accept: "text/html, */*")
        do {
            let (_, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 405 {
                    // Retry with GET
                    req = request(url: entry.url, method: "GET", accept: "text/html, */*")
                    let (_, r2) = try await session.data(for: req)
                    if let h2 = r2 as? HTTPURLResponse {
                        return (200...399).contains(h2.statusCode)
                            ? .live(httpStatus: h2.statusCode, shapeOK: true, sample: "DOC_INDEX GET \(h2.statusCode)")
                            : httpError(h2.statusCode, entry: entry)
                    }
                }
                return (200...399).contains(http.statusCode)
                    ? .live(httpStatus: http.statusCode, shapeOK: true, sample: "DOC_INDEX HEAD \(http.statusCode)")
                    : httpError(http.statusCode, entry: entry)
            }
            return .dead(reason: "non-HTTP response")
        } catch {
            return mapURLError(error, canRetry: false, entry: entry)
        }
    }

    // MARK: - GITHUB
    // GET {url} — JSON response with X-GitHub-Api-Version header (required since 2022-11-28)
    // Omitting the version header causes some GitHub API routes to return 406 or redirect to HTML.

    private static func probeGitHub(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        var components = URLComponents(url: entry.url, resolvingAgainstBaseURL: false) ?? URLComponents()
        if components.queryItems == nil {
            components.queryItems = [qi("q", "test"), qi("per_page", "1")]
        }
        let probeURL = components.url ?? entry.url
        var req = request(url: probeURL, method: "GET", accept: "application/vnd.github+json")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        do {
            let (data, response) = try await withRetry { try await session.data(for: req) }
            guard let http = response as? HTTPURLResponse else { return .dead(reason: "non-HTTP response") }
            if http.statusCode == 401 || http.statusCode == 403 { return .requiresAuth }
            guard (200...299).contains(http.statusCode) else { return httpError(http.statusCode, entry: entry) }
            let clean = stripBOM(data)
            if parseJSON(clean) != nil {
                return .live(httpStatus: http.statusCode, shapeOK: true, sample: "GitHub \(http.statusCode)")
            }
            return .live(httpStatus: http.statusCode, shapeOK: false, sample: preview(clean))
        } catch {
            return mapURLError(error, canRetry: false, entry: entry)
        }
    }

    // MARK: - GraphQL
    // POST {url} introspection query
    // Shape: JSON with data.__schema

    private static func probeGraphQL(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        let body = #"{"query":"{ __schema { queryType { name } } }"}"#
        guard let bodyData = body.data(using: .utf8) else {
            return .dead(reason: "failed to encode GraphQL body")
        }
        var req = request(url: entry.url, method: "POST", accept: "application/json")
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await withRetry { try await session.data(for: req) }
            guard let http = response as? HTTPURLResponse else { return .dead(reason: "non-HTTP response") }
            if http.statusCode == 401 || http.statusCode == 403 { return .requiresAuth }
            guard (200...299).contains(http.statusCode) else { return httpError(http.statusCode, entry: entry) }

            guard let json = parseJSON(data) as? [String: Any],
                  let data_  = json["data"] as? [String: Any],
                  data_["__schema"] != nil
            else {
                return .live(httpStatus: http.statusCode, shapeOK: false, sample: preview(data))
            }
            return .live(httpStatus: http.statusCode, shapeOK: true, sample: "GraphQL introspection OK")
        } catch {
            return mapURLError(error, canRetry: false, entry: entry)
        }
    }

    // MARK: - DCAT
    // GET {url} Accept: application/ld+json
    // Shape: JSON-LD with @context key

    private static func probeDCAT(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        return await fetchAndCheck(url: entry.url, session: session,
                                   accept: "application/ld+json, application/json") { data, status in
            if let json = parseJSON(data) as? [String: Any], json["@context"] != nil {
                return (true, "DCAT JSON-LD \(status)")
            }
            // Accept plain JSON too — many DCAT catalogs omit @context at root
            if parseJSON(data) != nil {
                return (false, "JSON but missing @context — may not be DCAT")
            }
            return (false, preview(data))
        }
    }

    // MARK: - REST (generic)
    // GET {url} — check content-type is JSON or XML; HTML → degraded

    private static func probeREST(entry: PortalEntry, session: URLSession) async -> ProbeOutcome {
        return await fetchAndCheck(url: entry.url, session: session, accept: "application/json, application/xml;q=0.9, */*;q=0.1") { data, status in
            let text = String(data: data.prefix(500), encoding: .utf8) ?? ""
            if text.lowercased().hasPrefix("<!doctype html") || text.lowercased().hasPrefix("<html") {
                return (false, "HTML response — likely a web page, not a REST API")
            }
            if parseJSON(data) != nil || text.hasPrefix("<?xml") || text.hasPrefix("<") {
                return (true, "REST \(status)")
            }
            return (false, preview(data))
        }
    }

    // MARK: - Shared Helpers

    private static func fetchAndCheck(
        url: URL,
        session: URLSession,
        accept: String,
        shapeCheck: @Sendable (Data, Int) -> (ok: Bool, sample: String)
    ) async -> ProbeOutcome {
        let req = request(url: url, method: "GET", accept: accept)
        do {
            let (data, response) = try await withRetry { try await session.data(for: req) }
            guard let http = response as? HTTPURLResponse else { return .dead(reason: "non-HTTP response") }
            if http.statusCode == 401 || http.statusCode == 403 { return .requiresAuth }
            guard (200...299).contains(http.statusCode) else { return httpError(http.statusCode, entry: nil) }
            let clean = stripBOM(data)
            let (ok, sample) = shapeCheck(clean, http.statusCode)
            return .live(httpStatus: http.statusCode, shapeOK: ok, sample: sample)
        } catch {
            return mapURLError(error, canRetry: false, entry: nil)
        }
    }

    private static func request(url: URL, method: String, accept: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(FAEProbeSession.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        return req
    }

    private static func url(_ base: URL, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url
    }

    private static func qi(_ name: String, _ value: String) -> URLQueryItem {
        URLQueryItem(name: name, value: value)
    }

    private static func parseJSON(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    private static func preview(_ data: Data) -> String {
        let raw = String(data: data.prefix(120), encoding: .utf8)
            ?? String(data: data.prefix(120), encoding: .isoLatin1)
            ?? "(binary)"
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripBOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3 && data.prefix(3).elementsEqual(bom) { return data.dropFirst(3) }
        return data
    }

    private static func httpError(_ status: Int, entry: PortalEntry?) -> ProbeOutcome {
        switch status {
        case 401, 403: return .requiresAuth
        case 404:      return .dead(reason: "HTTP 404 — endpoint not found")
        case 429:      return .dead(reason: "HTTP 429 — rate limited")
        case 500...599: return .dead(reason: "HTTP \(status) — server error")
        default:       return .dead(reason: "HTTP \(status)")
        }
    }

    private static func mapURLError(_ error: Error, canRetry: Bool, entry: PortalEntry?) -> ProbeOutcome {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .appTransportSecurityRequiresSecureConnection:
                return .dead(reason: "HTTP endpoint blocked by ATS — use HTTPS")
            case .timedOut:
                return .dead(reason: "timed out (>12s)")
            case .cannotFindHost, .dnsLookupFailed:
                return .dead(reason: "DNS failure: \(urlError.failingURL?.host() ?? "unknown host")")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return .dead(reason: "TLS failure")
            default:
                return .dead(reason: urlError.localizedDescription)
            }
        }
        return .dead(reason: error.localizedDescription)
    }

    // One retry on connection-level errors (never on 4xx per §3.2).
    private static func withRetry<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                probeLogger.debug("Probe: retrying after \(urlError.code.rawValue)")
                return try await operation()
            default:
                throw urlError
            }
        }
    }
}
