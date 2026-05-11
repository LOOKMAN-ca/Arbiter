import Foundation

// MARK: - FAE API Type

enum FAEAPIType: String, Codable, Sendable {
    case ckan
    case rest
    case sparql
    case sdmx
    case geojson
    case wfs
    case csv
    case json
    case github
    case docIndex
}

// MARK: - Accuracy Tier
//
// Tier 1 (verified):  Government statistical authority or major international body.
// Tier 2 (academic):  Research infrastructure, university consortium, or specialized institute.
// Tier 3 (community): Community-run aggregator, NGO portal, or unverified source.

enum FAEAccuracyTier: Int, Codable, Comparable, Sendable {
    case verified  = 1
    case academic  = 2
    case community = 3

    nonisolated static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .verified:  return "TIER 1"
        case .academic:  return "TIER 2"
        case .community: return "TIER 3"
        }
    }

    var color: String {
        switch self {
        case .verified:  return "green"
        case .academic:  return "blue"
        case .community: return "orange"
        }
    }
}

// MARK: - Portal

struct FAEPortal: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let api: FAEAPIType
    let tier: FAEAccuracyTier
    let baseURL: URL
    let supportsHistorical: Bool
    let domains: Set<String>
}

// MARK: - Portal Registry
//
// Each entry has been evaluated against FAE v5.4 Python source.
// See FAE_Migration_Notes.md at repo root for drop/fix rationale.

extension FAEPortal {

    // swiftlint:disable function_body_length
    nonisolated static let registry: [FAEPortal] = {
        var portals: [FAEPortal] = []

        func add(_ id: String, _ name: String, _ api: FAEAPIType, _ tier: FAEAccuracyTier,
                 _ url: String, historical: Bool = false, domains: Set<String>) {
            guard let baseURL = URL(string: url) else { return }
            portals.append(FAEPortal(id: id, name: name, api: api, tier: tier,
                                     baseURL: baseURL, supportsHistorical: historical, domains: domains))
        }

        // --- ITALY: NATIONAL & GOV ---
        add("ITA_GOV", "dati.gov.it", .ckan, .verified,
            "https://www.dati.gov.it/opendata/api/3/action/package_search",
            domains: ["government", "general"])

        add("ITA_COE", "OpenCoesione", .rest, .verified,
            "https://opencoesione.gov.it/it/api/progetti/",
            domains: ["spending", "projects", "cohesion"])

        add("ITA_ANA", "BDNCP (ANAC)", .sparql, .verified,
            "https://dati.anticorruzione.it/sparql",
            domains: ["contracts", "procurement", "anticorruption"])

        add("ITA_IPA", "IndicePA", .ckan, .verified,
            "https://www.indicepa.gov.it/ipa-dati/api/3/action/package_search",
            domains: ["public-administration", "government"])

        add("ITA_PNRR", "Italia GitHub", .github, .verified,
            "https://api.github.com/search/repositories",
            domains: ["government", "digital", "open-source"])

        // --- STATISTICS & DEMOGRAPHICS ---
        add("IST_DEM", "ISTAT Demo", .rest, .verified,
            "https://demo.istat.it/api/v1/",
            historical: true,
            domains: ["demographics", "population", "statistics"])

        add("IST_STA", "I.Stat (SDMX)", .sdmx, .verified,
            "https://sdmx.istat.it/SDMXWS/rest/data/",
            historical: true,
            domains: ["statistics", "economics", "demographics", "labor", "health"])

        add("EUR_ITA", "Eurostat (SDMX)", .sdmx, .verified,
            "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/",
            historical: true,
            domains: ["statistics", "economics", "demographics", "eu"])

        add("ITA_INP", "INPS Open Data", .rest, .verified,
            "https://serviziweb2.inps.it/odapi/search",
            domains: ["labor", "social-security", "pensions"])

        // --- RESEARCH & SCIENCE ---
        add("SCI_ZEN", "Zenodo", .rest, .academic,
            "https://zenodo.org/api/records",
            domains: ["research", "science"])

        add("SCI_WBD", "World Bank Open Data", .rest, .verified,
            "https://api.worldbank.org/v2/indicator",
            historical: true,
            domains: ["economics", "development", "statistics"])

        add("SCI_AIR", "OpenAIRE", .rest, .verified,
            "https://api.openaire.eu/search/researchProducts",
            domains: ["research", "science", "publications"])

        // --- REGIONAL OPEN DATA ---
        add("REG_LOM", "Lombardia Open Data", .ckan, .verified,
            "https://dati.lombardia.it/api/3/action/package_search",
            domains: ["regional", "lombardia"])

        add("REG_TOS", "Toscana Open Data", .ckan, .verified,
            "https://dati.toscana.it/api/3/action/package_search",
            domains: ["regional", "toscana"])

        add("REG_LAZ", "Lazio Open Data", .ckan, .verified,
            "https://dati.lazio.it/catalog/api/3/action/package_search",
            domains: ["regional", "lazio"])

        add("REG_PIE", "Piemonte Dati Aperti", .ckan, .verified,
            "https://www.dati.piemonte.it/api/3/action/package_search",
            domains: ["regional", "piemonte"])

        add("REG_EMI", "Emilia-Romagna Open Data", .ckan, .verified,
            "https://dati.emilia-romagna.it/api/3/action/package_search",
            domains: ["regional", "emilia-romagna"])

        add("SAR_OD", "Sardegna Open Data", .ckan, .verified,
            "https://opendata.regione.sardegna.it/api/3/action/package_search",
            domains: ["regional", "sardinia"])

        // --- INTERNATIONAL ---
        add("AFR_HDX", "OCHA HDX", .ckan, .verified,
            "https://data.humdata.org/api/3/action/package_search",
            domains: ["humanitarian", "development", "africa"])

        add("AFR_HUB", "openAFRICA", .ckan, .community,
            "https://africaopendata.org/api/3/action/package_search",
            domains: ["africa", "general"])

        add("MEA_KSA", "Saudi Open Data", .ckan, .verified,
            "https://open.data.gov.sa/en/api/3/action/package_search",
            domains: ["government", "saudi-arabia"])

        add("MED_EMO", "EMODnet", .rest, .verified,
            "https://emodnet.ec.europa.eu/geonetwork/srv/api/search",
            domains: ["environment", "maritime", "mediterranean"])

        return portals
    }()
    // swiftlint:enable function_body_length
}
