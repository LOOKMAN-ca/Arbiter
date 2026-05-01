import Foundation
import os

// MARK: - Registry File Wrappers

private struct RegistryFile: Decodable {
    let registry: [PortalEntry]

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        registry = try c.decode([PortalEntry].self, forKey: .registry)
    }

    private enum CodingKeys: String, CodingKey { case registry }
}

private struct RegistryFileOutput: Encodable {
    let registry: [PortalEntry]

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(registry, forKey: .registry)
    }

    private enum CodingKeys: String, CodingKey { case registry }
}

// MARK: - FAE Registry Loader
//
// Loading priority (§2.3):
//   1. User-override JSON at ~/Library/Application Support/Arbiter/fae_registry_v6.json
//   2. Verified JSON written by FAEVerifier (fae_registry_v6.verified.json)
//   3. Bundled fae_registry_v6.json (source of truth, never mutated)
//
// §2.7 cadence: verification is triggered when the bundle's hash changes or
// when more than 14 days have elapsed since the last run (checked by FAEActiveRegistry).

enum FAERegistryLoader {

    nonisolated static let bundleResourceName    = "fae_registry_v6"
    nonisolated static let userOverrideFilename  = "fae_registry_v6.json"
    nonisolated static let verifiedFilename      = "fae_registry_v6.verified.json"
    nonisolated static let reportFilename        = "FAE_Verification_Report.md"

    private nonisolated static let logger = Logger(subsystem: "com.LOOKMAN.Arbiter", category: "FAERegistryLoader")

    // MARK: - Filesystem Paths

    nonisolated static var appSupportURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Arbiter")
    }

    nonisolated static var userOverrideURL: URL? {
        appSupportURL?.appendingPathComponent(userOverrideFilename)
    }

    nonisolated static var verifiedFileURL: URL? {
        appSupportURL?.appendingPathComponent(verifiedFilename)
    }

    nonisolated static var reportFileURL: URL? {
        appSupportURL?.appendingPathComponent(reportFilename)
    }

    // MARK: - Load

    /// Loads entries following the priority chain described above.
    /// Always returns the full raw registry (no active-set filtering applied here).
    nonisolated static func load() throws -> [PortalEntry] {
        // 1. User override
        if let url = userOverrideURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let entries = try decode(from: url)
                logger.info("FAERegistryLoader: loaded \(entries.count) entries from user override")
                return entries
            } catch {
                logger.warning("FAERegistryLoader: user override malformed (\(error.localizedDescription)), falling back")
            }
        }

        // 2. Verified JSON (written by FAEVerifier)
        if let url = verifiedFileURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let entries = try decode(from: url)
                logger.info("FAERegistryLoader: loaded \(entries.count) entries from verified file")
                return entries
            } catch {
                logger.warning("FAERegistryLoader: verified file malformed (\(error.localizedDescription)), falling back to bundle")
            }
        }

        // 3. Bundled resource
        guard let bundleURL = Bundle.main.url(forResource: bundleResourceName, withExtension: "json") else {
            throw FAERegistryError.resourceNotFound
        }
        let entries = try decode(from: bundleURL)
        logger.info("FAERegistryLoader: loaded \(entries.count) entries from bundle")
        return entries
    }

    // MARK: - Save

    /// Persists the harness-augmented entries as the verified JSON.
    /// Called by FAEVerifier after a completed probe run.
    nonisolated static func saveVerified(_ entries: [PortalEntry]) throws {
        guard let url = verifiedFileURL else {
            throw FAERegistryError.cannotDetermineAppSupport
        }
        try ensureAppSupportDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(RegistryFileOutput(registry: entries))
        try data.write(to: url, options: .atomic)
        logger.info("FAERegistryLoader: saved \(entries.count) verified entries → \(url.path)")
    }

    /// Saves a verification report (Markdown) alongside the verified JSON.
    nonisolated static func saveReport(_ markdown: String) throws {
        guard let url = reportFileURL else {
            throw FAERegistryError.cannotDetermineAppSupport
        }
        try ensureAppSupportDirectory()
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        logger.info("FAERegistryLoader: saved report → \(url.path)")
    }

    // MARK: - Change Detection (§2.7)

    /// FNV-1a hash of the bundled JSON bytes.
    /// A changed hash triggers a new verification run even within the 14-day window.
    nonisolated static func bundleHash() -> String? {
        guard let url = Bundle.main.url(forResource: bundleResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    // MARK: - Private Helpers

    private nonisolated static func decode(from url: URL) throws -> [PortalEntry] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(RegistryFile.self, from: data).registry
        } catch {
            throw FAERegistryError.decodingFailed(error.localizedDescription)
        }
    }

    private nonisolated static func ensureAppSupportDirectory() throws {
        guard let dir = appSupportURL else {
            throw FAERegistryError.cannotDetermineAppSupport
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
