import Foundation

public enum ReviewAIDirectCatalog {
    public static let disclosureVersion = 1

    public static func models(for provider: ReviewAIHarnessKind) -> [ReviewAIModelOption] {
        switch provider {
        case .anthropic:
            [
                ReviewAIModelOption(
                    modelID: "claude-haiku-5-5", displayName: "Claude Haiku 5.5", isRecommended: true,
                    supportedReasoningEfforts: [])
            ]
        case .openAI:
            [
                ReviewAIModelOption(
                    modelID: "gpt-5.6-terra", displayName: "GPT-5.6 Terra", isRecommended: true,
                    supportedReasoningEfforts: [])
            ]
        default:
            []
        }
    }

    public static func documentation(for provider: ReviewAIHarnessKind) -> URL {
        URL(
            string: provider == .anthropic
                ? "https://platform.claude.com/docs/en/models/haiku-5-5/overview"
                : "https://developers.openai.com/api/docs/models/gpt-5.6-terra")!
    }
}

public enum ReviewAIDirectError: Error, LocalizedError, Equatable {
    case consentRequired
    case missingCredential
    case invalidConfiguration
    case requestTooLarge
    case responseTooLarge
    case invalidResponse
    case http(Int)
    case network

    public var errorDescription: String? {
        switch self {
        case .consentRequired: "Confirm the AI data disclosure before analysis."
        case .missingCredential: "Save an API key in AI suggestions settings first."
        case .invalidConfiguration: "Choose a supported AI provider and model."
        case .requestTooLarge: "This AI request exceeds the activity limit. Use smaller Review groups."
        case .responseTooLarge: "The AI response exceeded the safety limit."
        case .invalidResponse: "The provider returned an incomplete or invalid response. Nothing was applied."
        case .http(let status):
            switch status {
            case 401, 403: "The provider rejected your API key or model access. Check AI suggestions settings."
            case 429: "The provider's rate or usage limit was reached. Try again later."
            default: "The AI provider returned an error (HTTP \(status)). Nothing was applied."
            }
        case .network: "Could not reach the AI provider. Tracking continues locally."
        }
    }
}

public protocol ReviewAIHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct ReviewAIURLSessionTransport: ReviewAIHTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoAIRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw ReviewAIDirectError.invalidResponse }
            guard response.expectedContentLength <= 1_048_576 else { throw ReviewAIDirectError.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                if data.count >= 1_048_576 { throw ReviewAIDirectError.responseTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            return (data, response.statusCode)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ReviewAIDirectError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw ReviewAIDirectError.network
        }
    }
}

private final class NoAIRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum ReviewAIRedaction {
    public static func host(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
            ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
            let host = components.host, !host.isEmpty
        else { return nil }
        return host.lowercased()
    }

    public static func title(_ value: String) -> String {
        var result = String(value.prefix(500))
        for pattern in [
            #"https?://[^\s<>]+"#, #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, #"(?:/Users/|/home/|file://)[^\s]+"#,
            #"\b(?:sk-|sk_ant_|sk-ant-)[A-Za-z0-9_-]+"#,
        ] {
            result = result.replacingOccurrences(
                of: pattern, with: "[redacted]", options: [.regularExpression, .caseInsensitive])
        }
        return String(result.prefix(160))
    }

    public static func request(_ request: ReviewAISuggestionRequest, shareTitles: Bool) -> ReviewAISuggestionRequest {
        func value(_ value: String, field: RuleField) -> String {
            switch field {
            case .url: host(value) ?? "[URL withheld]"
            case .windowTitle: shareTitles ? title(value) : "[title withheld]"
            default: String(title(value).prefix(160))
            }
        }
        return ReviewAISuggestionRequest(
            groups: request.groups.enumerated().map { index, original in
                var group = original
                group.id = "group-\(index)"
                group.proposedRuleCondition.value = value(
                    original.proposedRuleCondition.value, field: original.proposedRuleCondition.field)
                group.samples = original.samples.prefix(3).map { sample in
                    ReviewAISuggestionSample(
                        appName: String(title(sample.appName).prefix(100)),
                        bundleIdentifier: String(title(sample.bundleIdentifier).prefix(160)),
                        windowTitle: shareTitles ? title(sample.windowTitle) : "[title withheld]",
                        url: sample.url.flatMap(host), duration: sample.duration)
                }
                group.relatedRules = original.relatedRules.filter { $0.kind != .ignored }.prefix(8).map { rule in
                    var rule = rule
                    rule.value = value(rule.value, field: rule.field)
                    return rule
                }
                return group
            })
    }
}

