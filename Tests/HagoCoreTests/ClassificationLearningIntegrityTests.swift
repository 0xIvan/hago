import Foundation
import Testing
import SQLite3
@testable import HagoCore

@Suite
struct ClassificationLearningIntegrityTests {
    @Test
    func migrationRetainsDecisionsAndLegacyOrderAndMakesRestorableBackup() throws {
        let url = try databaseURL()
        let id = UUID()
        let customID = UUID()
        let date = Date().timeIntervalSince1970
        try sql(url, """
            CREATE TABLE activity_segments(id TEXT PRIMARY KEY, started_at REAL, ended_at REAL, app_name TEXT, bundle_id TEXT, process_id INTEGER, window_title TEXT, url TEXT, source TEXT);
            CREATE TABLE rules(id TEXT PRIMARY KEY, name TEXT, priority INTEGER, enabled INTEGER, is_built_in INTEGER, action_kind TEXT, category_id TEXT, project_id TEXT);
            CREATE TABLE classifications(segment_id TEXT PRIMARY KEY REFERENCES activity_segments(id) ON DELETE CASCADE, kind TEXT, category_id TEXT, project_id TEXT, rule_id TEXT REFERENCES rules(id) ON DELETE SET NULL, is_manual INTEGER);
            INSERT INTO rules VALUES ('20000000-0000-0000-0000-000000000014','Old Discord',180,1,1,'work',NULL,NULL);
            INSERT INTO rules VALUES ('\(customID.uuidString)','Earlier custom',40,1,0,'personal',NULL,NULL);
            INSERT INTO activity_segments VALUES ('\(id.uuidString)',\(date),\(date+60),'Xcode','com.apple.dt.Xcode',1,'Editor',NULL,'macOS');
            INSERT INTO classifications VALUES ('\(id.uuidString)','personal',NULL,NULL,NULL,1);
            """)
        let store = try HagoStore(databaseURL: url)
        let rules = try store.loadRules()
        #expect(rules.first?.id == customID)
        #expect(rules.first?.origin == .legacy)
        #expect(rules.first(where: { $0.name == "Old Discord" })?.isBuiltIn == false)
        let entry = try #require(store.recentSegments(limit: 1).first)
        #expect(entry.id == id)
        #expect(entry.classification.isManual)
        #expect(entry.classification.kind == .personal)
        let backup = try #require(FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains("pre-v1-") })
        let restored = url.deletingLastPathComponent().appendingPathComponent("restored.sqlite")
        try FileManager.default.copyItem(at: backup, to: restored)
        let restoredStore = try HagoStore(databaseURL: restored)
        #expect(try restoredStore.recentSegments(limit: 1).first?.classification == entry.classification)
    }

    @Test
    func futureOnlyPresetsAndDeletedChoicesSurviveRestart() throws {
        let url = try databaseURL()
        let store = try HagoStore(databaseURL: url)
        let snapshot = ActivitySnapshot(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 1, windowTitle: "Editor", url: nil, source: .macOS)
        let segment = ActivitySegment(startedAt: Date(), endedAt: Date().addingTimeInterval(60), snapshot: snapshot)
        try store.save(segment: segment, classification: classification(segment.id, kind: .personal))
        #expect(ActivityClassifier().classify(snapshot: snapshot, rules: try store.loadRules()).kind == .review)
        #expect(try store.loadRules().allSatisfy { !$0.name.contains("Jian Yang") })
        try store.setEnabledPresetIDs(["software-development"])
        let rule = try #require(store.loadRules().first { $0.presetID != nil && $0.conditions.first?.value == snapshot.bundleIdentifier })
        #expect(ActivityClassifier().classify(snapshot: snapshot, rules: try store.loadRules()).kind == .work)
        #expect(try store.recentSegments(limit: 1).first?.classification.kind == .personal)
        try store.deleteRule(id: rule.id)
        let reopened = try HagoStore(databaseURL: url)
        try reopened.setEnabledPresetIDs(["software-development"])
        #expect(try !reopened.loadRules().contains { $0.id == rule.id })
        #expect(ActivityClassifier().classify(snapshot: snapshot, rules: try reopened.loadRules()).kind == .review)
    }

