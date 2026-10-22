import Foundation
import SQLite3

public enum HagoStoreError: Error, LocalizedError {
    case failedToOpenDatabase(String)
    case failedToPrepare(String)
    case failedToStep(String)
    case missingDatabase

    public var errorDescription: String? {
        switch self {
        case .failedToOpenDatabase(let message):
            "Could not open database: \(message)"
        case .failedToPrepare(let message):
            "Could not prepare database statement: \(message)"
        case .failedToStep(let message):
            "Could not execute database statement: \(message)"
        case .missingDatabase:
            "Database connection is missing."
        }
    }
}

public enum ReclassificationScope: String, CaseIterable, Identifiable {
    case today
    case allHistory

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .today:
            "Today"
        case .allHistory:
            "All History"
        }
    }
}

private enum SQLiteValue {
    case text(String?)
    case integer(Int)
    case double(Double)
    case bool(Bool)
}

private struct ReclassificationCandidate {
    var segment: ActivitySegment
    var classification: SegmentClassification
}

private struct SQLPredicate {
    var sql: String
    var bindings: [SQLiteValue]
    var indexName: String?
}

private struct ReviewAISuggestionApplyResult {
    var ruleID: UUID
    var ruleChange: ReviewAIRuleChange
    var condition: RuleCondition
    var appliedKind: ActivityKind
}

private struct ReviewAISuggestionApplyPlan {
    var rule: Rule
    var ruleChange: ReviewAIRuleChange
    var condition: RuleCondition
    var appliedKind: ActivityKind
}

private struct ReviewAIAuditDecision {
    var ruleID: UUID?
    var ruleChange: ReviewAIRuleChange?
    var condition: RuleCondition?
    var appliedKind: ActivityKind?
}

public final class HagoStore {
    private var database: OpaquePointer?
    private let classifier = ActivityClassifier()

