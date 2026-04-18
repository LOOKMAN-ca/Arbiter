import Foundation
import SwiftUI
import Combine

// MARK: — Orchestration Engine

@MainActor
final class OrchestrationEngine: ObservableObject {

    @Published var phase:        PipelinePhase = .idle
    @Published var steps:        [PipelineStep] = []
    @Published var finalOutput:  String = ""
    @Published var errorMessage: String?
    @Published var validation:   ValidationResult?

    private var runTask: Task<Void, Never>?

    // MARK: — Validate

    func validate(prompt: String, settings: AppSettings) {
        phase      = .validating
        validation  = nil
        errorMessage = nil

        runTask = Task {
            do {
                let result = try await ValidationEngine.validate(
                    prompt: prompt,
                    apiKey: settings.claudeKey
                )
                self.validation = result
                self.phase      = .validated
            } catch {
                self.errorMessage = error.localizedDescription
                self.phase        = .idle
            }
        }
    }

    // MARK: — Execute

    func execute(prompt: String, mode: PipelineMode, iterations: Int, settings: AppSettings) {
        phase        = .running
        steps        = []
        finalOutput  = ""
        errorMessage = nil

        runTask = Task {
            do {
                switch mode {
                case .sequential:
                    try await runSequential(prompt: prompt, settings: settings)
                case .iterative:
                    try await runIterative(prompt: prompt, iterations: iterations, settings: settings)
                }
                self.phase = .done
            } catch is CancellationError {
                self.phase = .aborted
            } catch {
                self.errorMessage = error.localizedDescription
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    // MARK: — Abort

    func abort() {
        runTask?.cancel()
        runTask = nil
        phase = .aborted
    }

    // MARK: — Reset

    func reset() {
        abort()
        phase        = .idle
        steps        = []
        finalOutput  = ""
        errorMessage = nil
        validation   = nil
    }

    // MARK: — Sequential Pipeline

    private func runSequential(prompt: String, settings: AppSettings) async throws {

        // Step 1: Claude initial draft
        let step1id = addStep(model: .claude, label: "INITIAL DRAFT")
        let draft = try await ClaudeClient.stream(
            messages: [["role": "user", "content": prompt]],
            system:   settings.effectiveSystemPrompt,
            apiKey:   settings.claudeKey,
            model:    settings.claudeModel,
            onToken:  { [weak self] text in
                Task { @MainActor [weak self] in self?.updateStep(id: step1id, content: text) }
            }
        )
        try Task.checkCancellation()
        finishStep(id: step1id, content: draft)

        // Step 2: Gemini critical review
        let step2id = addStep(model: .gemini, label: "CRITICAL REVIEW")
        let critiquePrompt = """
            You are a rigorous critical reviewer.
            User prompt: \"\"\"\(prompt)\"\"\"

            Response to review:
            \"\"\"\(draft)\"\"\"

            Identify specific issues as numbered points: factual risks, unsupported claims, logical gaps, missing nuance. Be precise and concise. Do NOT rewrite — only critique.
            """
        let critique = try await GeminiClient.stream(
            prompt:  critiquePrompt,
            apiKey:  settings.geminiKey,
            model:   settings.geminiModel,
            onToken: { [weak self] text in
                Task { @MainActor [weak self] in self?.updateStep(id: step2id, content: text) }
            }
        )
        try Task.checkCancellation()
        finishStep(id: step2id, content: critique)

        // Step 3: Claude final synthesis
        let step3id = addStep(model: .claude, label: "FINAL SYNTHESIS")
        let synthPrompt = """
            Original prompt: \"\"\"\(prompt)\"\"\"

            Your initial draft:
            \"\"\"\(draft)\"\"\"

            Critique from a second AI model:
            \"\"\"\(critique)\"\"\"

            Produce the final refined answer. Incorporate valid critique points only. Discard unfounded objections. Be accurate, complete, and well-structured.
            """
        let final = try await ClaudeClient.stream(
            messages: [["role": "user", "content": synthPrompt]],
            system:   "Produce a final refined answer integrating valid critique. Be direct, accurate, complete.",
            apiKey:   settings.claudeKey,
            model:    settings.claudeModel,
            onToken:  { [weak self] text in
                Task { @MainActor [weak self] in self?.updateStep(id: step3id, content: text) }
            }
        )
        try Task.checkCancellation()
        finishStep(id: step3id, content: final)
        self.finalOutput = final
    }

    // MARK: — Iterative Pipeline

    private func runIterative(prompt: String, iterations: Int, settings: AppSettings) async throws {

        // Initial draft
        let s0id = addStep(model: .claude, label: "INITIAL DRAFT")
        var current = try await ClaudeClient.stream(
            messages: [["role": "user", "content": prompt]],
            system:   settings.effectiveSystemPrompt,
            apiKey:   settings.claudeKey,
            model:    settings.claudeModel,
            onToken:  { [weak self] text in
                Task { @MainActor [weak self] in self?.updateStep(id: s0id, content: text) }
            }
        )
        try Task.checkCancellation()
        finishStep(id: s0id, content: current)

        // Iterative critique-revision loops
        for i in 0..<iterations {
            let loopLabel = "LOOP \(i + 1)"

            // Gemini critique
            let scId = addStep(model: .gemini, label: "\(loopLabel) — CRITIQUE")
            let critiquePrompt = """
                Prompt: \"\"\"\(prompt)\"\"\"

                Current response:
                \"\"\"\(current)\"\"\"

                Critique as numbered points: what is factually weak, logically incomplete, missing nuance, or could be strengthened?
                """
            let critique = try await GeminiClient.stream(
                prompt:  critiquePrompt,
                apiKey:  settings.geminiKey,
                model:   settings.geminiModel,
                onToken: { [weak self] text in
                    Task { @MainActor [weak self] in self?.updateStep(id: scId, content: text) }
                }
            )
            try Task.checkCancellation()
            finishStep(id: scId, content: critique)

            // Claude revision
            let srId = addStep(model: .claude, label: "\(loopLabel) — REVISION")
            let revisePrompt = """
                Original prompt: \"\"\"\(prompt)\"\"\"

                Previous response:
                \"\"\"\(current)\"\"\"

                Critique:
                \"\"\"\(critique)\"\"\"

                Revise and improve based on valid critique points. Preserve what is already accurate. Be more precise where the critique is valid.
                """
            current = try await ClaudeClient.stream(
                messages: [["role": "user", "content": revisePrompt]],
                system:   "Revise your previous response based on valid critique. Improve accuracy and completeness.",
                apiKey:   settings.claudeKey,
                model:    settings.claudeModel,
                onToken:  { [weak self] text in
                    Task { @MainActor [weak self] in self?.updateStep(id: srId, content: text) }
                }
            )
            try Task.checkCancellation()
            finishStep(id: srId, content: current)
        }

        self.finalOutput = current
    }

    // MARK: — Step helpers

    private func addStep(model: ModelSource, label: String) -> UUID {
        let step = PipelineStep(model: model, label: label, status: .running, content: "")
        steps.append(step)
        return step.id
    }

    private func updateStep(id: UUID, content: String) {
        guard let idx = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[idx].content = content
    }

    private func finishStep(id: UUID, content: String) {
        guard let idx = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[idx].content = content
        steps[idx].status  = .done
    }

    // MARK: — Static helpers

    static func callCount(mode: PipelineMode, iterations: Int) -> Int {
        mode == .sequential ? 3 : 1 + iterations * 2
    }

    static func estimatedSeconds(mode: PipelineMode, iterations: Int) -> Int {
        callCount(mode: mode, iterations: iterations) * 7
    }
}
