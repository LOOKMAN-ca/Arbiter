import Foundation

// MARK: - API Protocol
// Maps to the "type" field in fae_registry_v6.json.
// Unknown values fall back to .docIndex and are flagged for manual review.

public enum APIProtocol: String, Codable, Hashable, Sendable {
    case ckan     = "CKAN"
    case dkan     = "DKAN"
    case socrata  = "Socrata"
    case rest     = "REST"
    case sparql   = "SPARQL"
    case sdmx     = "SDMX"
    case oaiPmh   = "OAI-PMH"
    case geojson  = "GeoJSON"
    case wfs      = "WFS"
    case docIndex = "DOC_INDEX"
    case github   = "GITHUB"
    case graphql  = "GraphQL"
    case dcat     = "DCAT"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Forward-compatible: unknown types fall back to .docIndex
        self = APIProtocol(rawValue: raw) ?? .docIndex
    }

    /// Bridge to the legacy FAEAPIType for FAEEngine/FAEFetcher compatibility.
    nonisolated var legacyType: FAEAPIType {
        switch self {
        case .ckan:                    return .ckan
        case .dkan:                    return .ckan
        case .socrata:                 return .rest
        case .rest:                    return .rest
        case .sparql:                  return .sparql
        case .sdmx:                    return .sdmx
        case .geojson:                 return .geojson
        case .wfs:                     return .wfs
        case .github:                  return .github
        case .docIndex:                return .docIndex
        case .oaiPmh, .graphql, .dcat: return .rest
        }
    }
}

// MARK: - Auth Mode

public enum AuthMode: String, Codable, Hashable, Sendable {
    case none    = "none"
    case freeKey = "free_key"
    case paidKey = "paid_key"
    case oauth   = "oauth"

    nonisolated var isUsableWithoutConfig: Bool { self == .none || self == .freeKey }
}

// MARK: - Verification Label
// First three come from the JSON file (authoring-time labels).
// Last three are written back by FAEVerifier after live probing.

public enum VerificationLabel: String, Codable, Hashable, Sendable {
    case verifiedThisSession    = "verified_this_session"
    case documentedEndpoint     = "documented_endpoint"
    case confirmedExistenceOnly = "confirmed_existence_only"
    case verifiedLive           = "verified_live"    // set by FAEVerifier
    case probedFailed           = "probed_failed"    // set by FAEVerifier
    case probedDegraded         = "probed_degraded"  // set by FAEVerifier

    /// True if this label qualifies the entry for active-registry inclusion (§3.4).
    nonisolated var isActiveEligible: Bool {
        switch self {
        case .verifiedLive, .verifiedThisSession, .documentedEndpoint: return true
        default: return false
        }
    }

    nonisolated var displayLabel: String {
        switch self {
        case .verifiedLive:           return "LIVE"
        case .verifiedThisSession:    return "SESSION"
        case .documentedEndpoint:     return "DOCUMENTED"
        case .confirmedExistenceOnly: return "UNVERIFIED"
        case .probedFailed:           return "FAILED"
        case .probedDegraded:         return "DEGRADED"
        }
    }
}

// MARK: - Portal Entry
// Raw decoded form of a single fae_registry_v6.json entry.
// Mutable harness fields (verification, lastChecked, etc.) are set by FAEVerifier
// and persisted to fae_registry_v6.verified.json.

public struct PortalEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let type: APIProtocol
    public let acc: Int
    public let url: URL
    public let lang: [String]
    public let region: String
    public let domains: [String]
    public let license: String
    public let historical: Bool
    public let auth: AuthMode
    public var verification: VerificationLabel

    /// HTTP status code from last probe (nil = not yet probed).
    public var lastStatus: Int?
    /// ISO 8601 timestamp of the most recent probe.
    public var lastChecked: Date?
    /// Human-readable note from the most recent probe.
    public var lastNote: String?
    /// Incremented on each failure; reset to 0 on success. Active-registry gate: < 3 (§2.8).
    public var consecutiveFailures: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, acc, url, lang, region, domains
        case license, historical, auth, verification
        case lastStatus          = "last_status"
        case lastChecked         = "last_checked"
        case lastNote            = "last_note"
        case consecutiveFailures = "consecutive_failures"
    }

    public nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        name         = try c.decode(String.self, forKey: .name)
        type         = try c.decode(APIProtocol.self, forKey: .type)
        acc          = try c.decode(Int.self, forKey: .acc)
        let rawURL   = try c.decode(String.self, forKey: .url)
        guard let parsed = URL(string: rawURL) else {
            throw DecodingError.dataCorruptedError(
                forKey: .url, in: c, debugDescription: "Malformed URL: \(rawURL)")
        }
        url          = parsed
        lang         = (try? c.decode([String].self, forKey: .lang))       ?? ["en"]
        region       = try c.decode(String.self, forKey: .region)
        domains      = try c.decode([String].self, forKey: .domains)
        license      = (try? c.decode(String.self, forKey: .license))      ?? "unknown"
        historical   = (try? c.decode(Bool.self, forKey: .historical))     ?? false
        auth         = (try? c.decode(AuthMode.self, forKey: .auth))       ?? .none
        verification = try c.decode(VerificationLabel.self, forKey: .verification)
        lastStatus   = try? c.decodeIfPresent(Int.self,    forKey: .lastStatus)
        lastChecked  = try? c.decodeIfPresent(Date.self,   forKey: .lastChecked)
        lastNote     = try? c.decodeIfPresent(String.self, forKey: .lastNote)
        consecutiveFailures = try? c.decodeIfPresent(Int.self, forKey: .consecutiveFailures)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                 forKey: .id)
        try c.encode(name,               forKey: .name)
        try c.encode(type,               forKey: .type)
        try c.encode(acc,                forKey: .acc)
        try c.encode(url.absoluteString, forKey: .url)
        try c.encode(lang,               forKey: .lang)
        try c.encode(region,             forKey: .region)
        try c.encode(domains,            forKey: .domains)
        try c.encode(license,            forKey: .license)
        try c.encode(historical,         forKey: .historical)
        try c.encode(auth,               forKey: .auth)
        try c.encode(verification,       forKey: .verification)
        try c.encodeIfPresent(lastStatus,          forKey: .lastStatus)
        try c.encodeIfPresent(lastChecked,         forKey: .lastChecked)
        try c.encodeIfPresent(lastNote,            forKey: .lastNote)
        try c.encodeIfPresent(consecutiveFailures, forKey: .consecutiveFailures)
    }

    // Identity-based equality and hashing (by id) for Set/Dictionary use.
    public static func == (lhs: PortalEntry, rhs: PortalEntry) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - PortalEntry convenience

extension PortalEntry {
    nonisolated var tier: FAEAccuracyTier {
        FAEAccuracyTier(rawValue: acc) ?? .community
    }

    /// Converts to the legacy FAEPortal type consumed by FAEEngine and FAEFetcher.
    nonisolated var asFAEPortal: FAEPortal {
        FAEPortal(
            id: id,
            name: name,
            api: type.legacyType,
            tier: tier,
            baseURL: url,
            supportsHistorical: historical,
            domains: Set(domains)
        )
    }
}

// MARK: - Registry Error

enum FAERegistryError: LocalizedError {
    case resourceNotFound
    case cannotDetermineAppSupport
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            return "fae_registry_v6.json not found in bundle or override path"
        case .cannotDetermineAppSupport:
            return "Cannot determine Application Support directory"
        case .decodingFailed(let msg):
            return "Registry decoding failed: \(msg)"
        }
    }
}