    public init(databaseURL: URL) throws {
        var connection: OpaquePointer?

        if sqlite3_open(databaseURL.path, &connection) != SQLITE_OK {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw HagoStoreError.failedToOpenDatabase(message)
        }

        database = connection
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
        try seedIfNeeded()
        try deduplicateRememberedRules()
        try repairUnverifiedDiscordClassifications()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public static func defaultDatabaseURL() throws -> URL {
        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return try defaultDatabaseURL(in: supportURL)
    }

    static func defaultDatabaseURL(in supportURL: URL) throws -> URL {
        let hagoDirectory = supportURL.appendingPathComponent("Hago", isDirectory: true)
        let hagoDatabase = hagoDirectory.appendingPathComponent("hago.sqlite")
        let legacyDatabase = supportURL
            .appendingPathComponent("Worklog", isDirectory: true)
            .appendingPathComponent("worklog.sqlite")

        if FileManager.default.fileExists(atPath: hagoDatabase.path) {
            return hagoDatabase
        }

        // Keep the legacy database beside its WAL and SHM files until a safe migration is available.
        if FileManager.default.fileExists(atPath: legacyDatabase.path) {
            return legacyDatabase
        }

        try FileManager.default.createDirectory(
            at: hagoDirectory,
            withIntermediateDirectories: true
        )

        return hagoDatabase
    }

    public func save(segment: ActivitySegment, classification: SegmentClassification) throws {
        guard classification.kind != .ignored else {
            return
        }

        try transaction {
            try insertSegment(segment, classification: classification)
        }
    }

    public func checkpoint(segment: ActivitySegment, classification: SegmentClassification) throws {
        guard classification.kind != .ignored else { return }
        try transaction {
            if try loadClassification(segmentID: segment.id) != nil {
                try execute(
                    "UPDATE activity_segments SET ended_at = MAX(ended_at, ?) WHERE id = ?",
                    bindings: [.double(segment.endedAt.timeIntervalSince1970), .text(segment.id.uuidString)]
                )
            } else {
                try insertSegment(segment, classification: classification)
            }
        }
    }

    public func removeTime(segmentID: UUID, from start: Date, to end: Date) throws {
        try transaction {
            let segments = try query(
                "SELECT id, started_at, ended_at, app_name, bundle_id, process_id, window_title, url, source FROM activity_segments WHERE id = ?",
                bindings: [.text(segmentID.uuidString)], map: activitySegmentColumn
            )
            guard let segment = segments.first,
                  let classification = try loadClassification(segmentID: segmentID),
                  start >= segment.startedAt, end <= segment.endedAt, start < end else {
                throw HagoStoreError.failedToStep("Choose a non-empty range inside the recorded interval. Reload if it has changed.")
            }
            try deleteSegment(id: segmentID)
            for (lower, upper) in [(segment.startedAt, start), (end, segment.endedAt)] where lower < upper {
                let remainder = ActivitySegment(startedAt: lower, endedAt: upper, snapshot: segment.snapshot)
                let retained = SegmentClassification(
                    segmentID: remainder.id, kind: classification.kind,
                    categoryID: classification.categoryID, projectID: classification.projectID,
                    ruleID: classification.ruleID, isManual: classification.isManual
                )
                try insertSegment(remainder, classification: retained)
            }
        }
    }

    private func insertSegment(_ segment: ActivitySegment, classification: SegmentClassification) throws {
        try execute(
            """
            INSERT OR REPLACE INTO activity_segments (
                id,
                started_at,
                ended_at,
                app_name,
                bundle_id,
                process_id,
                window_title,
                url,
                source,
                host,
                app_name_normalized,
                bundle_id_normalized,
                window_title_normalized,
                url_normalized
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(segment.id.uuidString),
                .double(segment.startedAt.timeIntervalSince1970),
                .double(segment.endedAt.timeIntervalSince1970),
                .text(segment.appName),
                .text(segment.bundleIdentifier),
                .integer(Int(segment.processIdentifier)),
                .text(segment.windowTitle),
                .text(segment.url),
                .text(segment.source.rawValue),
                .text(host(from: segment.url)),
                .text(normalizedSearchValue(segment.appName)),
                .text(normalizedSearchValue(segment.bundleIdentifier)),
                .text(normalizedSearchValue(segment.windowTitle)),
                .text(normalizedSearchValue(segment.url))
            ]
        )

        try saveClassification(classification)
    }

    public func loadRules() throws -> [Rule] {
        let rules = try query(
            """
            SELECT id, name, priority, enabled, is_built_in, action_kind, category_id, project_id
            FROM rules
            ORDER BY priority ASC, name ASC
            """
        ) { statement in
            Rule(
                id: uuidColumn(statement, 0),
                name: stringColumn(statement, 1),
                priority: intColumn(statement, 2),
                enabled: boolColumn(statement, 3),
                isBuiltIn: boolColumn(statement, 4),
                action: RuleAction(
                    kind: ActivityKind(rawValue: stringColumn(statement, 5)) ?? .review,
                    categoryID: optionalUUIDColumn(statement, 6),
                    projectID: optionalUUIDColumn(statement, 7)
                ),
                conditions: []
            )
        }

        var populatedRules: [Rule] = []
        for var rule in rules {
            rule.conditions = try loadConditions(ruleID: rule.id)
            populatedRules.append(rule)
        }

        return populatedRules
    }

    public func ruleReviewRecords() throws -> [RuleReviewRecord] {
        try ruleReviewRecords(for: loadRules())
    }

    public func ruleReviewRecords(for rules: [Rule]) throws -> [RuleReviewRecord] {
        let matchCounts = Dictionary(
            uniqueKeysWithValues: try query(
                """
                SELECT rule_id, COUNT(*)
                FROM classifications
                WHERE rule_id IS NOT NULL
                GROUP BY rule_id
                """
            ) { statement in
                (uuidColumn(statement, 0), intColumn(statement, 1))
            }
        )
        let aiRuleIDs = Set(
            try query(
                """
                SELECT DISTINCT rule_id
                FROM review_ai_decisions
                WHERE disposition = ? AND rule_id IS NOT NULL
                """,
                bindings: [.text(ReviewAIDecisionDisposition.automaticallyApplied.rawValue)]
            ) { statement in
                uuidColumn(statement, 0)
            }
        )
        let rulesByMatch = Dictionary(grouping: rules.filter(\.enabled), by: ruleMatchSignature)

        return rules.map { rule in
            let matchingRules = rulesByMatch[ruleMatchSignature(rule)] ?? []
            let matchingKinds = Set(matchingRules.map(\.action.kind))
            var issues: Set<RuleReviewIssue> = []

            if rule.enabled, matchingKinds.count > 1 {
                issues.insert(.conflict)
            }
            if rule.enabled, matchingRules.filter({ $0.action.kind == rule.action.kind }).count > 1 {
                issues.insert(.duplicate)
            }

            let matchedSegmentCount = matchCounts[rule.id] ?? 0

            let origin: RuleOrigin
            if rule.isBuiltIn {
                origin = .builtIn
            } else if aiRuleIDs.contains(rule.id) {
                origin = .ai
            } else if rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().hasPrefix("remember ") {
                origin = .learned
            } else {
                origin = .custom
            }

            return RuleReviewRecord(
                rule: rule,
                origin: origin,
                matchedSegmentCount: matchedSegmentCount,
                issues: issues
            )
        }
    }

    public func saveRule(_ rule: Rule) throws {
        try execute(
            """
            INSERT OR REPLACE INTO rules (
                id,
                name,
                priority,
                enabled,
                is_built_in,
                action_kind,
                category_id,
                project_id
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(rule.id.uuidString),
                .text(rule.name),
                .integer(rule.priority),
                .bool(rule.enabled),
                .bool(rule.isBuiltIn),
                .text(rule.action.kind.rawValue),
                .text(rule.action.categoryID?.uuidString),
                .text(rule.action.projectID?.uuidString)
            ]
        )

        try execute("DELETE FROM rule_conditions WHERE rule_id = ?", bindings: [.text(rule.id.uuidString)])

        for condition in rule.conditions {
            try execute(
                """
                INSERT INTO rule_conditions (id, rule_id, field, operation, value)
                VALUES (?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(condition.id.uuidString),
                    .text(rule.id.uuidString),
                    .text(condition.field.rawValue),
                    .text(condition.operation.rawValue),
                    .text(condition.value)
                ]
            )
        }
    }

    @discardableResult
    public func saveRememberedRule(_ rule: Rule) throws -> UUID {
        guard let signature = rememberedRuleSignature(rule) else {
            try saveRule(rule)
            return rule.id
        }

        if var existingRule = try loadRules().first(where: { rememberedRuleSignature($0) == signature }) {
            if !existingRule.enabled {
                existingRule.enabled = true
                try saveRule(existingRule)
            }

            return existingRule.id
        }

        try saveRule(rule)
        return rule.id
    }

    public func deduplicateRememberedRules() throws {
        let rememberedRuleGroups = Dictionary(grouping: try loadRules()) { rule in
            rememberedRuleSignature(rule)
        }
        .compactMap { signature, rules in
            signature == nil ? nil : rules
        }

        for rules in rememberedRuleGroups where rules.count > 1 {
            let sortedRules = rules.sorted(by: preferredRememberedRule)
            guard let keeper = sortedRules.first else {
                continue
            }

            for duplicate in sortedRules.dropFirst() {
                try execute(
                    """
                    UPDATE classifications
                    SET rule_id = ?
                    WHERE rule_id = ?
                    """,
                    bindings: [
                        .text(keeper.id.uuidString),
                        .text(duplicate.id.uuidString)
                    ]
                )
                try deleteRule(id: duplicate.id)
            }
        }
    }

    public func deleteRule(id: UUID) throws {
        try execute("DELETE FROM rule_conditions WHERE rule_id = ?", bindings: [.text(id.uuidString)])
        try execute("DELETE FROM rules WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func loadCategories() throws -> [Category] {
        try query(
            """
            SELECT id, name, kind, color_hex
            FROM categories
            ORDER BY name ASC
            """
        ) { statement in
            Category(
                id: uuidColumn(statement, 0),
                name: stringColumn(statement, 1),
                kind: ActivityKind(rawValue: stringColumn(statement, 2)) ?? .review,
                colorHex: stringColumn(statement, 3)
            )
        }
    }

    public func saveCategory(_ category: Category) throws {
        try execute(
            """
            INSERT INTO categories (id, name, kind, color_hex)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                kind = excluded.kind,
                color_hex = excluded.color_hex
            """,
            bindings: [
                .text(category.id.uuidString),
                .text(category.name),
                .text(category.kind.rawValue),
                .text(category.colorHex)
            ]
        )
    }

    public func deleteCategory(id: UUID) throws {
        try execute("DELETE FROM categories WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func loadProjects() throws -> [Project] {
        try query(
            """
            SELECT id, name, color_hex, is_archived
            FROM projects
            ORDER BY is_archived ASC, name ASC
            """
        ) { statement in
            Project(
                id: uuidColumn(statement, 0),
                name: stringColumn(statement, 1),
                colorHex: stringColumn(statement, 2),
                isArchived: boolColumn(statement, 3)
            )
        }
    }

    public func saveProject(_ project: Project) throws {
        try execute(
            """
            INSERT INTO projects (id, name, color_hex, is_archived)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                color_hex = excluded.color_hex,
                is_archived = excluded.is_archived
            """,
            bindings: [
                .text(project.id.uuidString),
                .text(project.name),
                .text(project.colorHex),
                .bool(project.isArchived)
            ]
        )
    }

    public func deleteProject(id: UUID) throws {
        try execute("UPDATE rules SET project_id = NULL WHERE project_id = ?", bindings: [.text(id.uuidString)])
        try execute("DELETE FROM projects WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    public func overrideSegment(id: UUID, kind: ActivityKind, projectID: UUID?, categoryID: UUID?) throws {
        let classification = SegmentClassification(
            segmentID: id,
            kind: kind,
            categoryID: categoryID,
            projectID: projectID,
            ruleID: nil,
            isManual: true
        )

        try saveClassification(classification)
    }

    public func ignoreSegment(id: UUID) throws {
        try deleteSegment(id: id)
    }

    public func resolveReviewSegments(ids: [UUID], kind: ActivityKind, categoryID: UUID?) throws {
        guard kind != .review else { return }
        let selectedIDs = Set(ids)
        try transaction {
            for item in try reviewSegments() where selectedIDs.contains(item.id) {
                if kind == .ignored {
                    try ignoreSegment(id: item.id)
                } else {
                    try overrideSegment(
                        id: item.id,
                        kind: kind,
                        projectID: item.classification.projectID,
                        categoryID: categoryID
                    )
                }
            }
        }
    }

    public func reclassify(scope: ReclassificationScope, preserveProjects: Bool = false) throws {
        let startDate: Date?
        switch scope {
        case .today:
            startDate = dayInterval(for: Date()).start
        case .allHistory:
            startDate = nil
        }

        try transaction {
            let rules = classifier.preparedRules(from: try loadRules())
            let candidates = try reclassificationCandidates(startDate: startDate)

            for candidate in candidates {
                let result = classifier.classify(snapshot: candidate.segment.snapshot, preparedRules: rules)
                try applyReclassificationResult(result, to: candidate, preserveProject: preserveProjects)
            }
        }
    }

    public func reclassify(ruleID: UUID, scope: ReclassificationScope, preserveProjects: Bool = false) throws {
        let startDate: Date?
        switch scope {
        case .today:
            startDate = dayInterval(for: Date()).start
        case .allHistory:
            startDate = nil
        }

        try transaction {
            let rules = classifier.preparedRules(from: try loadRules())
            guard let rule = rules.first(where: { $0.id == ruleID }) else {
                return
            }

            let candidates = try reclassificationCandidates(matching: rule, startDate: startDate)
            for candidate in candidates where classifier.matches(rule: rule, snapshot: candidate.segment.snapshot) {
                let result = classifier.classify(snapshot: candidate.segment.snapshot, preparedRules: rules)
                try applyReclassificationResult(result, to: candidate, preserveProject: preserveProjects)
            }
        }
    }

    @discardableResult
    public func applyReviewAISuggestion(_ suggestion: ReviewAISuggestion) throws -> UUID? {
        try applyReviewAISuggestionWithResult(suggestion)?.ruleID
    }

    public func loadReviewAIScheduleState() throws -> ReviewAIScheduleState {
        let payload = try query("SELECT payload FROM review_ai_schedule WHERE id = 1") {
            stringColumn($0, 0)
        }.first
        guard let payload else { return ReviewAIScheduleState() }
        return try JSONDecoder().decode(ReviewAIScheduleState.self, from: Data(payload.utf8))
    }

    public func saveReviewAIScheduleState(_ state: ReviewAIScheduleState) throws {
        let payload = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try execute(
            "INSERT INTO review_ai_schedule (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload",
            bindings: [.text(payload)]
        )
    }

    public func loadReviewAICache() throws -> [String: ReviewAICachedSuggestion] {
        let entries = try query("SELECT group_id, payload FROM review_ai_cache") { statement in
            let value = try JSONDecoder().decode(
                ReviewAICachedSuggestion.self, from: Data(stringColumn(statement, 1).utf8)
            )
            return (stringColumn(statement, 0), value)
        }
        return Dictionary(uniqueKeysWithValues: entries)
    }

    public func saveReviewAICache(_ entries: [ReviewAICachedSuggestion]) throws {
        try transaction {
            for entry in entries {
                let payload = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
                try execute(
                    "INSERT INTO review_ai_cache (group_id, payload) VALUES (?, ?) ON CONFLICT(group_id) DO UPDATE SET payload = excluded.payload",
                    bindings: [.text(entry.suggestion.id), .text(payload)]
                )
            }
        }
    }

    public func reconcileReviewWithExistingRules() throws -> Int {
        let preparedRules = classifier.preparedRules(from: try loadRules())
        let entries = try reviewSegments().filter { !$0.classification.isManual }
        var count = 0
        try transaction {
            for entry in entries {
                let result = classifier.classify(snapshot: entry.segment.snapshot, preparedRules: preparedRules)
                guard result.ruleID != nil, result.kind == .work || result.kind == .personal else { continue }
                try applyReclassificationResult(
                    result, to: ReclassificationCandidate(segment: entry.segment, classification: entry.classification),
                    preserveProject: true
                )
                count += 1
            }
        }
        return count
    }

    public func processReviewAISuggestions(
        _ suggestions: [ReviewAISuggestion],
        harness: ReviewAIHarnessKind,
        harnessVersion: String?,
        automaticallyApply: Bool,
        maximumAutomaticRules: Int = 10
    ) throws -> ReviewAIRunSummary {
        let runID = UUID()
        let createdAt = Date()
        try execute(
            """
            INSERT INTO review_ai_runs (
                id, created_at, harness, harness_version, schema_version, decision_count,
                automatically_applied_count, recommendation_count, status
            ) VALUES (?, ?, ?, ?, 1, ?, 0, 0, ?)
            """,
            bindings: [
                .text(runID.uuidString),
                .double(createdAt.timeIntervalSince1970),
                .text(harness.rawValue),
                .text(harnessVersion),
                .integer(suggestions.count),
                .text(ReviewAIRunStatus.running.rawValue)
            ]
        )

        let validator = ReviewAISuggestionValidator()
        var automaticallyAppliedCount = 0

        do {
            for suggestion in suggestions {
                var disposition = ReviewAIDecisionDisposition.recommended

                if automaticallyApply, automaticallyAppliedCount < maximumAutomaticRules {
                    switch validator.automaticValidationResult(for: suggestion) {
                    case .applyAllowed:
                        guard let plan = try reviewAISuggestionApplyPlan(suggestion) else {
                            try recordReviewAIDecision(
                                runID: runID,
                                suggestion: suggestion,
                                disposition: .stale,
                                audit: ReviewAIAuditDecision()
                            )
                            continue
                        }
                        guard try automaticReviewPlanPreservesClassifiedActivity(plan) else {
                            try recordReviewAIDecision(
                                runID: runID, suggestion: suggestion, disposition: .recommended,
                                audit: ReviewAIAuditDecision()
                            )
                            continue
                        }
                        let audit = ReviewAIAuditDecision(
                            ruleID: plan.rule.id,
                            ruleChange: plan.ruleChange,
                            condition: plan.condition,
                            appliedKind: plan.appliedKind
                        )
                        let decisionID = try recordReviewAIDecision(
                            runID: runID,
                            suggestion: suggestion,
                            disposition: .pendingAutomaticApply,
                            audit: audit
                        )
                        if try applyReviewAISuggestion(plan) != nil {
                            automaticallyAppliedCount += 1
                            try updateReviewAIDecision(
                                id: decisionID,
                                disposition: .automaticallyApplied
                            )
                        } else {
                            try updateReviewAIDecision(id: decisionID, disposition: .stale)
                        }
                        continue
                    case .manualOnly:
                        disposition = .recommended
                    case .rejected:
                        disposition = .rejected
                    }
                }

                try recordReviewAIDecision(
                    runID: runID,
                    suggestion: suggestion,
                    disposition: disposition,
                    audit: ReviewAIAuditDecision()
                )
            }

            let recommendationCount = suggestions.count - automaticallyAppliedCount
            try execute(
                """
                UPDATE review_ai_runs
                SET automatically_applied_count = ?, recommendation_count = ?, status = ?
                WHERE id = ?
                """,
                bindings: [
                    .integer(automaticallyAppliedCount),
                    .integer(recommendationCount),
                    .text(ReviewAIRunStatus.completed.rawValue),
                    .text(runID.uuidString)
                ]
            )

            return ReviewAIRunSummary(
                id: runID,
                createdAt: createdAt,
                harness: harness,
                harnessVersion: harnessVersion,
                decisionCount: suggestions.count,
                automaticallyAppliedCount: automaticallyAppliedCount,
                recommendationCount: recommendationCount,
                status: .completed
            )
        } catch {
            try? execute(
                "UPDATE review_ai_runs SET status = ? WHERE id = ?",
                bindings: [.text(ReviewAIRunStatus.failed.rawValue), .text(runID.uuidString)]
            )
            throw error
        }
    }

    public func mostRecentReviewAIRun(appliedRulesOnly: Bool = false) throws -> ReviewAIRunSummary? {
        try query(
            """
            SELECT id, created_at, harness, harness_version, decision_count,
                   automatically_applied_count, recommendation_count, status
            FROM review_ai_runs
            WHERE (? = 0 OR automatically_applied_count > 0)
            ORDER BY created_at DESC
            LIMIT 1
            """,
            bindings: [.bool(appliedRulesOnly)]
        ) { statement in
            ReviewAIRunSummary(
                id: uuidColumn(statement, 0),
                createdAt: Date(timeIntervalSince1970: doubleColumn(statement, 1)),
                harness: ReviewAIHarnessKind(rawValue: stringColumn(statement, 2)) ?? .disabled,
                harnessVersion: optionalStringColumn(statement, 3),
                decisionCount: intColumn(statement, 4),
                automaticallyAppliedCount: intColumn(statement, 5),
                recommendationCount: intColumn(statement, 6),
                status: ReviewAIRunStatus(rawValue: stringColumn(statement, 7)) ?? .completed
            )
        }
        .first
    }

    public func appliedReviewAIRules(runID: UUID) throws -> [ReviewAIAppliedRule] {
        let rulesByID = Dictionary(uniqueKeysWithValues: try loadRules().map { ($0.id, $0) })

        return try query(
            """
            SELECT id, rule_id, confidence, reason, rule_change, condition_field,
                   condition_operation, condition_value, applied_kind
            FROM review_ai_decisions
            WHERE run_id = ? AND disposition = ? AND rule_id IS NOT NULL
            ORDER BY confidence DESC, condition_value COLLATE NOCASE ASC
            """,
            bindings: [
                .text(runID.uuidString),
                .text(ReviewAIDecisionDisposition.automaticallyApplied.rawValue)
            ]
        ) { statement in
            let ruleID = uuidColumn(statement, 1)
            let condition = RuleCondition(
                field: RuleField(rawValue: stringColumn(statement, 5)) ?? .windowTitle,
                operation: RuleOperation(rawValue: stringColumn(statement, 6)) ?? .equals,
                value: stringColumn(statement, 7)
            )
            let appliedKind = ActivityKind(rawValue: stringColumn(statement, 8)) ?? .review
            let currentRule = rulesByID[ruleID]
            let state: ReviewAIAppliedRuleState
            if let currentRule {
                state = reviewAIRuleMatchesAudit(currentRule, condition: condition, kind: appliedKind)
                    ? .unchanged
                    : .changed
            } else {
                state = .removed
            }

            return ReviewAIAppliedRule(
                id: uuidColumn(statement, 0),
                ruleID: ruleID,
                confidence: doubleColumn(statement, 2),
                reason: stringColumn(statement, 3),
                ruleChange: ReviewAIRuleChange(rawValue: stringColumn(statement, 4)) ?? .created,
                appliedCondition: condition,
                appliedKind: appliedKind,
                currentRule: currentRule,
                state: state
            )
        }
    }

    public func undoReviewAIRun(id: UUID) throws -> ReviewAIUndoResult {
        let currentStatus = try query(
            "SELECT status FROM review_ai_runs WHERE id = ? LIMIT 1",
            bindings: [.text(id.uuidString)]
        ) { statement in
            ReviewAIRunStatus(rawValue: stringColumn(statement, 0)) ?? .failed
        }
        .first
        guard currentStatus == .completed || currentStatus == .failed else {
            return ReviewAIUndoResult(revertedRuleCount: 0, unchangedRuleCount: 0, conflictCount: 0)
        }

        let decisions = try reviewAIAuditDecisions(runID: id)
        var revertedRuleCount = 0
        var unchangedRuleCount = 0
        var conflictCount = 0

        for decision in decisions {
            guard let ruleID = decision.ruleID,
                  let ruleChange = decision.ruleChange,
                  let condition = decision.condition,
                  let appliedKind = decision.appliedKind else {
                conflictCount += 1
                continue
            }

            if ruleChange == .reused {
                unchangedRuleCount += 1
                continue
            }

            guard var rule = try loadRules().first(where: { $0.id == ruleID }),
                  try reviewAIRuleIsUnchanged(rule, condition: condition, kind: appliedKind) else {
                conflictCount += 1
                continue
            }

            switch ruleChange {
            case .created:
                try deleteRule(id: ruleID)
            case .reenabled:
                rule.enabled = false
                try saveRule(rule)
            case .reused:
                break
            }
            revertedRuleCount += 1
        }

        try reclassify(scope: .allHistory, preserveProjects: true)
        let status: ReviewAIRunStatus = conflictCount == 0 ? .undone : .partiallyUndone
        try execute(
            "UPDATE review_ai_runs SET status = ? WHERE id = ?",
            bindings: [.text(status.rawValue), .text(id.uuidString)]
        )
        return ReviewAIUndoResult(
            revertedRuleCount: revertedRuleCount,
            unchangedRuleCount: unchangedRuleCount,
            conflictCount: conflictCount
        )
    }

    private func applyReviewAISuggestionWithResult(
        _ suggestion: ReviewAISuggestion
    ) throws -> ReviewAISuggestionApplyResult? {
        guard let plan = try reviewAISuggestionApplyPlan(suggestion) else {
            return nil
        }
        return try applyReviewAISuggestion(plan)
    }

    private func reviewAISuggestionApplyPlan(
        _ suggestion: ReviewAISuggestion
    ) throws -> ReviewAISuggestionApplyPlan? {
        guard ReviewAISuggestionValidator().validationResult(for: suggestion).canApply,
              let condition = suggestion.proposedRuleCondition,
              let kind = suggestion.kind.activityKind else {
            return nil
        }

        guard try hasCurrentReviewMatch(for: condition) else {
            return nil
        }

        let categoryID = try loadCategories().first { $0.kind == kind }?.id
        let rule = Rule(
            name: "Remember \(condition.value) as \(kind.displayName.lowercased())",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: kind, categoryID: categoryID, projectID: nil),
            conditions: [condition]
        )
        let existingRule = try loadRules().first { rememberedRuleSignature($0) == rememberedRuleSignature(rule) }
        if var existingRule {
            let ruleChange: ReviewAIRuleChange = existingRule.enabled ? .reused : .reenabled
            existingRule.enabled = true
            return ReviewAISuggestionApplyPlan(
                rule: existingRule,
                ruleChange: ruleChange,
                condition: condition,
                appliedKind: kind
            )
        }

        return ReviewAISuggestionApplyPlan(
            rule: rule,
            ruleChange: .created,
            condition: condition,
            appliedKind: kind
        )
    }

    private func automaticReviewPlanPreservesClassifiedActivity(_ plan: ReviewAISuggestionApplyPlan) throws -> Bool {
        var rules = try loadRules().filter { $0.id != plan.rule.id }
        rules.append(plan.rule)
        let prepared = classifier.preparedRules(from: rules)
        for candidate in try reclassificationCandidates(matching: plan.rule, startDate: nil)
            where candidate.classification.kind != .review
                && classifier.matches(rule: plan.rule, snapshot: candidate.segment.snapshot) {
            let result = classifier.classify(snapshot: candidate.segment.snapshot, preparedRules: prepared)
            if result.kind != candidate.classification.kind
                || result.categoryID != candidate.classification.categoryID
                || (candidate.classification.projectID ?? result.projectID) != candidate.classification.projectID {
                return false
            }
        }
        return true
    }

    private func applyReviewAISuggestion(
        _ plan: ReviewAISuggestionApplyPlan
    ) throws -> ReviewAISuggestionApplyResult? {
        let ruleID = try saveRememberedRule(plan.rule)
        try reclassify(ruleID: ruleID, scope: .allHistory, preserveProjects: true)

        guard try !hasCurrentReviewMatch(for: plan.condition) else {
            try rollbackReviewAIRuleChange(plan.ruleChange, ruleID: ruleID)
            return nil
        }

        return ReviewAISuggestionApplyResult(
            ruleID: ruleID,
            ruleChange: plan.ruleChange,
            condition: plan.condition,
            appliedKind: plan.appliedKind
        )
    }

    private func rollbackReviewAIRuleChange(
        _ change: ReviewAIRuleChange,
        ruleID: UUID
    ) throws {
        switch change {
        case .created:
            try deleteRule(id: ruleID)
        case .reenabled:
            if var rule = try loadRules().first(where: { $0.id == ruleID }) {
                rule.enabled = false
                try saveRule(rule)
            }
        case .reused:
            break
        }
        try reclassify(scope: .allHistory)
    }

    @discardableResult
    private func recordReviewAIDecision(
        runID: UUID,
        suggestion: ReviewAISuggestion,
        disposition: ReviewAIDecisionDisposition,
        audit: ReviewAIAuditDecision
    ) throws -> UUID {
        let decisionID = UUID()
        try execute(
            """
            INSERT INTO review_ai_decisions (
                id, run_id, group_id, suggested_kind, confidence, reason, disposition,
                rule_id, rule_change, condition_field, condition_operation,
                condition_value, applied_kind
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(decisionID.uuidString),
                .text(runID.uuidString),
                .text(suggestion.id),
                .text(suggestion.kind.rawValue),
                .double(suggestion.confidence),
                .text(suggestion.reason),
                .text(disposition.rawValue),
                .text(audit.ruleID?.uuidString),
                .text(audit.ruleChange?.rawValue),
                .text(audit.condition?.field.rawValue),
                .text(audit.condition?.operation.rawValue),
                .text(audit.condition?.value),
                .text(audit.appliedKind?.rawValue)
            ]
        )
        return decisionID
    }

    private func updateReviewAIDecision(
        id: UUID,
        disposition: ReviewAIDecisionDisposition
    ) throws {
        try execute(
            "UPDATE review_ai_decisions SET disposition = ? WHERE id = ?",
            bindings: [.text(disposition.rawValue), .text(id.uuidString)]
        )
    }

    private func reviewAIAuditDecisions(runID: UUID) throws -> [ReviewAIAuditDecision] {
        try query(
            """
            SELECT rule_id, rule_change, condition_field, condition_operation,
                   condition_value, applied_kind
            FROM review_ai_decisions
            WHERE run_id = ? AND disposition IN (?, ?)
            """,
            bindings: [
                .text(runID.uuidString),
                .text(ReviewAIDecisionDisposition.automaticallyApplied.rawValue),
                .text(ReviewAIDecisionDisposition.pendingAutomaticApply.rawValue)
            ]
        ) { statement in
            let field = optionalStringColumn(statement, 2).flatMap(RuleField.init(rawValue:))
            let operation = optionalStringColumn(statement, 3).flatMap(RuleOperation.init(rawValue:))
            let value = optionalStringColumn(statement, 4)
            let condition: RuleCondition?
            if let field, let operation, let value {
                condition = RuleCondition(field: field, operation: operation, value: value)
            } else {
                condition = nil
            }

            return ReviewAIAuditDecision(
                ruleID: optionalUUIDColumn(statement, 0),
                ruleChange: optionalStringColumn(statement, 1).flatMap(ReviewAIRuleChange.init(rawValue:)),
                condition: condition,
                appliedKind: optionalStringColumn(statement, 5).flatMap(ActivityKind.init(rawValue:))
            )
        }
    }

    private func reviewAIRuleIsUnchanged(
        _ rule: Rule,
        condition: RuleCondition,
        kind: ActivityKind
    ) throws -> Bool {
        let expectedCategoryID = try loadCategories().first { $0.kind == kind }?.id
        guard rule.enabled,
              !rule.isBuiltIn,
              rule.priority == 150,
              rule.action.kind == kind,
              rule.action.categoryID == expectedCategoryID,
              rule.action.projectID == nil,
              rule.conditions.count == 1,
              let currentCondition = rule.conditions.first else {
            return false
        }
        return currentCondition.field == condition.field
            && currentCondition.operation == condition.operation
            && currentCondition.value == condition.value
    }

    public func daySummary(for date: Date) throws -> DaySummary {
        let interval = dayInterval(for: date)
        let segments = ActivityAggregation.timeline(
            from: try classifiedSegments(startingAt: interval.start, endingBefore: interval.end, includingOverlaps: true),
            in: interval
        )

        var workSeconds: TimeInterval = 0
        var personalSeconds: TimeInterval = 0
        var reviewSeconds: TimeInterval = 0
        var appDurationsByKind: [ActivityKind: [String: TimeInterval]] = [:]
        var projectDurations: [String: TimeInterval] = [:]

        for item in segments {
            let duration = item.segment.duration
            switch item.classification.kind {
            case .work:
                workSeconds += duration
            case .personal:
                personalSeconds += duration
            case .review:
                reviewSeconds += duration
            case .ignored:
                continue
            }

            appDurationsByKind[item.classification.kind, default: [:]][appBucketName(for: item.segment), default: 0] += duration

            if let projectName = item.projectName {
                projectDurations[projectName, default: 0] += duration
            }
        }

        return DaySummary(
            date: interval.start,
            workSeconds: workSeconds,
            personalSeconds: personalSeconds,
            reviewSeconds: reviewSeconds,
            topApps: ActivityKind.allCases.flatMap { kind in
                buckets(from: appDurationsByKind[kind] ?? [:], kind: kind)
            },
            topProjects: buckets(from: projectDurations, kind: .work)
        )
    }

    public func dayTimeline(for date: Date) throws -> [ClassifiedSegment] {
        let interval = dayInterval(for: date)
        let segments = try classifiedSegments(startingAt: interval.start, endingBefore: interval.end, includingOverlaps: true)
        return ActivityAggregation.timeline(from: segments, in: interval)
    }

    public func weekSummary(containing date: Date) throws -> [WeekDaySummary] {
        let start = HagoCalendar.shared.weekStart(containing: date)

        return try (0..<7).map { offset in
            let day = Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
            let summary = try daySummary(for: day)

            return WeekDaySummary(
                date: summary.date,
                workSeconds: summary.workSeconds,
                personalSeconds: summary.personalSeconds,
                reviewSeconds: summary.reviewSeconds
            )
        }
    }

    public func reportSummary(for periodKind: ReportPeriodKind, containing date: Date) throws -> ReportSummary {
        let interval = reportInterval(for: periodKind, containing: date)
        let bucketKind: ReportBucketKind = periodKind == .week ? .day : .week

        return try reportSummary(
            for: periodKind,
            startingAt: interval.start,
            endingBefore: interval.end,
            bucketKind: bucketKind
        )
    }

    public func previousReportSummary(for periodKind: ReportPeriodKind, containing date: Date) throws -> ReportSummary {
        let interval = reportInterval(for: periodKind, containing: date)
        let previousDate: Date
        switch periodKind {
        case .week:
            previousDate = Calendar.current.date(byAdding: .day, value: -1, to: interval.start) ?? interval.start
        case .month:
            previousDate = Calendar.current.date(byAdding: .month, value: -1, to: interval.start) ?? interval.start
        }

        return try reportSummary(for: periodKind, containing: previousDate)
    }

    public func reviewSegments(for date: Date) throws -> [ClassifiedSegment] {
        let interval = dayInterval(for: date)

        return try classifiedSegments(startingAt: interval.start, endingBefore: interval.end, includingOverlaps: false)
            .filter { $0.classification.kind == .review }
    }

    public func reviewSegments() throws -> [ClassifiedSegment] {
        try query(
            """
            SELECT
                s.id,
                s.started_at,
                s.ended_at,
                s.app_name,
                s.bundle_id,
                s.process_id,
                s.window_title,
                s.url,
                s.source,
                c.kind,
                c.category_id,
                c.project_id,
                c.rule_id,
                c.is_manual,
                p.name,
                cat.name,
                r.name
            FROM activity_segments s
            JOIN classifications c ON c.segment_id = s.id
            LEFT JOIN projects p ON p.id = c.project_id
            LEFT JOIN categories cat ON cat.id = c.category_id
            LEFT JOIN rules r ON r.id = c.rule_id
            WHERE c.kind = ?
            ORDER BY s.started_at DESC
            """,
            bindings: [.text(ActivityKind.review.rawValue)]
        ) { statement in
            classifiedSegmentColumn(statement)
        }
    }

    public func activitySegments(for date: Date) throws -> [ClassifiedSegment] {
        let interval = dayInterval(for: date)

        return try classifiedSegments(startingAt: interval.start, endingBefore: interval.end, includingOverlaps: false)
            .sorted { first, second in
                first.segment.startedAt > second.segment.startedAt
            }
    }

    public func recentSegments(limit: Int) throws -> [ClassifiedSegment] {
        try query(
            """
            SELECT
                s.id,
                s.started_at,
                s.ended_at,
                s.app_name,
                s.bundle_id,
                s.process_id,
                s.window_title,
                s.url,
                s.source,
                c.kind,
                c.category_id,
                c.project_id,
                c.rule_id,
                c.is_manual,
                p.name,
                cat.name,
                r.name
            FROM activity_segments s
            JOIN classifications c ON c.segment_id = s.id
            LEFT JOIN projects p ON p.id = c.project_id
            LEFT JOIN categories cat ON cat.id = c.category_id
            LEFT JOIN rules r ON r.id = c.rule_id
            ORDER BY s.ended_at DESC
            LIMIT ?
            """,
            bindings: [.integer(limit)]
        ) { statement in
            classifiedSegmentColumn(statement)
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS categories (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                color_hex TEXT NOT NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                is_archived INTEGER NOT NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS rules (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                priority INTEGER NOT NULL,
                enabled INTEGER NOT NULL,
                is_built_in INTEGER NOT NULL,
                action_kind TEXT NOT NULL,
                category_id TEXT,
                project_id TEXT,
                FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS rule_conditions (
                id TEXT PRIMARY KEY,
                rule_id TEXT NOT NULL,
                field TEXT NOT NULL,
                operation TEXT NOT NULL,
                value TEXT NOT NULL,
                FOREIGN KEY(rule_id) REFERENCES rules(id) ON DELETE CASCADE
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS activity_segments (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                app_name TEXT NOT NULL,
                bundle_id TEXT NOT NULL,
                process_id INTEGER NOT NULL,
                window_title TEXT NOT NULL,
                url TEXT,
                source TEXT NOT NULL,
                host TEXT NOT NULL DEFAULT '',
                app_name_normalized TEXT NOT NULL DEFAULT '',
                bundle_id_normalized TEXT NOT NULL DEFAULT '',
                window_title_normalized TEXT NOT NULL DEFAULT '',
                url_normalized TEXT NOT NULL DEFAULT ''
            )
            """
        )

        var addedSearchColumn = false
        addedSearchColumn = try addActivitySegmentColumnIfMissing(
            name: "host",
            definition: "TEXT NOT NULL DEFAULT ''"
        ) || addedSearchColumn
        addedSearchColumn = try addActivitySegmentColumnIfMissing(
            name: "app_name_normalized",
            definition: "TEXT NOT NULL DEFAULT ''"
        ) || addedSearchColumn
        addedSearchColumn = try addActivitySegmentColumnIfMissing(
            name: "bundle_id_normalized",
            definition: "TEXT NOT NULL DEFAULT ''"
        ) || addedSearchColumn
        addedSearchColumn = try addActivitySegmentColumnIfMissing(
            name: "window_title_normalized",
            definition: "TEXT NOT NULL DEFAULT ''"
        ) || addedSearchColumn
        addedSearchColumn = try addActivitySegmentColumnIfMissing(
            name: "url_normalized",
            definition: "TEXT NOT NULL DEFAULT ''"
        ) || addedSearchColumn

        if addedSearchColumn {
            try backfillSegmentSearchColumns()
        }

        try execute(
            """
            CREATE TABLE IF NOT EXISTS classifications (
                segment_id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                category_id TEXT,
                project_id TEXT,
                rule_id TEXT,
                is_manual INTEGER NOT NULL,
                FOREIGN KEY(segment_id) REFERENCES activity_segments(id) ON DELETE CASCADE,
                FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE SET NULL,
                FOREIGN KEY(rule_id) REFERENCES rules(id) ON DELETE SET NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS review_ai_runs (
                id TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                harness TEXT NOT NULL,
                harness_version TEXT,
                schema_version INTEGER NOT NULL,
                decision_count INTEGER NOT NULL,
                automatically_applied_count INTEGER NOT NULL,
                recommendation_count INTEGER NOT NULL,
                status TEXT NOT NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS review_ai_decisions (
                id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL,
                group_id TEXT NOT NULL,
                suggested_kind TEXT NOT NULL,
                confidence REAL NOT NULL,
                reason TEXT NOT NULL,
                disposition TEXT NOT NULL,
                rule_id TEXT,
                rule_change TEXT,
                condition_field TEXT,
                condition_operation TEXT,
                condition_value TEXT,
                applied_kind TEXT,
                FOREIGN KEY(run_id) REFERENCES review_ai_runs(id) ON DELETE CASCADE
            )
            """
        )

        try execute("CREATE TABLE IF NOT EXISTS review_ai_schedule (id INTEGER PRIMARY KEY CHECK(id = 1), payload TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS review_ai_cache (group_id TEXT PRIMARY KEY, payload TEXT NOT NULL)")

        try execute("CREATE INDEX IF NOT EXISTS activity_segments_started_at_idx ON activity_segments(started_at)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_ended_at_idx ON activity_segments(ended_at)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_host_idx ON activity_segments(host)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_url_idx ON activity_segments(url)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_app_name_idx ON activity_segments(app_name)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_bundle_id_idx ON activity_segments(bundle_id)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_app_name_normalized_idx ON activity_segments(app_name_normalized)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_bundle_id_normalized_idx ON activity_segments(bundle_id_normalized)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_window_title_normalized_idx ON activity_segments(window_title_normalized)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_url_normalized_idx ON activity_segments(url_normalized)")
        try execute("CREATE INDEX IF NOT EXISTS classifications_kind_idx ON classifications(kind)")
        try execute("CREATE INDEX IF NOT EXISTS classifications_is_manual_idx ON classifications(is_manual)")
        try execute("CREATE INDEX IF NOT EXISTS rules_priority_idx ON rules(priority)")
        try execute("CREATE INDEX IF NOT EXISTS review_ai_runs_created_at_idx ON review_ai_runs(created_at)")
        try execute("CREATE INDEX IF NOT EXISTS review_ai_decisions_run_id_idx ON review_ai_decisions(run_id)")
        try deleteSystemSegments()
    }

    private func seedIfNeeded() throws {
        if try count(table: "categories") == 0 {
            for category in SeedData.categories {
                try saveCategory(category)
            }
        }

        if try count(table: "projects") == 0 {
            for project in SeedData.projects {
                try saveProject(project)
            }
        }

        if try count(table: "rules") == 0 {
            for rule in SeedData.rules {
                try saveRule(rule)
            }
        }

        try insertMissingBuiltInRules()
    }

    private func insertMissingBuiltInRules() throws {
        let existingRuleIDs = Set(try loadRules().map(\.id))
        var insertedRuleIDs: [UUID] = []

        for rule in SeedData.rules where rule.isBuiltIn && !existingRuleIDs.contains(rule.id) {
            try saveRule(rule)
            insertedRuleIDs.append(rule.id)
        }

        for ruleID in insertedRuleIDs {
            try reclassify(ruleID: ruleID, scope: .allHistory)
        }
    }

    private func repairUnverifiedDiscordClassifications() throws {
        let currentRules = try loadRules()
        guard let fallback = currentRules.first(where: {
            $0.id == UUID(uuidString: "30000000-0000-0000-0000-000000000004")
                && $0.isBuiltIn && $0.action.kind == .personal
        }) else { return }

        let candidates = try reclassificationCandidates(
            startDate: nil,
            predicate: SQLPredicate(
                sql: "s.app_name_normalized LIKE ? AND s.window_title_normalized = '' AND c.kind = ? AND c.rule_id = ?",
                bindings: [.text("%discord%"), .text(ActivityKind.personal.rawValue), .text(fallback.id.uuidString)],
                indexName: nil
            )
        )
        guard !candidates.isEmpty else { return }
        let rules = classifier.preparedRules(from: currentRules)

        try transaction {
            for candidate in candidates {
                let result = classifier.classify(snapshot: candidate.segment.snapshot, preparedRules: rules)
                guard result.kind == .review else { continue }
                try applyReclassificationResult(result, to: candidate, preserveProject: true)
            }
        }
    }

    private func count(table: String) throws -> Int {
        try query("SELECT COUNT(*) FROM \(table)") { statement in
            intColumn(statement, 0)
        }
        .first ?? 0
    }

    private func columnExists(table: String, column: String) throws -> Bool {
        try query("PRAGMA table_info(\(table))") { statement in
            stringColumn(statement, 1)
        }
        .contains(column)
    }

    private func addActivitySegmentColumnIfMissing(name: String, definition: String) throws -> Bool {
        guard try !columnExists(table: "activity_segments", column: name) else {
            return false
        }

        try execute("ALTER TABLE activity_segments ADD COLUMN \(name) \(definition)")
        return true
    }

    private func backfillSegmentSearchColumns() throws {
        let rows = try query(
            """
            SELECT id, app_name, bundle_id, window_title, url
            FROM activity_segments
            """
        ) { statement in
            (
                id: uuidColumn(statement, 0),
                appName: stringColumn(statement, 1),
                bundleIdentifier: stringColumn(statement, 2),
                windowTitle: stringColumn(statement, 3),
                url: optionalStringColumn(statement, 4)
            )
        }

        try transaction {
            for row in rows {
                try execute(
                    """
                    UPDATE activity_segments
                    SET host = ?,
                        app_name_normalized = ?,
                        bundle_id_normalized = ?,
                        window_title_normalized = ?,
                        url_normalized = ?
                    WHERE id = ?
                    """,
                    bindings: [
                        .text(host(from: row.url)),
                        .text(normalizedSearchValue(row.appName)),
                        .text(normalizedSearchValue(row.bundleIdentifier)),
                        .text(normalizedSearchValue(row.windowTitle)),
                        .text(normalizedSearchValue(row.url)),
                        .text(row.id.uuidString)
                    ]
                )
            }
        }
    }

    private func loadConditions(ruleID: UUID) throws -> [RuleCondition] {
        try query(
            """
            SELECT id, field, operation, value
            FROM rule_conditions
            WHERE rule_id = ?
            ORDER BY rowid ASC
            """,
            bindings: [.text(ruleID.uuidString)]
        ) { statement in
            RuleCondition(
                id: uuidColumn(statement, 0),
                field: RuleField(rawValue: stringColumn(statement, 1)) ?? .windowTitle,
                operation: RuleOperation(rawValue: stringColumn(statement, 2)) ?? .contains,
                value: stringColumn(statement, 3)
            )
        }
    }

    private func saveClassification(_ classification: SegmentClassification) throws {
        try execute(
            """
            INSERT OR REPLACE INTO classifications (
                segment_id,
                kind,
                category_id,
                project_id,
                rule_id,
                is_manual
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(classification.segmentID.uuidString),
                .text(classification.kind.rawValue),
                .text(classification.categoryID?.uuidString),
                .text(classification.projectID?.uuidString),
                .text(classification.ruleID?.uuidString),
                .bool(classification.isManual)
            ]
        )
    }

    private func loadClassification(segmentID: UUID) throws -> SegmentClassification? {
        try query(
            """
            SELECT segment_id, kind, category_id, project_id, rule_id, is_manual
            FROM classifications
            WHERE segment_id = ?
            """,
            bindings: [.text(segmentID.uuidString)]
        ) { statement in
            SegmentClassification(
                segmentID: uuidColumn(statement, 0),
                kind: ActivityKind(rawValue: stringColumn(statement, 1)) ?? .review,
                categoryID: optionalUUIDColumn(statement, 2),
                projectID: optionalUUIDColumn(statement, 3),
                ruleID: optionalUUIDColumn(statement, 4),
                isManual: boolColumn(statement, 5)
            )
        }
        .first
    }

    private func deleteSegment(id: UUID) throws {
        try execute("DELETE FROM activity_segments WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    private func deleteSystemSegments() throws {
        try execute(
            """
            DELETE FROM activity_segments
            WHERE lower(app_name) = 'loginwindow'
                OR lower(bundle_id) = 'com.apple.loginwindow'
            """
        )
    }

    private func applyReclassificationResult(
        _ result: ClassificationResult,
        to candidate: ReclassificationCandidate,
        preserveProject: Bool = false
    ) throws {
        if result.kind == .ignored {
            try deleteSegment(id: candidate.segment.id)
            return
        }

        let classification = SegmentClassification(
            segmentID: candidate.segment.id,
            kind: result.kind,
            categoryID: result.categoryID,
            projectID: preserveProject ? candidate.classification.projectID ?? result.projectID : result.projectID,
            ruleID: result.ruleID,
            isManual: false
        )

        guard classification != candidate.classification else {
            return
        }

        try saveClassification(classification)
    }

    private func reclassificationCandidates(startDate: Date?) throws -> [ReclassificationCandidate] {
        try reclassificationCandidates(startDate: startDate, predicate: nil)
    }

    private func reclassificationCandidates(matching rule: Rule, startDate: Date?) throws -> [ReclassificationCandidate] {
        try reclassificationCandidates(startDate: startDate, predicate: reclassificationPredicate(for: rule))
    }

    private func hasCurrentReviewMatch(for condition: RuleCondition) throws -> Bool {
        let rule = Rule(
            name: "Review AI freshness check",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .review, categoryID: nil, projectID: nil),
            conditions: [condition]
        )

        guard let predicate = reclassificationPredicate(for: rule) else {
            return false
        }

        var bindings = predicate.bindings
        bindings.append(.text(ActivityKind.review.rawValue))

        let indexHint = predicate.indexName.map { "INDEXED BY \($0)" } ?? ""
        return try query(
            """
            SELECT 1
            FROM activity_segments AS s \(indexHint)
            JOIN classifications c ON c.segment_id = s.id
            WHERE \(predicate.sql) AND c.kind = ?
            LIMIT 1
            """,
            bindings: bindings
        ) { _ in
            true
        }
        .first ?? false
    }

    private func reclassificationCandidates(
        startDate: Date?,
        predicate: SQLPredicate?
    ) throws -> [ReclassificationCandidate] {
        var clauses = ["c.is_manual = 0"]
        var bindings: [SQLiteValue] = []

        if let startDate {
            clauses.append("s.started_at >= ?")
            bindings.append(.double(startDate.timeIntervalSince1970))
        }

        if let predicate {
            clauses.append(predicate.sql)
            bindings.append(contentsOf: predicate.bindings)
        }

        let whereClause = clauses.joined(separator: " AND ")
        let indexHint = predicate?.indexName.map { "INDEXED BY \($0)" } ?? ""

        return try query(
            """
            SELECT
                s.id,
                s.started_at,
                s.ended_at,
                s.app_name,
                s.bundle_id,
                s.process_id,
                s.window_title,
                s.url,
                s.source,
                c.segment_id,
                c.kind,
                c.category_id,
                c.project_id,
                c.rule_id,
                c.is_manual
            FROM activity_segments AS s \(indexHint)
            JOIN classifications c ON c.segment_id = s.id
            WHERE \(whereClause)
            ORDER BY s.started_at ASC
            """,
            bindings: bindings
        ) { statement in
            reclassificationCandidateColumn(statement)
        }
    }

    private func reclassificationPredicate(for rule: Rule) -> SQLPredicate? {
        guard rule.conditions.count == 1, let condition = rule.conditions.first else {
            return nil
        }

        let value = normalizedSearchValue(condition.value)
        guard !value.isEmpty else {
            return nil
        }

        let expression: String
        let indexName: String
        switch condition.field {
        case .appName:
            expression = "s.app_name_normalized"
            indexName = "activity_segments_app_name_normalized_idx"
        case .bundleIdentifier:
            expression = "s.bundle_id_normalized"
            indexName = "activity_segments_bundle_id_normalized_idx"
        case .windowTitle:
            expression = "s.window_title_normalized"
            indexName = "activity_segments_window_title_normalized_idx"
        case .url:
            expression = "s.url_normalized"
            indexName = "activity_segments_url_normalized_idx"
        case .host:
            expression = "s.host"
            indexName = "activity_segments_host_idx"
        }

        switch condition.operation {
        case .contains:
            return SQLPredicate(
                sql: "\(expression) LIKE ? ESCAPE '\\'",
                bindings: [.text("%\(escapedLikeValue(value))%")],
                indexName: nil
            )
        case .equals:
            return SQLPredicate(sql: "\(expression) = ?", bindings: [.text(value)], indexName: indexName)
        case .domain:
            return SQLPredicate(
                sql: "(\(expression) = ? OR \(expression) LIKE ? ESCAPE '\\')",
                bindings: [.text(value), .text("%.\(escapedLikeValue(value))")],
                indexName: nil
            )
        case .startsWith:
            if let upperBound = searchUpperBound(afterPrefix: value) {
                return SQLPredicate(
                    sql: "\(expression) >= ? AND \(expression) < ?",
                    bindings: [.text(value), .text(upperBound)],
                    indexName: indexName
                )
            }

            return SQLPredicate(
                sql: "\(expression) LIKE ? ESCAPE '\\'",
                bindings: [.text("\(escapedLikeValue(value))%")],
                indexName: indexName
            )
        case .endsWith:
            return SQLPredicate(
                sql: "\(expression) LIKE ? ESCAPE '\\'",
                bindings: [.text("%\(escapedLikeValue(value))")],
                indexName: nil
            )
        case .regex:
            return nil
        }
    }

    private func loadSegments(startDate: Date?) throws -> [ActivitySegment] {
        if let startDate {
            return try query(
                """
                SELECT id, started_at, ended_at, app_name, bundle_id, process_id, window_title, url, source
                FROM activity_segments
                WHERE started_at >= ?
                ORDER BY started_at ASC
                """,
                bindings: [.double(startDate.timeIntervalSince1970)]
            ) { statement in
                activitySegmentColumn(statement)
            }
        }

        return try query(
            """
            SELECT id, started_at, ended_at, app_name, bundle_id, process_id, window_title, url, source
            FROM activity_segments
            ORDER BY started_at ASC
            """
        ) { statement in
            activitySegmentColumn(statement)
        }
    }

    private func classifiedSegments(startingAt start: Date, endingBefore end: Date, includingOverlaps: Bool) throws -> [ClassifiedSegment] {
        try query(
            """
            SELECT
                s.id,
                s.started_at,
                s.ended_at,
                s.app_name,
                s.bundle_id,
                s.process_id,
                s.window_title,
                s.url,
                s.source,
                c.kind,
                c.category_id,
                c.project_id,
                c.rule_id,
                c.is_manual,
                p.name,
                cat.name,
                r.name
            FROM activity_segments s
            JOIN classifications c ON c.segment_id = s.id
            LEFT JOIN projects p ON p.id = c.project_id
            LEFT JOIN categories cat ON cat.id = c.category_id
            LEFT JOIN rules r ON r.id = c.rule_id
            WHERE \(includingOverlaps ? "s.ended_at > ?" : "s.started_at >= ?") AND s.started_at < ?
            ORDER BY s.started_at ASC
            """,
            bindings: [
                .double(start.timeIntervalSince1970),
                .double(end.timeIntervalSince1970)
            ]
        ) { statement in
            classifiedSegmentColumn(statement)
        }
    }

    private func reportInterval(for periodKind: ReportPeriodKind, containing date: Date) -> DateInterval {
        switch periodKind {
        case .week:
            HagoCalendar.shared.weekInterval(containing: date)
        case .month:
            HagoCalendar.shared.monthInterval(containing: date)
        }
    }

    private func reportSummary(
        for periodKind: ReportPeriodKind,
        startingAt start: Date,
        endingBefore end: Date,
        bucketKind: ReportBucketKind
    ) throws -> ReportSummary {
        let interval = DateInterval(start: start, end: end)
        let segments = ActivityAggregation.timeline(
            from: try classifiedSegments(startingAt: start, endingBefore: end, includingOverlaps: true),
            in: interval
        )
        let totals = reportTotals(from: segments)

        return ReportSummary(
            periodKind: periodKind,
            startDate: start,
            endDate: end,
            workSeconds: totals.workSeconds,
            personalSeconds: totals.personalSeconds,
            reviewSeconds: totals.reviewSeconds,
            topApps: buckets(from: totals.appDurations, kind: .work),
            topProjects: buckets(from: totals.projectDurations, kind: .work),
            buckets: reportBuckets(
                from: segments,
                startingAt: start,
                endingBefore: end,
                bucketKind: bucketKind
            )
        )
    }

    private func reportTotals(from segments: [ClassifiedSegment]) -> (
        workSeconds: TimeInterval,
        personalSeconds: TimeInterval,
        reviewSeconds: TimeInterval,
        appDurations: [String: TimeInterval],
        projectDurations: [String: TimeInterval]
    ) {
        var workSeconds: TimeInterval = 0
        var personalSeconds: TimeInterval = 0
        var reviewSeconds: TimeInterval = 0
        var appDurations: [String: TimeInterval] = [:]
        var projectDurations: [String: TimeInterval] = [:]

        for item in segments {
            let duration = item.segment.duration

            switch item.classification.kind {
            case .work:
                workSeconds += duration
            case .personal:
                personalSeconds += duration
            case .review:
                reviewSeconds += duration
            case .ignored:
                continue
            }

            appDurations[appBucketName(for: item.segment), default: 0] += duration

            if let projectName = item.projectName {
                projectDurations[projectName, default: 0] += duration
            }
        }

        return (workSeconds, personalSeconds, reviewSeconds, appDurations, projectDurations)
    }

    private func reportBuckets(
        from segments: [ClassifiedSegment],
        startingAt start: Date,
        endingBefore end: Date,
        bucketKind: ReportBucketKind
    ) -> [ReportBucket] {
        intervals(startingAt: start, endingBefore: end, bucketKind: bucketKind).map { interval in
            let totals = reportTotals(
                from: ActivityAggregation.timeline(from: segments, in: interval)
            )

            return ReportBucket(
                startDate: interval.start,
                endDate: interval.end,
                workSeconds: totals.workSeconds,
                personalSeconds: totals.personalSeconds,
                reviewSeconds: totals.reviewSeconds
            )
        }
    }

    private func intervals(
        startingAt start: Date,
        endingBefore end: Date,
        bucketKind: ReportBucketKind
    ) -> [DateInterval] {
        let value = bucketKind == .day ? 1 : 7
        var intervals: [DateInterval] = []
        var currentStart = start

        while currentStart < end {
            let nextStart = Calendar.current.date(byAdding: .day, value: value, to: currentStart) ?? end
            let currentEnd = min(nextStart, end)
            intervals.append(DateInterval(start: currentStart, end: currentEnd))
            currentStart = currentEnd
        }

        return intervals
    }

    private func dayInterval(for date: Date) -> DateInterval {
        HagoCalendar.shared.dayInterval(containing: date)
    }

    private func buckets(from durations: [String: TimeInterval], kind: ActivityKind) -> [TimeBucket] {
        durations
            .sorted { first, second in
                if first.value == second.value {
                    return first.key.localizedCaseInsensitiveCompare(second.key) == .orderedAscending
                }

                return first.value > second.value
            }
            .prefix(8)
            .map { name, seconds in
                TimeBucket(id: "\(kind.rawValue)-\(name)", name: name, seconds: seconds, kind: kind)
            }
    }

    private func appBucketName(for segment: ActivitySegment) -> String {
        let host = segment.snapshot.host
        guard segment.source == .chrome, !host.isEmpty else {
            return segment.appName
        }

        return host
    }

    private func host(from url: String?) -> String {
        guard let url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            return ""
        }

        return URL(string: url)?.host?.lowercased() ?? ""
    }

    private func normalizedSearchValue(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func escapedLikeValue(_ value: String) -> String {
        var escaped = ""
        for character in value {
            if character == "%" || character == "_" || character == "\\" {
                escaped.append("\\")
            }

            escaped.append(character)
        }

        return escaped
    }

    private func searchUpperBound(afterPrefix prefix: String) -> String? {
        var scalars = Array(prefix.unicodeScalars)
        guard let last = scalars.popLast(),
              last.value < UInt32.max,
              let next = UnicodeScalar(last.value + 1) else {
            return nil
        }

        scalars.append(next)
        return String(String.UnicodeScalarView(scalars))
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        guard let database else {
            throw HagoStoreError.missingDatabase
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HagoStoreError.failedToPrepare(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw HagoStoreError.failedToStep(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func query<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        map: (OpaquePointer?) throws -> T
    ) throws -> [T] {
        guard let database else {
            throw HagoStoreError.missingDatabase
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HagoStoreError.failedToPrepare(String(cString: sqlite3_errmsg(database)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        try bind(bindings, to: statement)

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(try map(statement))
        }

        return rows
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            let sqliteIndex = Int32(index + 1)
            switch value {
            case .text(let text):
                if let text {
                    sqlite3_bind_text(statement, sqliteIndex, text, -1, sqliteTransient)
                } else {
                    sqlite3_bind_null(statement, sqliteIndex)
                }
            case .integer(let integer):
                sqlite3_bind_int64(statement, sqliteIndex, sqlite3_int64(integer))
            case .double(let double):
                sqlite3_bind_double(statement, sqliteIndex, double)
            case .bool(let bool):
                sqlite3_bind_int(statement, sqliteIndex, bool ? 1 : 0)
            }
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func rememberedRuleSignature(_ rule: Rule) -> RememberedRuleSignature? {
    guard !rule.isBuiltIn,
          !rule.conditions.isEmpty,
          rule.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("remember ") else {
        return nil
    }

    return RememberedRuleSignature(
        kind: rule.action.kind,
        categoryID: rule.action.categoryID,
        projectID: rule.action.projectID,
        conditions: rule.conditions
            .map { condition in
                [
                    condition.field.rawValue,
                    condition.operation.rawValue,
                    condition.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                ]
                    .joined(separator: "\u{1F}")
            }
            .sorted()
    )
}

private func ruleMatchSignature(_ rule: Rule) -> String {
    rule.conditions
        .map { condition in
            [
                condition.field.rawValue,
                condition.operation.rawValue,
                condition.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ]
                .joined(separator: "\u{1F}")
        }
        .sorted()
        .joined(separator: "\u{1E}")
}

private func reviewAIRuleMatchesAudit(
    _ rule: Rule,
    condition: RuleCondition,
    kind: ActivityKind
) -> Bool {
    guard rule.enabled,
          rule.action.kind == kind,
          rule.conditions.count == 1,
          let currentCondition = rule.conditions.first else {
        return false
    }

    return currentCondition.field == condition.field
        && currentCondition.operation == condition.operation
        && currentCondition.value.caseInsensitiveCompare(condition.value) == .orderedSame
}

private func preferredRememberedRule(_ first: Rule, _ second: Rule) -> Bool {
    if first.enabled != second.enabled {
        return first.enabled && !second.enabled
    }

    if first.priority != second.priority {
        return first.priority < second.priority
    }

    let nameOrder = first.name.localizedCaseInsensitiveCompare(second.name)
    if nameOrder != .orderedSame {
        return nameOrder == .orderedAscending
    }

    return first.id.uuidString < second.id.uuidString
}

private struct RememberedRuleSignature: Hashable {
    var kind: ActivityKind
    var categoryID: UUID?
    var projectID: UUID?
    var conditions: [String]
}

private func activitySegmentColumn(_ statement: OpaquePointer?) -> ActivitySegment {
    let snapshot = ActivitySnapshot(
        appName: stringColumn(statement, 3),
        bundleIdentifier: stringColumn(statement, 4),
        processIdentifier: Int32(intColumn(statement, 5)),
        windowTitle: stringColumn(statement, 6),
        url: optionalStringColumn(statement, 7),
        source: ActivitySource(rawValue: stringColumn(statement, 8)) ?? .macOS
    )

    return ActivitySegment(
        id: uuidColumn(statement, 0),
        startedAt: Date(timeIntervalSince1970: doubleColumn(statement, 1)),
        endedAt: Date(timeIntervalSince1970: doubleColumn(statement, 2)),
        snapshot: snapshot
    )
}

private func classifiedSegmentColumn(_ statement: OpaquePointer?) -> ClassifiedSegment {
    let segment = activitySegmentColumn(statement)
    let classification = SegmentClassification(
        segmentID: segment.id,
        kind: ActivityKind(rawValue: stringColumn(statement, 9)) ?? .review,
        categoryID: optionalUUIDColumn(statement, 10),
        projectID: optionalUUIDColumn(statement, 11),
        ruleID: optionalUUIDColumn(statement, 12),
        isManual: boolColumn(statement, 13)
    )

    return ClassifiedSegment(
        segment: segment,
        classification: classification,
        projectName: optionalStringColumn(statement, 14),
        categoryName: optionalStringColumn(statement, 15),
        ruleName: optionalStringColumn(statement, 16)
    )
}

private func reclassificationCandidateColumn(_ statement: OpaquePointer?) -> ReclassificationCandidate {
    ReclassificationCandidate(
        segment: activitySegmentColumn(statement),
        classification: SegmentClassification(
            segmentID: uuidColumn(statement, 9),
            kind: ActivityKind(rawValue: stringColumn(statement, 10)) ?? .review,
            categoryID: optionalUUIDColumn(statement, 11),
            projectID: optionalUUIDColumn(statement, 12),
            ruleID: optionalUUIDColumn(statement, 13),
            isManual: boolColumn(statement, 14)
        )
    )
}

private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String {
    guard let text = sqlite3_column_text(statement, index) else {
        return ""
    }

    return String(cString: text)
}

private func optionalStringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }

    return stringColumn(statement, index)
}

private func intColumn(_ statement: OpaquePointer?, _ index: Int32) -> Int {
    Int(sqlite3_column_int64(statement, index))
}

private func boolColumn(_ statement: OpaquePointer?, _ index: Int32) -> Bool {
    sqlite3_column_int(statement, index) == 1
}

private func doubleColumn(_ statement: OpaquePointer?, _ index: Int32) -> Double {
    sqlite3_column_double(statement, index)
}

private func uuidColumn(_ statement: OpaquePointer?, _ index: Int32) -> UUID {
    UUID(uuidString: stringColumn(statement, index)) ?? UUID()
}

private func optionalUUIDColumn(_ statement: OpaquePointer?, _ index: Int32) -> UUID? {
    guard let value = optionalStringColumn(statement, index) else {
        return nil
    }

    return UUID(uuidString: value)
}
