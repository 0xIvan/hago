import Foundation
import SQLite3
import Testing
@testable import HagoCore

@Suite
struct ReviewAISuggestionTests {
    @Test
    func missingDiscordTitlesCannotGenerateAppWideAISuggestions() {
        let request = ReviewAISuggestionRequest(reviewSegments: [
            classifiedSegment(appName: "Discord", bundleIdentifier: "com.hnc.Discord", windowTitle: "", url: nil, source: .macOS),
            classifiedSegment(appName: "Discord", bundleIdentifier: "com.hnc.Discord", windowTitle: "#work | Jian Yang - Discord", url: nil, source: .macOS)
        ])
        #expect(request.groups.count == 1)
        #expect(request.groups.first?.proposedRuleCondition.field == .windowTitle)
    }

    @Test
    func groupsReviewBacklogByStableSignals() {
        let request = ReviewAISuggestionRequest(
            reviewSegments: [
                classifiedSegment(url: "https://clerk.com/docs", offset: 0),
                classifiedSegment(url: "https://clerk.com/dashboard", offset: 120),
                classifiedSegment(url: "file:///Users/ivan/local.html", offset: 240),
                classifiedSegment(
                    appName: "Cursor",
                    bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                    windowTitle: "",
                    url: nil,
                    source: .macOS,
                    offset: 360
                )
            ],
            sampleLimit: 1
        )

        let clerkGroup = request.groups.first { $0.proposedRuleCondition.value == "clerk.com" }
        let fileGroup = request.groups.first { $0.proposedRuleCondition.value == "file:///Users/ivan/local.html" }
        let cursorGroup = request.groups.first { $0.proposedRuleCondition.value == "Cursor" }

        #expect(clerkGroup?.proposedRuleCondition.field == .host)
        #expect(clerkGroup?.affectedCount == 2)
        #expect(clerkGroup?.affectedDuration == 240)
        #expect(clerkGroup?.samples.count == 1)
        #expect(fileGroup?.proposedRuleCondition.field == .url)
        #expect(cursorGroup?.proposedRuleCondition.field == .appName)
    }

    @Test
    func unsureSuggestionDoesNotApply() throws {
        let store = try makeStore()
        let segment = classifiedSegment(url: "https://unknown.example.com").segment

        try saveReviewSegment(segment, in: store)

        let ruleID = try store.applyReviewAISuggestion(
            suggestion(
                kind: .unsure,
                confidence: 0.4,
                condition: RuleCondition(field: .host, operation: .equals, value: "unknown.example.com")
            )
        )

        #expect(ruleID == nil)
        #expect(try store.reviewSegments().count == 1)
    }

    @Test
    func broadBrowserAppRuleIsRejected() {
        let validation = ReviewAISuggestionValidator().validationResult(
            for: suggestion(
                kind: .work,
                confidence: 0.9,
                condition: RuleCondition(field: .appName, operation: .equals, value: "Google Chrome")
            )
        )

        #expect(validation.canApply == false)
    }

    @Test
    func ignoredSuggestionCanBeAppliedManuallyButNotAutomatically() throws {
        let store = try makeStore()
        let segment = classifiedSegment(url: "chrome-extension://example/options.html").segment
        let suggestion = suggestion(
            kind: .ignored,
            confidence: 0.9,
            condition: RuleCondition(field: .url, operation: .equals, value: "chrome-extension://example/options.html")
        )

        try saveReviewSegment(segment, in: store)
        let validation = ReviewAISuggestionValidator().validationResult(for: suggestion)
        let automaticValidation = ReviewAISuggestionValidator().automaticValidationResult(for: suggestion)
        let ruleID = try store.applyReviewAISuggestion(suggestion)

        #expect(validation.canApply)
        #expect(automaticValidation.canApply == false)
        #expect(ruleID != nil)
        #expect(try store.reviewSegments().isEmpty)
        #expect(try store.loadRules().contains { $0.id == ruleID && $0.action.kind == .ignored })
    }

