import Foundation
import os

// MARK: - FAE Engine (Planner)
//
// Pure planning logic. No networking. Transforms a user topic into
// a set of typed query plans ready for execution by FAEFetcher.

enum FAEEngine {

    private nonisolated static let logger = Logger(subsystem: "com.LOOKMAN.Arbiter", category: "FAEEngine")

    // MARK: - Semantic Mesh Entry

    private struct MeshEntry {
        let keywords: [String]
        let domains: Set<String>
    }

    // Bilingual (IT + EN) semantic mesh.
    // Both English and Italian terms trigger the same entry, fixing
    // the Python source's unidirectional coverage gap.
    private nonisolated static let semanticMesh: [MeshEntry] = [
        MeshEntry(
            keywords: ["healthcare", "sanità", "salute", "medicina", "health", "medical",
                       "FSE", "fascicolo sanitario", "ospedale", "hospital"],
            domains: ["health", "statistics"]
        ),
        MeshEntry(
            keywords: ["spending", "bilancio", "finanza", "spesa pubblica", "fondi",
                       "budget", "finance", "SIOPE", "spesa"],
            domains: ["spending", "economics", "government"]
        ),
        MeshEntry(
            keywords: ["environment", "clima", "ecologia", "transizione ecologica",
                       "green deal", "ambiente", "climate", "ecology"],
            domains: ["environment"]
        ),
        MeshEntry(
            keywords: ["labor", "occupazione", "disoccupazione", "CCNL", "lavoro",
                       "impiego", "employment", "unemployment", "jobs", "workforce"],
            domains: ["labor", "statistics"]
        ),
        MeshEntry(
            keywords: ["innovation", "innovazione sociale", "startup",
                       "trasformazione digitale", "AI", "digitale", "digital"],
            domains: ["digital", "government"]
        ),
        MeshEntry(
            keywords: ["demographics", "residenti", "censimento", "popolazione",
                       "natalità", "mortalità", "population", "census",
                       "birth rate", "death rate", "abitanti"],
            domains: ["demographics", "population", "statistics"]
        ),
        MeshEntry(
            keywords: ["media", "pluralismo", "disinformazione", "fake news",
                       "broadband", "comunicazione", "communication", "journalism"],
            domains: ["media"]
        ),
        MeshEntry(
            keywords: ["sardinia", "sardegna", "cagliari", "sassari", "nuoro",
                       "oristano", "agro-pastorale", "insularità"],
            domains: ["sardinia", "regional"]
        ),
        MeshEntry(
            keywords: ["lombardia", "lombardy", "milano", "milan", "brescia", "bergamo"],
            domains: ["lombardia", "regional"]
        ),
        MeshEntry(
            keywords: ["toscana", "tuscany", "firenze", "florence", "pisa", "siena"],
            domains: ["toscana", "regional"]
        ),
        MeshEntry(
            keywords: ["lazio", "roma", "rome", "viterbo", "latina"],
            domains: ["lazio", "regional"]
        ),
        MeshEntry(
            keywords: ["piemonte", "piedmont", "torino", "turin"],
            domains: ["piemonte", "regional"]
        ),
        MeshEntry(
            keywords: ["emilia-romagna", "emilia", "romagna", "bologna", "modena", "parma"],
            domains: ["emilia-romagna", "regional"]
        ),
        MeshEntry(
            keywords: ["contracts", "appalti", "bandi", "gare", "procurement",
                       "contratti pubblici", "public contracts"],
            domains: ["contracts", "procurement", "government"]
        ),
        MeshEntry(
            keywords: ["education", "istruzione", "scuola", "università",
                       "school", "university", "formazione"],
            domains: ["education", "statistics"]
        ),
        MeshEntry(
            keywords: ["africa", "humanitarian", "development", "umanitario", "sviluppo"],
            domains: ["humanitarian", "development", "africa"]
        ),
        MeshEntry(
            keywords: ["research", "ricerca", "science", "scienza", "publications", "pubblicazioni"],
            domains: ["research", "science", "publications"]
        ),
        MeshEntry(
            keywords: ["economy", "economia", "GDP", "PIL", "trade", "commercio",
                       "export", "import", "esportazioni", "importazioni"],
            domains: ["economics", "statistics"]
        ),
        MeshEntry(
            keywords: ["maritime", "mare", "sea", "ocean", "oceano", "coast", "costa",
                       "mediterranean", "mediterraneo"],
            domains: ["environment", "maritime", "mediterranean"]
        ),
    ]

    // MARK: - Topic Expansion

    /// Expands a user topic into keywords and inferred domains using
    /// the bilingual semantic mesh and temporal detection.
    nonisolated static func expand(topic: String) -> FAEExpandedTopic {
        let lower = topic.lowercased()
        var keywords = Set<String>([topic])
        var domains = Set<String>()

        for entry in semanticMesh {
            let matched = entry.keywords.contains { kw in
                lower.contains(kw.lowercased())
            }
            if matched {
                keywords.formUnion(entry.keywords)
                domains.formUnion(entry.domains)
            }
        }

        let mode = detectTemporalMode(topic: topic, lower: lower)

        if mode == .historical {
            keywords.insert("serie storica")
            keywords.insert("time series")
        } else {
            if lower.contains("government") || lower.contains("spending") || lower.contains("pa") ||
               lower.contains("governo") || lower.contains("spesa") {
                keywords.insert("PNRR 2026")
            }
        }

        let dedupedKeywords = Array(keywords).sorted()
        logger.debug("Expanded '\(topic)' → \(dedupedKeywords.count) keywords, \(domains.count) domains, mode=\(mode.rawValue)")

        return FAEExpandedTopic(
            originalTopic: topic,
            keywords: dedupedKeywords,
            mode: mode,
            inferredDomains: domains
        )
    }

