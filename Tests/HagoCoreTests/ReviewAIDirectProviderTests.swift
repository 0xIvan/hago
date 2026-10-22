import Foundation
import Testing

@testable import HagoCore

@Suite
struct ReviewAIDirectProviderTests {
    private func request() -> ReviewAISuggestionRequest {
        ReviewAISuggestionRequest(groups: [
            ReviewAISuggestionGroup(
                id: "secret@example.com-private-title",
                proposedRuleCondition: RuleCondition(
                    field: .url, operation: .equals,
                    value: "https://user:password@example.com/private-document?token=secret#fragment"),
                affectedCount: 2, affectedDuration: 600,
                samples: [
                    ReviewAISuggestionSample(
                        appName: "Browser", bundleIdentifier: "org.test.browser",
                        windowTitle:
                            "Private person secret@example.com https://example.com/secret /Users/test/private sk-secretkey",
                        url: "https://example.com/private-document?token=secret#fragment", duration: 600)
                ])
        ])
    }

    @Test
    func redactionRemovesSecretsAndUsesOpaqueIDs() throws {
        let redacted = ReviewAIRedaction.request(request(), shareTitles: false)
        let prompt = try ReviewAIContract.prompt(for: redacted)
        for secret in [
            "secret@example.com", "private-document", "password", "token=", "fragment", "Private person",
            "sk-secretkey",
        ] {
            #expect(!prompt.contains(secret))
        }
        #expect(redacted.groups[0].id == "group-0")
        #expect(redacted.groups[0].samples[0].url == "example.com")
        let title = ReviewAIRedaction.title(request().groups[0].samples[0].windowTitle)
        #expect(!title.contains("secret@example.com"))
        #expect(!title.contains("/Users/test"))
        #expect(!title.contains("sk-secretkey"))
    }

    @Test
    func explicitConsentIsRequiredBeforeTransport() async {
        let transport = FixtureTransport(status: 200, body: Data())
        let provider = DirectReviewAISuggestionProvider(
            provider: .openAI, model: "custom", apiKey: "fixture-key", consentVersion: 0, transport: transport)
        await #expect(throws: ReviewAIDirectError.consentRequired) { try await provider.suggestions(for: request()) }
        #expect(await transport.calls == 0)
    }

    @Test
    func authenticatedResponseMapsOnlyValidatedOriginalScope() async throws {
        let envelope = ReviewAIResponseEnvelope(decisions: [
            ReviewAIResponseDecision(groupID: "group-0", kind: .work, confidence: 0.97, reason: "Work context")
        ])
        let content = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
        let body = try JSONSerialization.data(withJSONObject: [
            "choices": [["finish_reason": "stop", "message": ["content": content]]]
        ])
        let transport = FixtureTransport(status: 200, body: body)
        let provider = DirectReviewAISuggestionProvider(
            provider: .openAI, model: "custom", apiKey: "fixture-key", consentVersion: 1, transport: transport)
        let original = request()
        let suggestions = try await provider.suggestions(for: original)
        #expect(suggestions[0].id == original.groups[0].id)
        #expect(suggestions[0].proposedRuleCondition == original.groups[0].proposedRuleCondition)
        let sent = try #require(await transport.lastRequest)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        #expect(sent.url?.host == "api.openai.com")
        #expect(!String(decoding: sent.httpBody ?? Data(), as: UTF8.self).contains("private-document"))
    }

    @Test
    func authenticationAndMalformedResponsesNeverCreateSuggestions() async throws {
        let denied = FixtureTransport(status: 401, body: Data("fixture-key private provider error".utf8))
        let provider = DirectReviewAISuggestionProvider(
            provider: .anthropic, model: "custom", apiKey: "fixture-key", consentVersion: 1, transport: denied)
        await #expect(throws: ReviewAIDirectError.http(401)) { try await provider.suggestions(for: request()) }
        #expect(await denied.calls == 1)
        #expect(!ReviewAIDirectError.http(401).localizedDescription.contains("fixture-key"))
        let invalid = FixtureTransport(status: 200, body: Data("{}".utf8))
        let malformed = DirectReviewAISuggestionProvider(
            provider: .openAI, model: "custom", apiKey: "fixture-key", consentVersion: 1, transport: invalid)
        await #expect(throws: ReviewAIDirectError.invalidResponse) { try await malformed.suggestions(for: request()) }
    }

    @Test
    func cancellationDoesNotReturnSuggestions() async {
        let provider = DirectReviewAISuggestionProvider(
            provider: .openAI, model: "custom", apiKey: "fixture-key", consentVersion: 1,
            transport: CancelledTransport())
        await #expect(throws: CancellationError.self) { try await provider.suggestions(for: request()) }
    }

    @Test
    func legacySettingsPreserveConsentAndNeverOptIntoDirectSharing() throws {
        let data = Data(
            #"{"selectedHarness":"claudeCode","confirmedHarnesses":["claudeCode"],"scheduleEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(ReviewAISettings.self, from: data)
        #expect(settings.selectedHarness == .claudeCode)
        #expect(settings.confirmedHarnesses == [.claudeCode])
        #expect(settings.scheduleEnabled)
        #expect(settings.directDisclosureVersion == 0)
        #expect(!settings.shareRedactedTitles)
        #expect(!String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains("apiKey"))
    }
}

private actor FixtureTransport: ReviewAIHTTPTransport {
    var calls = 0
    var lastRequest: URLRequest?
    let status: Int
    let body: Data

    init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1
        lastRequest = request
        return (body, status)
    }
}

private struct CancelledTransport: ReviewAIHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) { throw CancellationError() }
}