    @Test
    func highConfidenceHostSuggestionCreatesRememberedRuleAndReclassifiesHistory() throws {
        let store = try makeStore()
        let firstSegment = classifiedSegment(url: "https://clerk.com/docs").segment
        let secondSegment = classifiedSegment(url: "https://clerk.com/dashboard", offset: 120).segment
        let suggestion = suggestion(
            kind: .work,
            confidence: 0.9,
            condition: RuleCondition(field: .host, operation: .equals, value: "clerk.com")
        )

        try saveReviewSegment(firstSegment, in: store)
        try saveReviewSegment(secondSegment, in: store)

        let ruleID = try #require(try store.applyReviewAISuggestion(suggestion))
        let activitySegments = try store.activitySegments(for: Date())

        #expect(try store.reviewSegments().isEmpty)
        #expect(activitySegments.allSatisfy { $0.classification.kind == .work })
        #expect(activitySegments.allSatisfy { $0.classification.ruleID == ruleID })
        #expect(
            try store.loadRules().contains {
                $0.id == ruleID && $0.name == "Remember clerk.com as work"
            }
        )
    }

    @Test
    func staleSuggestionWithoutCurrentReviewMatchesDoesNotCreateRule() throws {
        let store = try makeStore()
        let segment = classifiedSegment(url: "https://clerk.com/docs").segment
        let staleWorkSuggestion = suggestion(
            kind: .work,
            confidence: 0.9,
            condition: RuleCondition(field: .host, operation: .equals, value: "clerk.com")
        )
        let manualPersonalRule = Rule(
            name: "Remember clerk.com",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .personal, categoryID: SeedData.personalCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .host, operation: .equals, value: "clerk.com")
            ]
        )

        try saveReviewSegment(segment, in: store)
        let manualRuleID = try store.saveRememberedRule(manualPersonalRule)
        try store.reclassify(ruleID: manualRuleID, scope: .allHistory)

        let staleRuleID = try store.applyReviewAISuggestion(staleWorkSuggestion)
        let rememberedClerkRules = try store.loadRules()
            .filter { $0.name == "Remember clerk.com" }

        #expect(staleRuleID == nil)
        #expect(try store.reviewSegments().isEmpty)
        #expect(rememberedClerkRules.count == 1)
        #expect(rememberedClerkRules.first?.action.kind == .personal)
    }

    @Test
    func automaticApplyRequiresNinetyFivePercentConfidence() {
        let validator = ReviewAISuggestionValidator()
        let condition = RuleCondition(field: .host, operation: .equals, value: "github.com")

        #expect(
            validator.automaticValidationResult(
                for: suggestion(kind: .work, confidence: 0.94, condition: condition)
            ).canApply == false
        )
        #expect(
            validator.automaticValidationResult(
                for: suggestion(kind: .work, confidence: 0.95, condition: condition)
            ).canApply
        )
    }

    @Test
    func relatedRuleHistoryIsIncludedAndConflictsBlockAutomaticApply() {
        let existingRules = [
            Rule(
                name: "OpenAI is work",
                priority: 150,
                enabled: true,
                isBuiltIn: false,
                action: RuleAction(kind: .work, categoryID: nil, projectID: nil),
                conditions: [RuleCondition(field: .host, operation: .equals, value: "platform.openai.com")]
            ),
            Rule(
                name: "OpenAI billing is personal",
                priority: 150,
                enabled: true,
                isBuiltIn: false,
                action: RuleAction(kind: .personal, categoryID: nil, projectID: nil),
                conditions: [RuleCondition(field: .host, operation: .equals, value: "pay.openai.com")]
            )
        ]
        let request = ReviewAISuggestionRequest(
            reviewSegments: [classifiedSegment(url: "https://status.openai.com")],
            existingRules: existingRules
        )
        let relatedKinds = request.groups.first?.relatedRules.map(\.kind) ?? []
        let suggestion = suggestion(
            kind: .work,
            confidence: 0.99,
            condition: RuleCondition(field: .host, operation: .equals, value: "status.openai.com"),
            relatedRuleKinds: relatedKinds
        )

        #expect(Set(relatedKinds) == [.work, .personal])
        #expect(ReviewAISuggestionValidator().automaticValidationResult(for: suggestion).canApply == false)
    }

    @Test
    func manualCorrectionCanApplyBelowAutomaticThreshold() {
        let validation = ReviewAISuggestionValidator().validationResult(
            for: suggestion(
                kind: .personal,
                confidence: 0.2,
                condition: RuleCondition(field: .host, operation: .equals, value: "example.com")
            )
        )

        #expect(validation.canApply)
    }

    @Test
    func automaticRunCanBeUndone() throws {
        let store = try makeStore()
        let segment = classifiedSegment(url: "https://github.com/openai/codex").segment
        try saveReviewSegment(segment, in: store)

        let summary = try store.processReviewAISuggestions(
            [
                suggestion(
                    kind: .work,
                    confidence: 0.99,
                    condition: RuleCondition(field: .host, operation: .equals, value: "github.com")
                )
            ],
            harness: .codex,
            harnessVersion: "codex 1.0",
            automaticallyApply: true
        )

        #expect(summary.automaticallyAppliedCount == 1)
        #expect(try store.reviewSegments().isEmpty)

        let undo = try store.undoReviewAIRun(id: summary.id)

        #expect(undo.revertedRuleCount == 1)
        #expect(undo.conflictCount == 0)
        #expect(try store.reviewSegments().count == 1)
        #expect(try store.mostRecentReviewAIRun()?.status == .undone)

        let secondUndo = try store.undoReviewAIRun(id: summary.id)
        #expect(secondUndo == ReviewAIUndoResult(revertedRuleCount: 0, unchangedRuleCount: 0, conflictCount: 0))
    }

    @Test
    func automaticRunThatFailsPartwayLeavesHistoryUntouched() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try HagoStore(databaseURL: url)
        try saveReviewSegment(classifiedSegment(url: "https://github.com/openai/codex").segment, in: store)
        try saveReviewSegment(classifiedSegment(url: "https://linear.app/team").segment, in: store)

        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        #expect(sqlite3_exec(connection, """
            CREATE TRIGGER fail_second_decision BEFORE INSERT ON review_ai_decisions
            WHEN (SELECT COUNT(*) FROM review_ai_decisions) >= 1
            BEGIN SELECT RAISE(ABORT, 'disk full'); END
            """, nil, nil, nil) == SQLITE_OK)

        #expect(throws: (any Error).self) {
            try store.processReviewAISuggestions(
                [
                    suggestion(kind: .work, confidence: 0.99,
                               condition: RuleCondition(field: .host, operation: .equals, value: "github.com")),
                    suggestion(kind: .work, confidence: 0.99,
                               condition: RuleCondition(field: .host, operation: .equals, value: "linear.app"))
                ],
                harness: .codex,
                harnessVersion: "codex 1.0",
                automaticallyApply: true
            )
        }

        #expect(try store.reviewSegments().count == 2)
        #expect(try store.loadRules().allSatisfy { $0.conditions.first?.value != "github.com" })
        #expect(try store.mostRecentReviewAIRun()?.status == .failed)
    }

    @Test
    func automaticRunKeepsLowConfidenceSuggestionForReview() throws {
        let store = try makeStore()
        let segment = classifiedSegment(url: "https://example.com/docs").segment
        try saveReviewSegment(segment, in: store)

        let summary = try store.processReviewAISuggestions(
            [
                suggestion(
                    kind: .work,
                    confidence: 0.94,
                    condition: RuleCondition(field: .host, operation: .equals, value: "example.com")
                )
            ],
            harness: .codex,
            harnessVersion: nil,
            automaticallyApply: true
        )

        #expect(summary.automaticallyAppliedCount == 0)
        #expect(summary.recommendationCount == 1)
        #expect(try store.reviewSegments().count == 1)
    }

    @Test
    func automaticRunHonorsRuleLimit() throws {
        let store = try makeStore()
        try saveReviewSegment(classifiedSegment(url: "https://first.example.com").segment, in: store)
        try saveReviewSegment(
            classifiedSegment(url: "https://second.example.com", offset: 120).segment,
            in: store
        )

        let summary = try store.processReviewAISuggestions(
            [
                suggestion(
                    kind: .work,
                    confidence: 0.99,
                    condition: RuleCondition(field: .host, operation: .equals, value: "first.example.com")
                ),
                suggestion(
                    kind: .personal,
                    confidence: 0.99,
                    condition: RuleCondition(field: .host, operation: .equals, value: "second.example.com")
                )
            ],
            harness: .claudeCode,
            harnessVersion: nil,
            automaticallyApply: true,
            maximumAutomaticRules: 1
        )

        #expect(summary.automaticallyAppliedCount == 1)
        #expect(summary.recommendationCount == 1)
        #expect(try store.reviewSegments().count == 1)
    }

    @Test
    func undoDisablesRuleThatAutomaticRunReenabled() throws {
        let store = try makeStore()
        let condition = RuleCondition(field: .host, operation: .equals, value: "github.com")
        let rule = Rule(
            name: "Remember github.com",
            priority: 150,
            enabled: false,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [condition]
        )
        try store.saveRule(rule)
        try saveReviewSegment(classifiedSegment(url: "https://github.com/openai/codex").segment, in: store)

        let summary = try store.processReviewAISuggestions(
            [suggestion(kind: .work, confidence: 0.99, condition: condition)],
            harness: .codex,
            harnessVersion: nil,
            automaticallyApply: true
        )
        let undo = try store.undoReviewAIRun(id: summary.id)

        #expect(undo.revertedRuleCount == 1)
        #expect(try store.loadRules().first { $0.id == rule.id }?.enabled == false)
        #expect(try store.reviewSegments().count == 1)
    }

    @Test
    func undoKeepsRuleThatExistedBeforeAutomaticRun() throws {
        let store = try makeStore()
        let condition = RuleCondition(field: .host, operation: .equals, value: "github.com")
        let rule = Rule(
            name: "Remember github.com",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [condition]
        )
        try store.saveRule(rule)
        try saveReviewSegment(classifiedSegment(url: "https://github.com/openai/codex").segment, in: store)

        let summary = try store.processReviewAISuggestions(
            [suggestion(kind: .work, confidence: 0.99, condition: condition)],
            harness: .pi,
            harnessVersion: nil,
            automaticallyApply: true
        )
        let undo = try store.undoReviewAIRun(id: summary.id)

        #expect(undo.unchangedRuleCount == 1)
        #expect(try store.loadRules().contains { $0.id == rule.id && $0.enabled })
        #expect(try store.reviewSegments().isEmpty)
    }

    @Test
    func higherPriorityReviewRuleBlocksAutomaticApply() throws {
        let store = try makeStore()
        let condition = RuleCondition(field: .host, operation: .equals, value: "github.com")
        try store.saveRule(
            Rule(
                name: "Keep GitHub for review",
                priority: 100,
                enabled: true,
                isBuiltIn: false,
                action: RuleAction(kind: .review, categoryID: nil, projectID: nil),
                conditions: [
                    RuleCondition(field: .host, operation: .equals, value: "github.com")
                ]
            )
        )
        try saveReviewSegment(classifiedSegment(url: "https://github.com/openai/codex").segment, in: store)

        let summary = try store.processReviewAISuggestions(
            [suggestion(kind: .work, confidence: 0.99, condition: condition)],
            harness: .codex,
            harnessVersion: nil,
            automaticallyApply: true
        )

        #expect(summary.automaticallyAppliedCount == 0)
        #expect(try store.reviewSegments().count == 1)
        #expect(try store.loadRules().contains { $0.name == "Remember github.com" } == false)
    }

    private func makeStore() throws -> HagoStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try HagoStore(databaseURL: directory.appendingPathComponent("hago.sqlite"))
    }

    private func saveReviewSegment(_ segment: ActivitySegment, in store: HagoStore) throws {
        try store.save(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
    }

    private func suggestion(
        kind: ReviewAISuggestionKind,
        confidence: Double,
        condition: RuleCondition,
        relatedRuleKinds: [ActivityKind] = []
    ) -> ReviewAISuggestion {
        ReviewAISuggestion(
            kind: kind,
            confidence: confidence,
            reason: "Test",
            proposedRuleCondition: condition,
            affectedCount: 1,
            affectedDuration: 120,
            samples: [
                ReviewAISuggestionSample(
                    appName: "Google Chrome",
                    bundleIdentifier: "com.google.Chrome",
                    windowTitle: "Test",
                    url: nil,
                    duration: 120
                )
            ],
            relatedRuleKinds: relatedRuleKinds
        )
    }

    private func classifiedSegment(
        appName: String = "Google Chrome",
        bundleIdentifier: String = "com.google.Chrome",
        windowTitle: String = "Test",
        url: String?,
        source: ActivitySource = .chrome,
        offset: TimeInterval = 0
    ) -> ClassifiedSegment {
        let start = Date().addingTimeInterval(offset)
        let segment = ActivitySegment(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            snapshot: ActivitySnapshot(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                processIdentifier: 1,
                windowTitle: windowTitle,
                url: url,
                source: source
            )
        )

        return ClassifiedSegment(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            ),
            projectName: nil,
            categoryName: nil,
            ruleName: nil
        )
    }
}