    // MARK: - Plan Generation

    /// Produces typed query plans for each relevant portal.
    nonisolated static func plan(
        expanded: FAEExpandedTopic,
        portals: [FAEPortal] = FAEPortal.registry,
        strictAccuracy: Bool
    ) -> [FAEQueryPlan] {
        var plans: [FAEQueryPlan] = []
        let topicKeywords = limitKeywords(expanded.keywords, max: 5)

        for portal in portals {
            if strictAccuracy && portal.tier != .verified { continue }

            if strictAccuracy && !portal.domains.intersection(expanded.inferredDomains).isEmpty == false {
                let isGeneralist = portal.domains.contains("general") || portal.domains.contains("government")
                if !isGeneralist { continue }
            }

            for kw in topicKeywords {
                guard let endpoint = buildEndpoint(portal: portal, keyword: kw, mode: expanded.mode) else {
                    continue
                }
                plans.append(FAEQueryPlan(
                    id: UUID(),
                    portal: portal,
                    term: kw,
                    mode: expanded.mode,
                    endpoint: endpoint
                ))
            }
        }

        logger.debug("Generated \(plans.count) query plans across \(Set(plans.map(\.portal.id)).count) portals")
        return plans
    }

    // MARK: - SPARQL Escaping

    /// Escapes a string for safe inclusion in a SPARQL literal.
    /// Fixes the injection vulnerability in the Python source that
    /// interpolated raw user input into SPARQL queries.
    nonisolated static func escapeSPARQLLiteral(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return escaped
    }

    // MARK: - Private Helpers

    /// Stricter temporal detection than the Python source's loose year regex.
    /// Requires contextual cues rather than matching any 4-digit number.
    private nonisolated static func detectTemporalMode(topic: String, lower: String) -> FAEMode {
        let temporalKeywords = [
            "history", "trend", "past", "historical", "series", "evolution",
            "storia", "serie storica", "storico", "tendenza", "andamento",
            "evoluzione", "time series"
        ]

        if temporalKeywords.contains(where: { lower.contains($0) }) {
            return .historical
        }

        // Year with contextual preposition (EN/IT)
        let contextualYear = #"(?:since|from|dal|dopo|in|nel|before|fino|until|prima|tra|between)\s+((?:19|20)\d{2})"#
        if lower.range(of: contextualYear, options: .regularExpression) != nil {
            return .historical
        }

        // Year range: 2000-2024
        let yearRange = #"(19|20)\d{2}\s*[-–]\s*(19|20)\d{2}"#
        if lower.range(of: yearRange, options: .regularExpression) != nil {
            return .historical
        }

        return .currentSnapshot
    }

    /// Caps keywords to avoid query explosion across many portals.
    private nonisolated static func limitKeywords(_ keywords: [String], max: Int) -> [String] {
        if keywords.count <= max { return keywords }
        return Array(keywords.prefix(max))
    }

    /// Builds the API endpoint URL for a given portal, keyword, and mode.
    /// Uses URLComponents for safe percent-encoding — never string concatenation.
    private nonisolated static func buildEndpoint(portal: FAEPortal, keyword: String, mode: FAEMode) -> URL? {
        switch portal.api {
        case .ckan:
            return buildCKANEndpoint(portal: portal, keyword: keyword, mode: mode)
        case .rest:
            return buildRESTEndpoint(portal: portal, keyword: keyword)
        case .sparql:
            return buildSPARQLEndpoint(portal: portal, keyword: keyword)
        case .sdmx:
            return buildSDMXEndpoint(portal: portal)
        case .github:
            return buildGitHubEndpoint(portal: portal, keyword: keyword)
        case .geojson, .wfs, .csv, .json, .docIndex:
            return buildGenericEndpoint(portal: portal, keyword: keyword)
        }
    }

    private nonisolated static func buildCKANEndpoint(portal: FAEPortal, keyword: String, mode: FAEMode) -> URL? {
        var components = URLComponents(url: portal.baseURL, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "rows", value: "10"),
        ]
        if mode == .currentSnapshot {
            items.append(URLQueryItem(name: "sort", value: "metadata_modified desc"))
        }
        components?.queryItems = items
        return components?.url
    }

    private nonisolated static func buildRESTEndpoint(portal: FAEPortal, keyword: String) -> URL? {
        var components = URLComponents(url: portal.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: keyword)]
        return components?.url
    }

    private nonisolated static func buildSPARQLEndpoint(portal: FAEPortal, keyword: String) -> URL? {
        let escaped = escapeSPARQLLiteral(keyword)
        let query = """
        SELECT ?s ?p ?o WHERE { ?s ?p ?o . FILTER(CONTAINS(LCASE(STR(?o)), LCASE("\(escaped)"))) } LIMIT 10
        """
        var components = URLComponents(url: portal.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "format", value: "application/sparql-results+json"),
        ]
        return components?.url
    }

    private nonisolated static func buildSDMXEndpoint(portal: FAEPortal) -> URL? {
        var components = URLComponents(url: portal.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "detail", value: "full")]
        return components?.url
    }

    private nonisolated static func buildGitHubEndpoint(portal: FAEPortal, keyword: String) -> URL? {
        var components = URLComponents(url: portal.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: "org:italia \(keyword)"),
            URLQueryItem(name: "per_page", value: "10"),
        ]
        return components?.url
    }

    private nonisolated static func buildGenericEndpoint(portal: FAEPortal, keyword: String) -> URL? {
        var components = URLComponents(url: portal.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "search", value: keyword)]
        return components?.url
    }
}