public struct DirectReviewAISuggestionProvider: ReviewAISuggestionProviding {
    public var provider: ReviewAIHarnessKind
    public var model: String
    public var apiKey: String
    public var consentVersion: Int
    public var shareTitles: Bool
    public var profession: ReviewAIProfession
    private let transport: any ReviewAIHTTPTransport

    public init(
        provider: ReviewAIHarnessKind, model: String, apiKey: String, consentVersion: Int, shareTitles: Bool = false,
        profession: ReviewAIProfession = .notSpecified,
        transport: any ReviewAIHTTPTransport = ReviewAIURLSessionTransport()
    ) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.consentVersion = consentVersion
        self.shareTitles = shareTitles
        self.profession = profession
        self.transport = transport
    }

    public func suggestions(for request: ReviewAISuggestionRequest) async throws -> [ReviewAISuggestion] {
        guard consentVersion == ReviewAIDirectCatalog.disclosureVersion else {
            throw ReviewAIDirectError.consentRequired
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, apiKey.utf8.count <= 4_096,
            !apiKey.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ReviewAIDirectError.missingCredential
        }
        guard provider.isDirectProvider, !model.isEmpty, model.count <= 200,
            !model.contains(where: { $0.isNewline || $0.isWhitespace })
        else { throw ReviewAIDirectError.invalidConfiguration }
        guard request.groups.count <= 20 else { throw ReviewAIDirectError.requestTooLarge }
        if request.groups.isEmpty { return [] }
        try Task.checkCancellation()
        let redacted = ReviewAIRedaction.request(request, shareTitles: shareTitles)
        let prompt =
            try ReviewAIContract.prompt(for: redacted, profession: profession)
            + "\nRequired response JSON schema:\n" + ReviewAIContract.schemaString
        guard prompt.utf8.count <= 96 * 1_024 else { throw ReviewAIDirectError.requestTooLarge }
        let endpoint =
            provider == .anthropic
            ? "https://api.anthropic.com/v1/messages" : "https://api.openai.com/v1/chat/completions"
        var http = URLRequest(url: URL(string: endpoint)!)
        http.httpMethod = "POST"
        http.timeoutInterval = 60
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": model, "messages": [["role": "user", "content": prompt]]]
        if provider == .anthropic {
            http.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            http.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["max_tokens"] = 8_192
            if model == "claude-haiku-5-5" { body["output_config"] = ["effort": "low"] }
        } else {
            http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body["max_completion_tokens"] = 8_192
            if model == "gpt-5.6-terra" { body["reasoning_effort"] = "low" }
            body["store"] = false
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "hago_review", "strict": true,
                    "schema": try JSONSerialization.jsonObject(with: ReviewAIContract.schemaData),
                ],
            ]
        }
        http.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, status) = try await transport.send(http)
        try Task.checkCancellation()
        guard (200..<300).contains(status) else { throw ReviewAIDirectError.http(status) }
        guard data.count <= 1_048_576 else { throw ReviewAIDirectError.responseTooLarge }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReviewAIDirectError.invalidResponse
        }
        let text: String
        if provider == .anthropic {
            guard root["stop_reason"] as? String == "end_turn", let blocks = root["content"] as? [[String: Any]],
                blocks.allSatisfy({ ["text", "thinking", "redacted_thinking"].contains($0["type"] as? String ?? "") })
            else { throw ReviewAIDirectError.invalidResponse }
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        } else {
            guard let choices = root["choices"] as? [[String: Any]], choices.count == 1,
                choices[0]["finish_reason"] as? String == "stop",
                let message = choices[0]["message"] as? [String: Any],
                message["refusal"] == nil || message["refusal"] is NSNull,
                let content = message["content"] as? String
            else { throw ReviewAIDirectError.invalidResponse }
            text = content
        }
        let envelope = try ReviewAIHarnessOutputParser.envelope(from: Data(text.utf8))
        _ = try ReviewAIContract.suggestions(from: envelope, for: redacted)
        var mapped = envelope
        mapped.decisions = try envelope.decisions.map { decision in
            guard let index = redacted.groups.firstIndex(where: { $0.id == decision.groupID }) else {
                throw ReviewAIContractError.invalidGroupIDs
            }
            var decision = decision
            decision.groupID = request.groups[index].id
            return decision
        }
        return try ReviewAIContract.suggestions(from: mapped, for: request)
    }
}
