import Foundation
import SwiftUI
import Combine

// MARK: — Validation Engine

struct ValidationEngine {

    static func validate(prompt: String, apiKey: String) async throws -> ValidationResult {

        let systemPrompt = """
            You are a prompt quality analyzer for AI hallucination risk.
            Output ONLY a single valid JSON object. No preamble, no explanation, no markdown fences.
            """

        let userMessage = """
            Analyze this prompt for AI hallucination risk.
            Respond ONLY with raw JSON, no markdown, no backticks:

            {
              "specificity":   <int 1-5>,
              "verifiability": <int 1-5>,
              "ambiguity":     <int 1-5>,
              "scope":         <int 1-5>,
              "verdict":       "green" | "amber" | "red",
              "summary":       "<one concise sentence>",
              "suggestions":   ["<tip1>", "<tip2>"],
              "refinedPrompt": "<improved version>"
            }

            Scoring (integers 1–5 only):
            - specificity:   how constrained (5 = very specific = good)
            - verifiability: how easy to fact-check (5 = easily verifiable = good)
            - ambiguity:     how unclear/open-ended (5 = very ambiguous = bad)
            - scope:         how broad in knowledge demand (5 = too wide = bad)

            verdict logic:
            - "green" if specificity >= 3 AND verifiability >= 3 AND ambiguity <= 2 AND scope <= 3
            - "red"   if specificity <= 2 OR ambiguity >= 4 OR scope >= 5
            - "amber" otherwise

            refinedPrompt: a rewritten version that is more specific, bounded, and lower-hallucination.

            Prompt to assess:
            \"\"\"
            \(prompt)
            \"\"\"
            """

        let raw = try await ClaudeClient.call(
            messages: [["role": "user", "content": userMessage]],
            system:   systemPrompt,
            apiKey:   apiKey
        )

        // Strip potential markdown fences
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw ArbiterError.parseError("Could not encode validation response")
        }

        let decoder = JSONDecoder()
        let rawResult = try decoder.decode(ValidationResult.Raw.self, from: data)
        return ValidationResult.from(rawResult)
    }
}
