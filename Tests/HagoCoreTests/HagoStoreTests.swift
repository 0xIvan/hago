import Foundation
import Testing
@testable import HagoCore

@Suite
struct HagoStoreTests {
    @Test
    func reclassifyTodayUpdatesMatchingReviewSegments() throws {
        let store = try makeStore()
        let segmentA = segment(url: "https://clerk.com/docs")
        let segmentB = segment(url: "https://clerk.com/dashboard", offset: 600)

        try store.save(
            segment: segmentA,
            classification: SegmentClassification(
                segmentID: segmentA.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: segmentB,
            classification: SegmentClassification(
                segmentID: segmentB.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )

        try store.saveRule(
            Rule(
                name: "Remember clerk.com",
                priority: 150,
                enabled: true,
                isBuiltIn: false,
                action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
                conditions: [
                    RuleCondition(field: .host, operation: .equals, value: "clerk.com")
                ]
            )
        )
        try store.reclassify(scope: .today)

        let remainingReviewSegments = try store.reviewSegments(for: Date())

        #expect(remainingReviewSegments.isEmpty)
    }

    @Test
    func reclassifyRuleUpdatesMatchingHistoryOnly() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let matchingSegment = segment(url: "https://clerk.com/docs", startedAt: baseDate)
        let otherSegment = segment(url: "https://x.com/home", offset: 600, startedAt: baseDate)
        let rule = rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000001")

        try store.save(
            segment: matchingSegment,
            classification: SegmentClassification(
                segmentID: matchingSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: otherSegment,
            classification: SegmentClassification(
                segmentID: otherSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.saveRule(rule)

        try store.reclassify(ruleID: rule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[matchingSegment.id]?.kind == .work)
        #expect(classifications[matchingSegment.id]?.ruleID == rule.id)
        #expect(classifications[otherSegment.id]?.kind == .review)
    }

    @Test
    func reclassifyRulePreservesHigherPriorityRulesForMatchingHistory() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let matchingSegment = segment(url: "https://clerk.com/docs", startedAt: baseDate)
        let higherPriorityRule = Rule(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
            name: "Clerk is personal",
            priority: 100,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .personal, categoryID: SeedData.personalCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .host, operation: .equals, value: "clerk.com")
            ]
        )
        let lowerPriorityRule = rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000001")

        try store.save(
            segment: matchingSegment,
            classification: SegmentClassification(
                segmentID: matchingSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.saveRule(higherPriorityRule)
        try store.saveRule(lowerPriorityRule)

        try store.reclassify(ruleID: lowerPriorityRule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[matchingSegment.id]?.kind == .personal)
        #expect(classifications[matchingSegment.id]?.ruleID == higherPriorityRule.id)
    }

    @Test
    func reclassifyRuleUpdatesExactURLMatches() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let matchingSegment = segment(url: "file:///Users/Ivan/Preview.html", startedAt: baseDate)
        let otherSegment = segment(url: "file:///Users/Ivan/Other.html", offset: 600, startedAt: baseDate)
        let rule = Rule(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!,
            name: "Remember local preview",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .url, operation: .equals, value: "file:///users/ivan/preview.html")
            ]
        )

        try store.save(
            segment: matchingSegment,
            classification: SegmentClassification(
                segmentID: matchingSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: otherSegment,
            classification: SegmentClassification(
                segmentID: otherSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.saveRule(rule)

        try store.reclassify(ruleID: rule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[matchingSegment.id]?.kind == .work)
        #expect(classifications[matchingSegment.id]?.ruleID == rule.id)
        #expect(classifications[otherSegment.id]?.kind == .review)
    }

    @Test
    func reclassifyDomainRuleUpdatesRootAndSubdomainMatches() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let rootSegment = segment(url: "https://emirates.com", startedAt: baseDate)
        let subdomainSegment = segment(
            url: "https://accounts.emirates.com",
            offset: 600,
            startedAt: baseDate
        )
        let lookalikeSegment = segment(
            url: "https://notemirates.com",
            offset: 1_200,
            startedAt: baseDate
        )
        let rule = Rule(
            name: "Remember emirates.com and subdomains as personal",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .personal, categoryID: SeedData.personalCategoryID, projectID: nil),
            conditions: [RuleCondition(field: .host, operation: .domain, value: "emirates.com")]
        )

        for activity in [rootSegment, subdomainSegment, lookalikeSegment] {
            try store.save(
                segment: activity,
                classification: SegmentClassification(
                    segmentID: activity.id,
                    kind: .review,
                    categoryID: nil,
                    projectID: nil,
                    ruleID: nil,
                    isManual: false
                )
            )
        }
        try store.saveRule(rule)

        try store.reclassify(ruleID: rule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[rootSegment.id]?.kind == .personal)
        #expect(classifications[subdomainSegment.id]?.kind == .personal)
        #expect(classifications[lookalikeSegment.id]?.kind == .review)
    }

    @Test
    func reclassifyRuleUpdatesAppNameMatches() throws {
        let store = try makeStore()
        let baseDate = middayToday()
        let matchingSegment = segment(
            appName: "Linear",
            bundleIdentifier: "com.linear",
            windowTitle: "Issue list",
            url: nil,
            source: .macOS,
            startedAt: baseDate
        )
        let otherSegment = segment(
            appName: "Finder",
            bundleIdentifier: "com.apple.finder",
            windowTitle: "Downloads",
            url: nil,
            source: .macOS,
            offset: 600,
            startedAt: baseDate
        )
        let rule = Rule(
            id: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!,
            name: "Remember Linear",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .appName, operation: .equals, value: "linear")
            ]
        )