    @Test
    func rememberedRulePreservesAuthorityAndUndoDoesNotResurrectDeletedData() throws {
        let url = try databaseURL()
        let store = try HagoStore(databaseURL: url)
        let snapshot = ActivitySnapshot(appName: "Editor", bundleIdentifier: "test.Editor", processIdentifier: 1, windowTitle: "Notes", url: nil, source: .macOS)
        var entries: [ActivitySegment] = []
        let project = Project(name: "Old project", colorHex: "#000000", isArchived: false)
        try store.saveProject(project)
        for index in 0..<4 {
            let item = ActivitySegment(startedAt: Date().addingTimeInterval(Double(index*100)), endedAt: Date().addingTimeInterval(Double(index*100+60)), snapshot: snapshot)
            entries.append(item)
            var choice = classification(item.id)
            if index == 1 { choice.isManual = true; choice.kind = .personal }
            if index == 2 { choice.projectID = project.id; choice.kind = .personal }
            try store.save(segment: item, classification: choice)
        }
        let rule = scopedRule(bundle: "test.Editor", kind: .work)
        #expect(try store.previewRememberedRule(rule).affectedCount == 2)
        let action = try store.applyRememberedRule(rule)
        var byID = Dictionary(uniqueKeysWithValues: try store.recentSegments(limit: 10).map { ($0.id, $0.classification) })
        #expect(byID[entries[0].id]?.kind == .work)
        #expect(byID[entries[1].id]?.kind == .personal)
        #expect(byID[entries[2].id]?.projectID == project.id)
        try store.ignoreSegment(id: entries[3].id)
        let reopened = try HagoStore(databaseURL: url)
        #expect(try reopened.undoCorrection(id: action) == 1)
        byID = Dictionary(uniqueKeysWithValues: try reopened.recentSegments(limit: 10).map { ($0.id, $0.classification) })
        #expect(byID[entries[0].id]?.kind == .review)
        #expect(byID[entries[3].id] == nil)
        #expect(byID[entries[1].id]?.isManual == true)
        #expect(try !reopened.loadRules().contains { $0.id == rule.id })
    }

    @Test
    func contradictoryScopedRulesNeedReviewWhileSpecificExceptionsWin() {
        let snapshot = ActivitySnapshot(appName: "Editor", bundleIdentifier: "test.Editor", processIdentifier: 1, windowTitle: "Notes", url: nil, source: .macOS)
        let work = scopedRule(bundle: "test.Editor", kind: .work)
        var personal = scopedRule(bundle: "test.Editor", kind: .personal)
        let classifier = ActivityClassifier()
        let conflict = classifier.classify(snapshot: snapshot, rules: [work, personal])
        #expect(conflict.kind == .review)
        #expect(conflict.reason.contains("Conflicting"))
        personal.conditions.append(RuleCondition(field: .windowTitle, operation: .equals, value: "Notes"))
        #expect(classifier.classify(snapshot: snapshot, rules: [work, personal]).kind == .personal)
        #expect(classifier.classify(snapshot: snapshot, rules: [work]).kind == .work)
    }

    @Test
    func learningRequiresDistinctDaysAndDismissalAndContradictionsPersist() throws {
        let url = try databaseURL()
        let store = try HagoStore(databaseURL: url)
        let now = HagoCalendar.shared.dayInterval(containing: Date()).start.addingTimeInterval(3600)
        var ids: [UUID] = []
        for day in 0..<3 {
            let date = Calendar.current.date(byAdding: .day, value: -day, to: now)!
            let snapshot = ActivitySnapshot(appName: "Editor", bundleIdentifier: "test.Editor", processIdentifier: 1, windowTitle: "", url: nil, source: .macOS)
            let item = ActivitySegment(startedAt: date, endedAt: date.addingTimeInterval(60), snapshot: snapshot)
            ids.append(item.id)
            try store.save(segment: item, classification: classification(item.id))
            _ = try store.correctSegments(ids: [item.id], kind: .work, categoryID: SeedData.workCategoryID)
        }
        let suggestion = try #require(store.learningSuggestions().first)
        #expect(suggestion.days == 3)
        try store.dismissLearningSuggestion(suggestion)
        let reopened = try HagoStore(databaseURL: url)
        #expect(try reopened.learningSuggestions().isEmpty)
        _ = try reopened.correctSegments(ids: [ids[0]], kind: .personal, categoryID: SeedData.personalCategoryID)
        #expect(try reopened.learningSuggestions().isEmpty)
    }

    @Test
    func privateSnapshotNeverBecomesDurableEvenWithAnIncorrectCallerLabel() throws {
        let store = try HagoStore(databaseURL: databaseURL())
        let snapshot = ActivitySnapshot(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 1,
                                        windowTitle: "Private title", url: "https://private.example", source: .chrome, isPrivate: true)
        let segment = ActivitySegment(startedAt: Date(), endedAt: Date().addingTimeInterval(60), snapshot: snapshot)
        try store.save(segment: segment, classification: classification(segment.id, kind: .work))
        try store.checkpoint(segment: segment, classification: classification(segment.id, kind: .work))
        #expect(try store.recentSegments(limit: 10).isEmpty)
        let security = ActivitySnapshot(appName: "SecurityAgent", bundleIdentifier: "com.apple.SecurityAgent", processIdentifier: 2,
                                        windowTitle: "Authentication", url: nil, source: .macOS)
        #expect(ActivityClassifier().classify(snapshot: security, rules: []).kind == .ignored)
    }

    private func classification(_ id: UUID, kind: ActivityKind = .review) -> SegmentClassification {
        SegmentClassification(segmentID: id, kind: kind, categoryID: nil, projectID: nil, ruleID: nil, isManual: false)
    }

    private func scopedRule(bundle: String, kind: ActivityKind) -> Rule {
        Rule(name: "Remember Editor", priority: 150, enabled: true, isBuiltIn: false,
             action: RuleAction(kind: kind, categoryID: nil, projectID: nil),
             conditions: [RuleCondition(field: .bundleIdentifier, operation: .equals, value: bundle)], origin: .user)
    }

    private func databaseURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("fixture.sqlite")
    }

    private func sql(_ url: URL, _ sql: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }
}
