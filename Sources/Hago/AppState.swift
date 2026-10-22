import AppKit
import Combine
import Foundation
import HagoCore
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    @Published var currentSnapshot: ActivitySnapshot?
    @Published var currentClassification: ClassificationResult?
    @Published var currentStateLabel = "Starting"
    @Published var todaySummary = DaySummary.empty(on: Date())
    @Published var todayTimeline: [ClassifiedSegment] = []
    @Published var reviewSegments: [ClassifiedSegment] = []
    @Published var reviewAISuggestions: [ReviewAISuggestion] = []
    @Published var reviewAIAnalysisState = ReviewAIAnalysisState.idle
    @Published var reviewAISettings: ReviewAISettings
    @Published var reviewAIScheduleState = ReviewAIScheduleState()
    @Published var reviewAIHarnessStatuses: [ReviewAIHarnessStatus] = []
    @Published var isDiscoveringReviewAIHarnesses = false
    @Published var lastReviewAIRunSummary: ReviewAIRunSummary?
    @Published var lastReviewAIUndoMessage: String?
    @Published var recentSegments: [ClassifiedSegment] = []
    @Published var activityDate = Date()
    @Published var activitySegments: [ClassifiedSegment] = []
    @Published var rules: [Rule] = []
    @Published var ruleReviewRecords: [RuleReviewRecord] = []
    @Published var categories: [HagoCore.Category] = []
    @Published var projects: [Project] = []
    @Published var errorMessage: String?
    @Published var accessibilityTrusted = false
    @Published var selectedSection: HagoSection = .overview

    private let reader = ActiveWindowReader()
    private let classifier = ActivityClassifier()
    private let rememberedRuleFactory = RememberedRuleFactory()
    private let reviewAISettingsStore: ReviewAISettingsStore
    private let reviewAIHarnessDiscovery: ReviewAIHarnessDiscovery
    private let formatter = TimeFormatting()
    private var store: HagoStore?
    private var reviewAIAnalysisService: ReviewAIAnalysisService?
    private var activeReviewIsScheduled = false
    private var timer: Timer?
    private var recorder = ActivityRecorder()
    private var pendingCheckpoints: [UUID: ActivitySegment] = [:]
    private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var suspensionReasons: Set<String> = []
    @Published var isTrackingPaused = false
    @Published var trackingErrorMessage: String?
    @Published var loginItemStatus = SMAppService.mainApp.status
    @Published var loginItemError: String?
    private var visibleAppWindows: Set<String> = []
    private var dashboardWindow: NSWindow?
    private var reviewAIRevision = 0
    private var reviewAIAnalysisTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5

    init() {
        let settingsStore = ReviewAISettingsStore()
        reviewAISettingsStore = settingsStore
        reviewAISettings = settingsStore.load()
        reviewAIHarnessDiscovery = ReviewAIHarnessDiscovery()

        do {
            let databaseURL = try HagoStore.defaultDatabaseURL()
            store = try HagoStore(databaseURL: databaseURL)
            if let store {
                if let last = try store.recentSegments(limit: 1).first {
                    recorder = ActivityRecorder(notBefore: last.segment.endedAt)
                }
                reviewAIAnalysisService = ReviewAIAnalysisService(store: store)
                reviewAIScheduleState = try store.loadReviewAIScheduleState()
                if reviewAIScheduleState.outcome == .running {
                    reviewAIScheduleState.recoverAfterRestart(at: Date(), interval: reviewAISettings.scheduleInterval)
                    try store.saveReviewAIScheduleState(reviewAIScheduleState)
                }
                if reviewAISettings.scheduleEnabled {
                    let previousNextRunAt = reviewAIScheduleState.nextRunAt
                    reviewAIScheduleState.deferOverdueRunAfterLaunch(
                        at: Date(), interval: reviewAISettings.scheduleInterval
                    )
                    if reviewAIScheduleState.nextRunAt != previousNextRunAt {
                        try store.saveReviewAIScheduleState(reviewAIScheduleState)
                    }
                }
            }
            // Launches and tracking polls only check access; the user starts permission requests.
            try refresh()
            refreshReviewAIHarnesses()
            observeLifecycle()
            startTracking()
            DispatchQueue.main.async { [weak self] in
                self?.hideFromDockIfNoWindowsAreOpen()
            }
        } catch {
            errorMessage = error.localizedDescription
            currentStateLabel = "Setup failed"
        }
    }

    var menuBarTitle: String {
        let workDuration = formatter.menuBarWorkDuration(todaySummary.workSeconds)
        let totalDuration = formatter.menuBarWorkDuration(todayTrackedSeconds)

        return "\(workDuration) | \(totalDuration)"
    }

    var todayTrackedSeconds: TimeInterval {
        todaySummary.workSeconds + todaySummary.personalSeconds + todaySummary.reviewSeconds
    }

    var selectedReviewAIHarnessStatus: ReviewAIHarnessStatus? {
        reviewAIHarnessStatuses.first { $0.harness == reviewAISettings.selectedHarness }
    }

    var selectedReviewAIHarnessIsConfirmed: Bool {
        reviewAISettings.selectedHarness == .disabled
            || reviewAISettings.confirmedHarnesses.contains(reviewAISettings.selectedHarness)
    }

    var availableReviewAIModels: [ReviewAIModelOption] {
        selectedReviewAIHarnessStatus?.models ?? []
    }

    var selectedReviewAIModelOption: ReviewAIModelOption? {
        guard let modelID = reviewAISettings.selectedModel(for: reviewAISettings.selectedHarness) else {
            return nil
        }
        return availableReviewAIModels.first { $0.modelID == modelID }
    }

    var availableReviewAIReasoningEfforts: [ReviewAIReasoningEffort] {
        if let selectedReviewAIModelOption {
            return selectedReviewAIModelOption.supportedReasoningEfforts
        }
        if let recommendedModel = availableReviewAIModels.first(where: \.isRecommended) {
            return recommendedModel.supportedReasoningEfforts
        }
        switch reviewAISettings.selectedHarness {
        case .codex:
            return [.low, .medium, .high, .xhigh, .max]
        case .claudeCode:
            return [.low, .medium, .high, .xhigh, .max]
        case .pi:
            return [.off, .minimal, .low, .medium, .high, .xhigh, .max]
        case .disabled:
            return []
        }
    }

    var recommendedReviewAIReasoningEffort: ReviewAIReasoningEffort? {
        selectedReviewAIModelOption?.recommendedReasoningEffort
            ?? availableReviewAIModels.first(where: \.isRecommended)?.recommendedReasoningEffort
    }

    var effectiveReviewAIReasoningEffort: ReviewAIReasoningEffort? {
        guard let effort = reviewAISettings.selectedReasoningEffort(
            for: reviewAISettings.selectedHarness
        ), availableReviewAIReasoningEfforts.contains(effort) else {
            return nil
        }
        return effort
    }

    func prepareToOpenAppWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openDashboardWindow() {
        openHagoWindow(section: .overview)
    }

    func openSettingsWindow() {
        openHagoWindow(section: .rules)
    }

    private func openHagoWindow(section: HagoSection) {
        selectedSection = section
        prepareToOpenAppWindow()

        if dashboardWindow == nil {
            dashboardWindow = NSApp.windows.first {
                $0.identifier?.rawValue == "dashboard" || $0.title == "Hago"
            }
        }

        appWindowDidAppear(id: "dashboard")
        dashboardWindow?.deminiaturize(nil)
        dashboardWindow?.makeKeyAndOrderFront(nil)
        reload()
    }

    func appWindowDidAppear(id: String, window: NSWindow? = nil) {
        if id == "dashboard", let window {
            dashboardWindow = window
        }
        visibleAppWindows.insert(id)
        prepareToOpenAppWindow()
    }

    func appWindowDidDisappear(id: String) {
        visibleAppWindows.remove(id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else {
                return
            }

            self.hideFromDockIfNoWindowsAreOpen()
        }
    }

    func requestAccessibilityPermission() {
        reader.requestAccessibilityPermission()
        accessibilityTrusted = reader.accessibilityIsTrusted()
    }

    func refresh() throws {
        guard let store else {
            return
        }

        rules = try store.loadRules()
        ruleReviewRecords = try store.ruleReviewRecords(for: rules)
        categories = try store.loadCategories()
        projects = try store.loadProjects()
        let now = Date()
        todaySummary = try store.daySummary(for: now)
        todayTimeline = try store.dayTimeline(for: now)
        reviewSegments = try store.reviewSegments()
        // A recommendation-only background run must not hide the latest View Applied / Undo controls.
        lastReviewAIRunSummary = try store.mostRecentReviewAIRun(appliedRulesOnly: true) ?? store.mostRecentReviewAIRun()
        activitySegments = try store.activitySegments(for: activityDate)
        recentSegments = try store.recentSegments(limit: 20)
        accessibilityTrusted = reader.accessibilityIsTrusted()
        reviewAISuggestions = try reviewAIAnalysisService?.savedSuggestions(context: reviewAIAnalysisContext) ?? []
    }

    func reload() {
        do {
            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveRule(_ rule: Rule, reclassify scope: ReclassificationScope?) {
        guard flushTracking() else { return }
        do {
            try store?.saveRule(rule)
            if let scope {
                try store?.reclassify(scope: scope)
            }
            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRule(id: UUID, reclassify scope: ReclassificationScope?) {
        do {
            try store?.deleteRule(id: id)
            if let scope {
                try store?.reclassify(scope: scope)
            }
            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveCategory(_ category: HagoCore.Category) -> Bool {
        do {
            try store?.saveCategory(category)
            try refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveProject(_ project: Project) {
        do {
            try store?.saveProject(project)
            try refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectActivityDate(_ date: Date) {
        activityDate = date
        reload()
    }

    func loadReportPair(
        for periodKind: ReportPeriodKind,
        containing date: Date
    ) -> (current: ReportSummary, previous: ReportSummary)? {
        do {
            guard let store else {
                return nil
            }

            let current = try store.reportSummary(for: periodKind, containing: date)
            let previous = try store.previousReportSummary(for: periodKind, containing: date)
            errorMessage = nil

            return (current, previous)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private var reviewAIAnalysisContext: ReviewAIAnalysisContext {
        ReviewAIAnalysisContext(
            harness: reviewAISettings.selectedHarness,
            model: reviewAISettings.selectedModel(for: reviewAISettings.selectedHarness),
            reasoning: effectiveReviewAIReasoningEffort,
            profession: reviewAISettings.profession
        )
    }

    func analyzeReview(scheduled: Bool = false) {
        guard reviewAIAnalysisTask == nil,
              let service = reviewAIAnalysisService, !service.isRunning else { return }
        if scheduled {
            reviewAIScheduleState.begin(at: Date(), interval: reviewAISettings.scheduleInterval)
            guard saveReviewAIScheduleState() else { return }
        }
        let selectedHarness = reviewAISettings.selectedHarness
        guard selectedHarness != .disabled else {
            reviewAIAnalysisFailed("Select an AI harness before analysis.", scheduled: scheduled)
            return
        }
        guard selectedReviewAIHarnessIsConfirmed else {
            reviewAIAnalysisFailed("Confirm the data disclosure for \(selectedHarness.displayName) first.", scheduled: scheduled)
            return
        }
        guard let status = selectedReviewAIHarnessStatus,
              status.isAvailable,
              let executablePath = status.executablePath else {
            reviewAIAnalysisFailed("\(selectedHarness.displayName) is not available. Refresh AI Harness settings.", scheduled: scheduled)
            return
        }

        reviewAIAnalysisState = .analyzing
        activeReviewIsScheduled = scheduled
        let revision = reviewAIRevision
        let context = reviewAIAnalysisContext
        let automaticallyApply = scheduled
            ? reviewAISettings.automaticallyApplyScheduledReviews
            : reviewAISettings.automaticallyApplyHighConfidence

        reviewAIAnalysisTask = Task { @MainActor in
            do {
                let environment = await reviewAIHarnessDiscovery.repairedEnvironment(
                    from: ProcessInfo.processInfo.environment
                )
                let provider = CLIReviewAISuggestionProvider(
                    harness: selectedHarness,
                    executablePath: executablePath,
                    environment: environment,
                    model: context.model,
                    reasoningEffort: context.reasoning,
                    profession: context.profession
                )
                let result = try await service.analyze(
                    provider: provider, context: context, harnessVersion: status.version,
                    automaticallyApply: automaticallyApply, force: !scheduled
                )
                guard revision == reviewAIRevision else {
                    return
                }

                if let summary = result.summary {
                    lastReviewAIRunSummary = summary
                    lastReviewAIUndoMessage = nil
                }
                try refresh()
                if scheduled {
                    reviewAIScheduleState.finish(
                        at: Date(), analyzedGroups: result.analyzedGroups,
                        appliedRules: result.summary?.automaticallyAppliedCount ?? 0
                    )
                    guard saveReviewAIScheduleState() else {
                        reviewAIAnalysisTask = nil
                        reviewAIAnalysisState = .failed(errorMessage ?? "Could not save the schedule result.")
                        return
                    }
                }
                reviewAIAnalysisState = .completed
                reviewAIAnalysisTask = nil
                errorMessage = nil
            } catch {
                guard revision == reviewAIRevision else {
                    return
                }

                reviewAIAnalysisTask = nil
                reviewAIAnalysisFailed(error.localizedDescription, scheduled: scheduled)
            }
        }
    }

    func stopReviewAIAnalysis() {
        guard reviewAIAnalysisState == .analyzing else {
            return
        }
        reviewAIRevision += 1
        reviewAIAnalysisTask?.cancel()
        reviewAIAnalysisTask = nil
        if activeReviewIsScheduled {
            reviewAIScheduleState.stop(at: Date(), interval: reviewAISettings.scheduleInterval)
            _ = saveReviewAIScheduleState()
        }
        reviewAIAnalysisState = .idle
        errorMessage = nil
    }

    func setReviewAIScheduleEnabled(_ enabled: Bool) {
        if !enabled && activeReviewIsScheduled { stopReviewAIAnalysis() }
        reviewAISettings.scheduleEnabled = enabled
        reviewAIScheduleState.nextRunAt = enabled ? Date() : nil
        reviewAISettingsStore.save(reviewAISettings)
        guard saveReviewAIScheduleState() else { return }
        checkScheduledReview()
    }

    func setReviewAIScheduleInterval(_ interval: ReviewAIScheduleInterval) {
        reviewAISettings.scheduleInterval = interval
        reviewAIScheduleState.nextRunAt = Date().addingTimeInterval(TimeInterval(interval.rawValue))
        reviewAISettingsStore.save(reviewAISettings)
        _ = saveReviewAIScheduleState()
    }

    func setReviewAIScheduledAutomaticApply(_ enabled: Bool) {
        reviewAISettings.automaticallyApplyScheduledReviews = enabled
        saveReviewAISettings()
    }

    private func checkScheduledReview() {
        guard !isDiscoveringReviewAIHarnesses,
              reviewAIScheduleState.isDue(
                at: Date(), enabled: reviewAISettings.scheduleEnabled,
                isRunning: reviewAIAnalysisTask != nil || reviewAIAnalysisService?.isRunning == true
              ) else { return }
        analyzeReview(scheduled: true)
    }

    private func saveReviewAIScheduleState() -> Bool {
        do {
            guard let store else { return false }
            try store.saveReviewAIScheduleState(reviewAIScheduleState)
            return true
        } catch {
            reviewAISettings.scheduleEnabled = false
            reviewAISettingsStore.save(reviewAISettings)
            errorMessage = "Automatic Review paused: \(error.localizedDescription)"
            return false
        }
    }

    private func reviewAIAnalysisFailed(_ message: String, scheduled: Bool) {
        reviewAIAnalysisState = .failed(message)
        if scheduled {
            reviewAIScheduleState.fail(message)
            _ = saveReviewAIScheduleState()
        } else {
            errorMessage = message
        }
    }

    func selectReviewAIHarness(_ harness: ReviewAIHarnessKind) {
        if harness == .disabled { setReviewAIScheduleEnabled(false) }
        reviewAISettings.selectedHarness = harness
        saveReviewAISettings()
    }

    func setReviewAIHarnessConfirmed(_ confirmed: Bool) {
        let harness = reviewAISettings.selectedHarness
        guard harness != .disabled else {
            return
        }
        if confirmed {
            reviewAISettings.confirmedHarnesses.insert(harness)
        } else {
            reviewAISettings.confirmedHarnesses.remove(harness)
            setReviewAIScheduleEnabled(false)
        }
        saveReviewAISettings()
    }

    func setReviewAIAutomaticallyAppliesHighConfidence(_ enabled: Bool) {
        reviewAISettings.automaticallyApplyHighConfidence = enabled
        saveReviewAISettings()
    }

    func setReviewAIModel(_ modelID: String?) {
        let harness = reviewAISettings.selectedHarness
        guard harness != .disabled else {
            return
        }
        let trimmedModelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedModelID.isEmpty {
            reviewAISettings.selectedModels.removeValue(forKey: harness.rawValue)
        } else {
            reviewAISettings.selectedModels[harness.rawValue] = trimmedModelID
        }

        if let effort = reviewAISettings.selectedReasoningEffort(for: harness),
           !availableReviewAIReasoningEfforts.contains(effort) {
            reviewAISettings.selectedReasoningEfforts.removeValue(forKey: harness.rawValue)
        }
        saveReviewAISettings()
    }

    func setReviewAIProfession(_ profession: ReviewAIProfession) {
        reviewAISettings.profession = profession
        saveReviewAISettings()
    }

    func setReviewAIReasoningEffort(_ effort: ReviewAIReasoningEffort?) {
        let harness = reviewAISettings.selectedHarness
        guard harness != .disabled else {
            return
        }
        if let effort {
            reviewAISettings.selectedReasoningEfforts[harness.rawValue] = effort
        } else {
            reviewAISettings.selectedReasoningEfforts.removeValue(forKey: harness.rawValue)
        }
        saveReviewAISettings()
    }

    func setReviewAICustomBinaryPath(_ path: String, for harness: ReviewAIHarnessKind) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousPath = reviewAISettings.customBinaryPath(for: harness)
        if trimmedPath.isEmpty {
            reviewAISettings.customBinaryPaths.removeValue(forKey: harness.rawValue)
        } else {
            reviewAISettings.customBinaryPaths[harness.rawValue] = trimmedPath
        }
        if previousPath != reviewAISettings.customBinaryPath(for: harness) {
            reviewAISettings.confirmedHarnesses.remove(harness)
        }
        saveReviewAISettings()
        refreshReviewAIHarnesses()
    }

    func refreshReviewAIHarnesses() {
        guard !isDiscoveringReviewAIHarnesses else {
            return
        }
        isDiscoveringReviewAIHarnesses = true
        let settings = reviewAISettings

        Task { @MainActor in
            reviewAIHarnessStatuses = await reviewAIHarnessDiscovery.discover(settings: settings)
            isDiscoveringReviewAIHarnesses = false
            checkScheduledReview()
        }
    }

    func applyReviewAISuggestion(_ suggestion: ReviewAISuggestion) {
        do {
            stopReviewAIAnalysis()
            reviewAIRevision += 1
            _ = try store?.applyReviewAISuggestion(suggestion)
            try refresh()
            pruneReviewAISuggestionsForCurrentBacklog()
            reviewAIAnalysisState = .completed

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyReviewAISuggestion(_ suggestion: ReviewAISuggestion, as kind: ReviewAISuggestionKind) {
        var correctedSuggestion = suggestion
        correctedSuggestion.kind = kind
        applyReviewAISuggestion(correctedSuggestion)
    }

    func undoLastReviewAIRun() {
        guard let run = lastReviewAIRunSummary,
              run.status == .completed,
              run.automaticallyAppliedCount > 0 else {
            return
        }

        do {
            guard let result = try store?.undoReviewAIRun(id: run.id) else {
                return
            }
            try refresh()
            clearReviewAISuggestions()
            if result.conflictCount == 0 {
                lastReviewAIUndoMessage = "Undid \(result.revertedRuleCount) automatic rule changes."
            } else {
                lastReviewAIUndoMessage = "Undid \(result.revertedRuleCount) rule changes; \(result.conflictCount) changed rules were left as they are."
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func appliedReviewAIRules(for runID: UUID) -> [ReviewAIAppliedRule] {
        do {
            let details = try store?.appliedReviewAIRules(runID: runID) ?? []
            errorMessage = nil
            return details
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    var reviewGroups: [AggregatedActivity] {
        ActivityAggregation.reviewGroups(from: reviewSegments)
    }

    func classifyReviewGroup(_ group: AggregatedActivity, as kind: ActivityKind) {
        guard flushTracking() else { return }
        guard let segment = reviewSegments.first(where: { group.segmentIDs.contains($0.id) }) else { return }
        let categoryID = categories.first { $0.kind == kind }?.id

        do {
            if let rule = rememberedRuleFactory.rule(from: segment, kind: kind, categoryID: categoryID) {
                if let ruleID = try store?.saveRememberedRule(rule) {
                    try store?.reclassify(ruleID: ruleID, scope: .allHistory)
                }
            }

            try store?.resolveReviewSegments(ids: group.segmentIDs, kind: kind, categoryID: categoryID)

            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSegmentClassification(_ segment: ClassifiedSegment, as kind: ActivityKind) {
        guard flushTracking() else { return }
        guard kind != .review else {
            return
        }

        let categoryID = categories.first { $0.kind == kind }?.id

        do {
            if kind == .ignored {
                try store?.ignoreSegment(id: segment.id)
            } else {
                try store?.overrideSegment(
                    id: segment.id,
                    kind: kind,
                    projectID: segment.classification.projectID,
                    categoryID: categoryID
                )
            }

            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearReviewAISuggestions() {
        stopReviewAIAnalysis()
        reviewAIRevision += 1
        reviewAIAnalysisTask?.cancel()
        reviewAIAnalysisTask = nil
        reviewAISuggestions = (try? reviewAIAnalysisService?.savedSuggestions(context: reviewAIAnalysisContext)) ?? []
        reviewAIAnalysisState = .idle
    }

    private func saveReviewAISettings() {
        reviewAISettingsStore.save(reviewAISettings)
        clearReviewAISuggestions()
    }

    private func pruneReviewAISuggestionsForCurrentBacklog() {
        let currentGroupIDs = Set(ReviewAISuggestionRequest(reviewSegments: reviewSegments).groups.map(\.id))
        reviewAISuggestions = reviewAISuggestions.filter { suggestion in
            currentGroupIDs.contains(suggestion.id)
        }
    }

    private func hideFromDockIfNoWindowsAreOpen() {
        guard visibleAppWindows.isEmpty else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
    }

    func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func toggleTracking() {
        isTrackingPaused.toggle()
        tick()
    }

    @discardableResult
    func flushTracking() -> Bool {
        enqueue(recorder.observe(nil, at: Date(), uptime: ProcessInfo.processInfo.systemUptime))
        return persistCheckpoints()
    }

    @discardableResult
    func stopTracking() -> Bool {
        timer?.invalidate()
        timer = nil
        for (center, token) in lifecycleObservers { center.removeObserver(token) }
        lifecycleObservers.removeAll()
        return flushTracking()
    }

    func removeActivityTime(_ item: ClassifiedSegment, from start: Date, to end: Date) -> Bool {
        guard flushTracking() else { return false }
        do {
            try store?.removeTime(segmentID: item.id, from: start, to: end)
            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason, suspended) in [
            (NSWorkspace.willSleepNotification, "sleep", true),
            (NSWorkspace.didWakeNotification, "sleep", false),
            (NSWorkspace.screensDidSleepNotification, "display", true),
            (NSWorkspace.screensDidWakeNotification, "display", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session", false),
            (NSWorkspace.willPowerOffNotification, "shutdown", true)
        ] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setSuspended(reason, suspended: suspended)
                }
            }
            lifecycleObservers.append((workspace, token))
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, suspended) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let token = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setSuspended("lock", suspended: suspended)
                }
            }
            lifecycleObservers.append((distributed, token))
        }
    }

    private func setSuspended(_ reason: String, suspended: Bool) {
        if suspended {
            suspensionReasons.insert(reason)
            flushTracking()
        } else {
            suspensionReasons.remove(reason)
        }
        tick()
    }

    private func startTracking() {
        timer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        tick()
    }

    private func tick() {
        accessibilityTrusted = reader.accessibilityIsTrusted()
        refreshLoginItemStatus()
        let now = Date()
        if isTrackingPaused || !suspensionReasons.isEmpty {
            enqueue(recorder.observe(nil, at: now, uptime: ProcessInfo.processInfo.systemUptime))
            persistCheckpoints()
            currentSnapshot = nil
            currentClassification = nil
            currentStateLabel = isTrackingPaused ? "Paused" : "Suspended"
            return
        }
        checkScheduledReview()
        let snapshot = reader.currentSnapshot()
        let classification = snapshot.map { classifier.classify(snapshot: $0, rules: rules) }
        let retained = classification?.kind == .ignored ? nil : snapshot
        let contextChanged = recorder.current?.snapshot.normalizedSignature != retained?.normalizedSignature
        currentSnapshot = retained
        currentClassification = classification
        enqueue(recorder.observe(retained, at: now, uptime: ProcessInfo.processInfo.systemUptime))
        let saved = persistCheckpoints()
        if saved && contextChanged { reload() }
        currentStateLabel = saved
            ? (classification?.kind.displayName ?? "Window context unavailable")
            : "Storage error"
    }

    private func enqueue(_ checkpoints: [ActivitySegment]) {
        for segment in checkpoints { pendingCheckpoints[segment.id] = segment }
    }

    @discardableResult
    private func persistCheckpoints() -> Bool {
        do {
            guard let store else { throw HagoStoreError.missingDatabase }
            for segment in pendingCheckpoints.values.sorted(by: { $0.startedAt < $1.startedAt }) {
                let result = classifier.classify(snapshot: segment.snapshot, rules: rules)
                if result.kind != .ignored {
                    try store.checkpoint(segment: segment, classification: SegmentClassification(
                        segmentID: segment.id, kind: result.kind, categoryID: result.categoryID,
                        projectID: result.projectID, ruleID: result.ruleID, isManual: false
                    ))
                }
                pendingCheckpoints.removeValue(forKey: segment.id)
            }
            todaySummary = try store.daySummary(for: Date())
            if !visibleAppWindows.isEmpty {
                todayTimeline = try store.dayTimeline(for: Date())
                if selectedSection == .activity {
                    activitySegments = try store.activitySegments(for: activityDate)
                }
                if selectedSection == .review {
                    reviewSegments = try store.reviewSegments()
                }
            }
            trackingErrorMessage = nil
            return true
        } catch {
            trackingErrorMessage = "Time could not be saved. Hago will retry: \(error.localizedDescription)"
            return false
        }
    }
}

enum ReviewAIAnalysisState: Equatable {
    case idle
    case analyzing
    case completed
    case failed(String)
}
