import Foundation

public struct ReviewAIModelCatalog: Sendable {
    private let runner: any ReviewAIProcessRunning

    public init(runner: any ReviewAIProcessRunning = FoundationReviewAIProcessRunner()) {
        self.runner = runner
    }

    public func models(
        for harness: ReviewAIHarnessKind,
        executablePath: String,
        environment: [String: String]
    ) async -> [ReviewAIModelOption] {
        switch harness {
        case .codex:
            return Self.codexModels(environment: environment)
        case .claudeCode:
            return Self.claudeModels
        case .pi:
            return await piModels(executablePath: executablePath, environment: environment)
        case .anthropic, .openAI:
            return ReviewAIDirectCatalog.models(for: harness)
        case .disabled:
            return []
        }
    }

    static func codexModels(environment: [String: String]) -> [ReviewAIModelOption] {
        let codexDirectory: URL
        if let configuredDirectory = environment["CODEX_HOME"], !configuredDirectory.isEmpty {
            codexDirectory = URL(fileURLWithPath: configuredDirectory, isDirectory: true)
        } else {
            let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            codexDirectory = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".codex", isDirectory: true)
        }
        let cacheURL = codexDirectory.appendingPathComponent("models_cache.json")

        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(CodexModelsCache.self, from: data) {
            let visibleModels = cache.models.filter { $0.visibility == "list" }
            if !visibleModels.isEmpty {
                return visibleModels.enumerated().map { index, model in
                    let efforts = (model.supportedReasoningLevels ?? []).compactMap {
                        ReviewAIReasoningEffort(rawValue: $0.effort)
                    }
                    return ReviewAIModelOption(
                        modelID: model.slug,
                        displayName: model.displayName ?? model.slug,
                        isRecommended: index == 0,
                        supportedReasoningEfforts: efforts,
                        recommendedReasoningEffort: ReviewAIReasoningEffort(
                            rawValue: model.defaultReasoningLevel ?? ""
                        )
                    )
                }
            }
        }

        let efforts: [ReviewAIReasoningEffort] = [.low, .medium, .high, .xhigh, .max]
        return [
            ReviewAIModelOption(
                modelID: "gpt-5.6-sol",
                displayName: "GPT-5.6 Sol",
                isRecommended: true,
                supportedReasoningEfforts: efforts,
                recommendedReasoningEffort: .low
            ),
            ReviewAIModelOption(
                modelID: "gpt-5.6-terra",
                displayName: "GPT-5.6 Terra",
                supportedReasoningEfforts: efforts,
                recommendedReasoningEffort: .medium
            ),
            ReviewAIModelOption(
                modelID: "gpt-5.6-luna",
                displayName: "GPT-5.6 Luna",
                supportedReasoningEfforts: efforts,
                recommendedReasoningEffort: .medium
            )
        ]
    }

    static let claudeModels: [ReviewAIModelOption] = {
        let efforts: [ReviewAIReasoningEffort] = [.low, .medium, .high, .xhigh, .max]
        return [
            ReviewAIModelOption(
                modelID: "sonnet",
                displayName: "Latest Sonnet",
                isRecommended: true,
                supportedReasoningEfforts: efforts,
                recommendedReasoningEffort: .medium
            ),
            ReviewAIModelOption(
                modelID: "opus",
                displayName: "Latest Opus",
                supportedReasoningEfforts: efforts,
                recommendedReasoningEffort: .medium
            ),
            ReviewAIModelOption(
                modelID: "fable",
                displayName: "Latest Fable",
                supportedReasoningEfforts: efforts,
                recommendedReasoningEffort: .medium
            )
        ]
    }()

    static func parsePiModels(
        _ output: String,
        recommendedModelID: String?,
        recommendedReasoningEffort: ReviewAIReasoningEffort?
    ) -> [ReviewAIModelOption] {
        let lines = output.split(whereSeparator: \.isNewline)
        var models: [ReviewAIModelOption] = []

        for line in lines {
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 6,
                  columns[0].lowercased() != "provider",
                  ["yes", "no"].contains(columns[4].lowercased()) else {
                continue
            }
            let modelID = "\(columns[0])/\(columns[1])"
            let supportsReasoning = columns[4].lowercased() == "yes"
            models.append(
                ReviewAIModelOption(
                    modelID: modelID,
                    displayName: columns[1],
                    isRecommended: modelID == recommendedModelID,
                    supportedReasoningEfforts: supportsReasoning
                        ? [.off, .minimal, .low, .medium, .high, .xhigh, .max]
                        : [.off],
                    recommendedReasoningEffort: supportsReasoning
                        ? recommendedReasoningEffort ?? .medium
                        : .off
                )
            )
        }

        if !models.isEmpty, !models.contains(where: \.isRecommended) {
            models[0].isRecommended = true
        }
        return models
    }

    private func piModels(
        executablePath: String,
        environment: [String: String]
    ) async -> [ReviewAIModelOption] {
        do {
            let directory = try ReviewAIHarnessDiscovery.makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let result = try await runner.run(
                ReviewAIProcessRequest(
                    executablePath: executablePath,
                    arguments: ["--list-models"],
                    environment: environment,
                    workingDirectory: directory,
                    timeout: 10,
                    maximumOutputBytes: 1 * 1_024 * 1_024
                )
            )
            guard result.exitCode == 0 else {
                return []
            }
            let defaults = Self.piDefaults(environment: environment)
            return Self.parsePiModels(
                String(decoding: result.standardOutput, as: UTF8.self),
                recommendedModelID: defaults.modelID,
                recommendedReasoningEffort: defaults.reasoningEffort
            )
        } catch {
            return []
        }
    }

    private static func piDefaults(
        environment: [String: String]
    ) -> (modelID: String?, reasoningEffort: ReviewAIReasoningEffort?) {
        let settingsDirectory: URL
        if let configuredDirectory = environment["PI_CODING_AGENT_DIR"], !configuredDirectory.isEmpty {
            settingsDirectory = URL(fileURLWithPath: configuredDirectory, isDirectory: true)
        } else {
            let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
            settingsDirectory = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".pi/agent", isDirectory: true)
        }
        let settingsURL = settingsDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(PiSettings.self, from: data) else {
            return (nil, nil)
        }
        let modelID: String?
        if let provider = settings.defaultProvider, let model = settings.defaultModel {
            modelID = "\(provider)/\(model)"
        } else {
            modelID = settings.defaultModel
        }
        return (
            modelID,
            settings.thinkingLevel.flatMap(ReviewAIReasoningEffort.init(rawValue:))
        )
    }
}

private struct CodexModelsCache: Decodable {
    var models: [CodexModel]
}

private struct CodexModel: Decodable {
    var slug: String
    var displayName: String?
    var visibility: String
    var defaultReasoningLevel: String?
    var supportedReasoningLevels: [CodexReasoningLevel]?

    private enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case visibility
        case defaultReasoningLevel = "default_reasoning_level"
        case supportedReasoningLevels = "supported_reasoning_levels"
    }
}

private struct CodexReasoningLevel: Decodable {
    var effort: String
}

private struct PiSettings: Decodable {
    var defaultProvider: String?
    var defaultModel: String?
    var thinkingLevel: String?
}
