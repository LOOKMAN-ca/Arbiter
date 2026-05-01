import Foundation
import SwiftUI

// MARK: — Central Command Logic
enum ArbiterVoiceCommand: Equatable { case execute, abort, validate, none }

struct ModelOption: Identifiable {
    let id: String
    let label: String
}

// MARK: — Model Catalog
// Single source of truth for available models. Update IDs here when new versions release.
enum ModelCatalog {
    nonisolated static let claude: [ModelOption] = [
        ModelOption(id: "claude-sonnet-4-5-20250514", label: "Claude Sonnet 4.5"),
        ModelOption(id: "claude-3-5-sonnet-20241022", label: "Claude 3.5 Sonnet"),
        ModelOption(id: "claude-3-5-haiku-20241022",  label: "Claude 3.5 Haiku"),
    ]

    nonisolated static let gemini: [ModelOption] = [
        ModelOption(id: "gemini-2.5-flash-preview-04-17", label: "Gemini 2.5 Flash"),
        ModelOption(id: "gemini-2.0-flash",               label: "Gemini 2.0 Flash"),
        ModelOption(id: "gemini-1.5-pro",                 label: "Gemini 1.5 Pro"),
    ]
}

// MARK: — Pipeline Enums
enum PipelineMode: String, CaseIterable, Identifiable {
    case sequential, iterative
    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
    var description: String {
        switch self {
        case .sequential: return "3-pass: Claude drafts → Gemini critiques → Claude synthesizes."
        case .iterative:  return "N-loop: Claude drafts, then Gemini/Claude alternate revisions."
        }
    }
}

enum PipelinePhase: Equatable {
    case idle, validating, validated, running, done, aborted, error(String)
    var displayLabel: String {
        switch self {
        case .idle:       return "STANDBY"
        case .validating: return "ANALYZING"
        case .validated:  return "ARMED"
        case .running:    return "PROCESSING"
        case .done:       return "COMPLETE"
        case .aborted:    return "ABORTED"
        case .error:      return "ERROR"
        }
    }
}

enum ModelSource: String { case claude, gemini; var displayName: String { rawValue.uppercased() } }

struct PipelineStep: Identifiable {
    let id = UUID()
    let model: ModelSource
    let label: String
    var status: StepStatus
    var content: String
    var tokenCount: Int { content.split(separator: " ").count }
    enum StepStatus { case running, done, failed }
}

enum ArbiterError: LocalizedError {
    case httpError(Int, String), emptyResponse, parseError(String), missingKey(String), networkUnavailable
    var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return "SYSTEM_ERR [HTTP \(code)]: \(msg)"
        case .emptyResponse:                return "SYSTEM_ERR: EMPTY_RESPONSE"
        case .parseError(let d):            return "DATA_ERR: \(d)"
        case .missingKey(let k):            return "CONFIG_ERR: MISSING_KEY [\(k)]"
        case .networkUnavailable:           return "OFFLINE: NETWORK_UNAVAILABLE"
        }
    }
}

// MARK: — Validation Result

struct ValidationResult {

    // MARK: Verdict
    enum Verdict: String, Decodable {
        case green, amber, red
        var label: String {
            switch self {
            case .green: return "RISK LOW: PROMPT CLEARED"
            case .amber: return "RISK MEDIUM: REVIEW ADVISED"
            case .red:   return "RISK HIGH: PROMPT FLAGGED"
            }
        }
    }

    // MARK: Decodable mirror (raw JSON shape from Claude)
    struct Raw: Decodable {
        let specificity:   Int
        let verifiability: Int
        let ambiguity:     Int
        let scope:         Int
        let verdict:       String
        let summary:       String
        let suggestions:   [String]
        let refinedPrompt: String?
    }

    // MARK: Typed fields
    let specificity:   Int
    let verifiability: Int
    let ambiguity:     Int
    let scope:         Int
    let verdict:       Verdict
    let summary:       String
    let suggestions:   [String]
    let refinedPrompt: String?

    // MARK: Factory
    static func from(_ raw: Raw) -> ValidationResult {
        ValidationResult(
            specificity:   raw.specificity,
            verifiability: raw.verifiability,
            ambiguity:     raw.ambiguity,
            scope:         raw.scope,
            verdict:       Verdict(rawValue: raw.verdict.lowercased()) ?? .amber,
            summary:       raw.summary,
            suggestions:   raw.suggestions,
            refinedPrompt: raw.refinedPrompt
        )
    }
}