        try store.save(
            segment: matchingSegment,
            classification: SegmentClassification(
                segmentID: matchingSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: otherSegment,
            classification: SegmentClassification(
                segmentID: otherSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.saveRule(rule)

        try store.reclassify(ruleID: rule.id, scope: .allHistory)

        let classifications = try classificationsBySegmentID(store: store, date: baseDate)
        #expect(classifications[matchingSegment.id]?.kind == .work)
        #expect(classifications[matchingSegment.id]?.ruleID == rule.id)
        #expect(classifications[otherSegment.id]?.kind == .review)
    }

    @Test
    func saveRememberedRuleDoesNotCreateDuplicates() throws {
        let store = try makeStore()

        try store.saveRememberedRule(rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000001"))
        try store.saveRememberedRule(rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000002"))

        let rememberedRules = try store.loadRules()
            .filter { $0.name == "Remember clerk.com" }

        #expect(rememberedRules.count == 1)
        #expect(rememberedRules.first?.id == UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001"))
    }

    @Test
    func deduplicateRememberedRulesKeepsActivityRuleReferences() throws {
        let store = try makeStore()
        let keeperRule = rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000001")
        let duplicateRule = rememberedRule(id: "AAAAAAAA-0000-0000-0000-000000000002")
        let segment = segment(url: "https://clerk.com/docs")

        try store.saveRule(keeperRule)
        try store.saveRule(duplicateRule)
        try store.save(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: nil,
                ruleID: duplicateRule.id,
                isManual: false
            )
        )

        try store.deduplicateRememberedRules()

        let rememberedRules = try store.loadRules()
            .filter { $0.name == "Remember clerk.com" }
        let activitySegments = try store.activitySegments(for: Date())

        #expect(rememberedRules.count == 1)
        #expect(activitySegments.first?.classification.ruleID == keeperRule.id)
    }


    @Test
    func activitySegmentsForDateReflectManualClassificationEdits() throws {
        let store = try makeStore()
        let segment = segment(url: "https://example.com")

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
        try store.overrideSegment(
            id: segment.id,
            kind: .personal,
            projectID: nil,
            categoryID: SeedData.personalCategoryID
        )

        let activitySegments = try store.activitySegments(for: Date())

        #expect(activitySegments.count == 1)
        #expect(activitySegments.first?.classification.kind == .personal)
        #expect(activitySegments.first?.classification.isManual == true)
    }


    @Test
    func bulkReviewChoiceChangesOnlySelectedPendingRecordings() throws {
        let store = try makeStore()
        let date = middayToday()
        let project = Project(name: "Preserved", colorHex: "#2563EB", isArchived: false)
        try store.saveProject(project)
        let entries = (0..<4).map { index in
            segment(appName: "Discord", bundleIdentifier: "com.hnc.Discord", windowTitle: "", url: nil, source: .macOS,
                    offset: Double(index) * 600, startedAt: date)
        }
        for item in entries {
            try store.save(segment: item, classification: SegmentClassification(
                segmentID: item.id, kind: .review, categoryID: nil, projectID: project.id, ruleID: nil, isManual: false
            ))
        }
        try store.overrideSegment(id: entries[3].id, kind: .personal, projectID: project.id, categoryID: SeedData.personalCategoryID)
        let rulesBefore = try store.loadRules()
        try store.resolveReviewSegments(ids: [entries[0].id, entries[1].id, entries[3].id], kind: .work, categoryID: SeedData.workCategoryID)

        let rows = Dictionary(uniqueKeysWithValues: try store.activitySegments(for: date).map { ($0.id, $0) })
        for item in entries.prefix(2) {
            #expect(rows[item.id]?.classification.kind == .work)
            #expect(rows[item.id]?.classification.isManual == true)
            #expect(rows[item.id]?.classification.projectID == project.id)
        }
        #expect(rows[entries[2].id]?.classification.kind == .review)
        #expect(rows[entries[3].id]?.classification.kind == .personal)
        #expect(rows.count == 4)
        #expect(rows.values.reduce(0) { $0 + $1.segment.duration } == 480)
        #expect(try store.loadRules() == rulesBefore)
        #expect(ActivityClassifier().classify(snapshot: entries[0].snapshot, rules: rulesBefore).kind == .review)
    }

    @Test
    func daySummaryAggregatesChromeActivityByHost() throws {
        let store = try makeStore()
        let firstSegment = segment(url: "https://clerk.com/docs")
        let secondSegment = segment(url: "https://clerk.com/dashboard", offset: 600)
        let thirdSegment = segment(url: "https://x.com/home", offset: 1_200)

        for segment in [firstSegment, secondSegment, thirdSegment] {
            try store.save(
                segment: segment,
                classification: SegmentClassification(
                    segmentID: segment.id,
                    kind: .work,
                    categoryID: SeedData.workCategoryID,
                    projectID: nil,
                    ruleID: nil,
                    isManual: false
                )
            )
        }

        let summary = try store.daySummary(for: Date())

        #expect(summary.topApps.map(\.name) == ["clerk.com", "x.com"])
        #expect(summary.topApps.map(\.seconds) == [240, 120])
    }

    @Test
    func daySummarySeparatesWorkPersonalAndReviewTimeForTheSameSite() throws {
        let store = try makeStore()
        let date = middayToday()
        for (index, kind) in [ActivityKind.work, .work, .personal, .review].enumerated() {
            let item = segment(url: "https://example.com/page-\(index)", offset: Double(index) * 600, startedAt: date)
            try store.save(
                segment: item,
                classification: SegmentClassification(
                    segmentID: item.id,
                    kind: kind,
                    categoryID: nil,
                    projectID: nil,
                    ruleID: nil,
                    isManual: false
                )
            )
        }

        let summary = try store.daySummary(for: date)
        let work = summary.topApps.filter { $0.kind == .work }
        let personal = summary.topApps.filter { $0.kind == .personal }
        let review = summary.topApps.filter { $0.kind == .review }

        #expect(work.map(\.name) == ["example.com"])
        #expect(work.map(\.seconds) == [240])
        #expect(personal.map(\.name) == ["example.com"])
        #expect(personal.map(\.seconds) == [120])
        #expect(review.map(\.seconds) == [120])
        #expect(Set(summary.topApps.map(\.id)).count == 3)
        #expect(summary.workSeconds == 240)
        #expect(summary.personalSeconds == 120)
        #expect(summary.reviewSeconds == 120)
    }

    @Test
    func daySummaryRanksTopAppsSeparatelyForEachClassification() throws {
        let store = try makeStore()
        let date = middayToday()
        for index in 0..<10 {
            let kind: ActivityKind = index == 9 ? .personal : .work
            var item = segment(url: "https://app-\(index).example.com", offset: Double(index) * 600, startedAt: date)
            item.endedAt = item.startedAt.addingTimeInterval(kind == .work ? 240 : 120)
            try store.save(
                segment: item,
                classification: SegmentClassification(
                    segmentID: item.id,
                    kind: kind,
                    categoryID: nil,
                    projectID: nil,
                    ruleID: nil,
                    isManual: false
                )
            )
        }

        let summary = try store.daySummary(for: date)
        #expect(summary.topApps.filter { $0.kind == .work }.count == 8)
        #expect(summary.topApps.filter { $0.kind == .personal }.map(\.name) == ["app-9.example.com"])
        #expect(summary.topApps.filter { $0.kind == .personal }.map(\.seconds) == [120])
    }

    @Test
    func reviewSegmentsReturnsEntireBacklogNewestFirst() throws {
        let store = try makeStore()
        let olderSegment = segment(url: "https://older.example.com", offset: -172_800)
        let newerSegment = segment(url: "https://newer.example.com", offset: -86_400)

        try store.save(
            segment: olderSegment,
            classification: SegmentClassification(
                segmentID: olderSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: newerSegment,
            classification: SegmentClassification(
                segmentID: newerSegment.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )

        let reviewSegments = try store.reviewSegments()

        #expect(reviewSegments.map(\.id) == [newerSegment.id, olderSegment.id])
    }

    @Test
    func saveCategoryKeepsExistingActivityAttached() throws {
        let store = try makeStore()
        let segment = segment(url: "https://example.com")

        try store.save(
            segment: segment,
            classification: SegmentClassification(
                segmentID: segment.id,
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )

        try store.saveCategory(
            Category(
                id: SeedData.workCategoryID,
                name: "Deep Work",
                kind: .work,
                colorHex: "#111111"
            )
        )

        let activitySegments = try store.activitySegments(for: Date())

        #expect(activitySegments.first?.classification.categoryID == SeedData.workCategoryID)
        #expect(activitySegments.first?.categoryName == "Deep Work")
    }

    @Test
    func weekReportAggregatesTotalsBucketsAndPreviousPeriod() throws {
        let store = try makeStore()
        let workSegment = segment(url: "https://example.com")
        let personalSegment = segment(url: "https://x.com", offset: 600)

        try store.save(
            segment: workSegment,
            classification: SegmentClassification(
                segmentID: workSegment.id,
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        try store.save(
            segment: personalSegment,
            classification: SegmentClassification(
                segmentID: personalSegment.id,
                kind: .personal,
                categoryID: SeedData.personalCategoryID,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )

        let report = try store.reportSummary(for: .week, containing: Date())
        let previousReport = try store.previousReportSummary(for: .week, containing: Date())

        #expect(report.workSeconds == 120)
        #expect(report.personalSeconds == 120)
        #expect(report.totalSeconds == 240)
        #expect(report.buckets.count == 7)
        #expect(report.topApps.map(\.name) == ["example.com", "x.com"])
        #expect(report.topApps.map(\.seconds) == [120, 120])
        #expect(previousReport.totalSeconds == 0)
    }

    @Test
    func weekReportClipsSegmentsAtPeriodAndDayCutoffs() throws {
        let store = try makeStore()
        let date = middayToday()
        let week = HagoCalendar.shared.weekInterval(containing: date)
        let firstDayEnd = Calendar.current.date(byAdding: .day, value: 1, to: week.start)!
        let beforeWeek = segment(url: nil, startedAt: week.start.addingTimeInterval(-60))
        let acrossDay = segment(url: nil, startedAt: firstDayEnd.addingTimeInterval(-30))

        for item in [beforeWeek, acrossDay] {
            try store.save(segment: item, classification: SegmentClassification(
                segmentID: item.id,
                kind: .work,
                categoryID: SeedData.workCategoryID,
                projectID: nil,
                ruleID: nil,
                isManual: false
            ))
        }

        let report = try store.reportSummary(for: .week, containing: date)
        #expect(report.workSeconds == 180)
        #expect(report.buckets[0].workSeconds == 90)
        #expect(report.buckets[1].workSeconds == 90)
        #expect(report.topApps.first?.seconds == 180)
    }

    @Test
    func daySummaryCountsARecordingThatGrewAcrossTheDayStartAfterAnEarlierRead() throws {
        let store = try makeStore()
        let day = HagoCalendar.shared.dayInterval(containing: middayToday())
        let short = segment(url: nil, startedAt: day.start.addingTimeInterval(3_600))
        let work = SegmentClassification(
            segmentID: short.id, kind: .work, categoryID: nil, projectID: nil, ruleID: nil, isManual: false
        )
        try store.save(segment: short, classification: work)
        #expect(try store.daySummary(for: middayToday()).workSeconds == 120)

        var long = segment(url: nil, startedAt: day.start.addingTimeInterval(-10 * 3_600))
        let longWork = SegmentClassification(
            segmentID: long.id, kind: .work, categoryID: nil, projectID: nil, ruleID: nil, isManual: false
        )
        try store.checkpoint(segment: long, classification: longWork)
        long.endedAt = day.start.addingTimeInterval(1_800)
        try store.checkpoint(segment: long, classification: longWork)

        #expect(try store.daySummary(for: middayToday()).workSeconds == 120 + 1_800)
    }

    @Test
    func ruleReviewRecordsIdentifyConflictingRules() throws {
        let store = try makeStore()
        let condition = RuleCondition(field: .host, operation: .equals, value: "www.firecrawl.dev")
        let workRule = Rule(
            name: "Firecrawl work",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [condition]
        )
        let personalRule = Rule(
            name: "Firecrawl personal",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .personal, categoryID: SeedData.personalCategoryID, projectID: nil),
            conditions: [RuleCondition(field: .host, operation: .equals, value: "www.firecrawl.dev")]
        )

        try store.saveRule(workRule)
        try store.saveRule(personalRule)
        let records = try store.ruleReviewRecords().filter { $0.id == workRule.id || $0.id == personalRule.id }

        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.issues.contains(.conflict) })
        #expect(records.allSatisfy { $0.origin == .custom })
    }

    @Test
    func appliedReviewRuleDetailsTrackLaterChanges() throws {
        let store = try makeStore()
        let activity = segment(url: "https://github.com/openai/codex")
        try store.save(
            segment: activity,
            classification: SegmentClassification(
                segmentID: activity.id,
                kind: .review,
                categoryID: nil,
                projectID: nil,
                ruleID: nil,
                isManual: false
            )
        )
        let summary = try store.processReviewAISuggestions(
            [
                ReviewAISuggestion(
                    kind: .work,
                    confidence: 0.99,
                    reason: "GitHub development activity.",
                    proposedRuleCondition: RuleCondition(
                        field: .host,
                        operation: .equals,
                        value: "github.com"
                    ),
                    affectedCount: 1,
                    affectedDuration: 120,
                    samples: []
                )
            ],
            harness: .codex,
            harnessVersion: "test",
            automaticallyApply: true
        )

        let originalDetail = try #require(try store.appliedReviewAIRules(runID: summary.id).first)
        #expect(originalDetail.state == .unchanged)
        #expect(originalDetail.currentRule?.name == "Remember github.com as work")

        var editedRule = try #require(originalDetail.currentRule)
        editedRule.action.kind = .personal
        editedRule.action.categoryID = SeedData.personalCategoryID
        try store.saveRule(editedRule)

        let changedDetail = try #require(try store.appliedReviewAIRules(runID: summary.id).first)
        #expect(changedDetail.state == .changed)
        #expect(changedDetail.currentRule?.action.kind == .personal)
    }

    private func makeStore() throws -> HagoStore {
        try HagoStore(databaseURL: temporaryDatabaseURL())
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("hago.sqlite")
    }

    private func classificationsBySegmentID(
        store: HagoStore,
        date: Date
    ) throws -> [UUID: SegmentClassification] {
        try Dictionary(
            uniqueKeysWithValues: store.activitySegments(for: date).map { item in
                (item.id, item.classification)
            }
        )
    }

    private func middayToday() -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func segment(
        appName: String = "Google Chrome",
        bundleIdentifier: String = "com.google.Chrome",
        windowTitle: String = "Clerk",
        url: String?,
        source: ActivitySource = .chrome,
        offset: TimeInterval = 0,
        startedAt: Date = Date()
    ) -> ActivitySegment {
        let start = startedAt.addingTimeInterval(offset)
        let end = start.addingTimeInterval(120)
        let snapshot = ActivitySnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: 1,
            windowTitle: windowTitle,
            url: url,
            source: source
        )

        return ActivitySegment(startedAt: start, endedAt: end, snapshot: snapshot)
    }

    private func rememberedRule(id: String) -> Rule {
        Rule(
            id: UUID(uuidString: id)!,
            name: "Remember clerk.com",
            priority: 150,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .work, categoryID: SeedData.workCategoryID, projectID: nil),
            conditions: [
                RuleCondition(field: .host, operation: .equals, value: "clerk.com")
            ]
        )
    }
}
