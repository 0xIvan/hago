import AppKit
import Combine
import Foundation
import HagoCore
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    let workProfileStore = WorkProfileStore()
    let updater = AppUpdater()
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
    @Published var selectedPresetIDs: Set<String> = []
    @Published var learningSuggestions: [CorrectionLearningSuggestion] = []
    @Published var latestCorrectionActionID: UUID?
    @Published var correctionMessage: String?
    private var store: HagoStore?
    private var reviewAIAnalysisService: ReviewAIAnalysisService?
    private var activeReviewIsScheduled = false
    private var timer: Timer?
    private var captureTask: Task<Void, Never>?
    private var captureRevision = 0
    @Published var captureCapabilityLabel = "Checking capture capabilities"
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
                workProfileStore.prepare(hasHistory: try !store.recentSegments(limit: 1).isEmpty, presetIDs: try store.enabledPresetIDs())
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

        return "\(workDuration) · \(totalDuration)"
    }

    var menuBarAccessibilityLabel: String {
        func spokenDuration(_ seconds: TimeInterval) -> String {
            let wholeMinutes = max(0, Int(seconds.rounded())) / 60
            return Duration.seconds(wholeMinutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        }
        return "Hago. Work: \(spokenDuration(todaySummary.workSeconds)). Total tracked: \(spokenDuration(todayTrackedSeconds))."
    }

    var todayTrackedSeconds: TimeInterval {
        todaySummary.workSeconds + todaySummary.personalSeconds + todaySummary.reviewSeconds
    }

    var selectedReviewAIHarnessStatus: ReviewAIHarnessStatus? {
        reviewAIHarnessStatuses.first { $0.harness == reviewAISettings.selectedHarness }
    }

    var selectedReviewAIHarnessIsConfirmed: Bool {
        let harness = reviewAISettings.selectedHarness
        return harness == .disabled || (reviewAISettings.confirmedHarnesses.contains(harness)
            && (!harness.isDirectProvider || reviewAISettings.directDisclosureVersion == ReviewAIDirectCatalog.disclosureVersion))
    }

    var availableReviewAIModels: [ReviewAIModelOption] {
        if reviewAISettings.selectedHarness.isDirectProvider {
            return ReviewAIDirectCatalog.models(for: reviewAISettings.selectedHarness)
        }
        return selectedReviewAIHarnessStatus?.models ?? []
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
        case .disabled, .anthropic, .openAI:
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

    func applyWorkProfile(_ profile: inout WorkProfile) throws {
        guard let store else { throw CocoaError(.fileNoSuchFile) }
        let domains = profile.workDomains.split(whereSeparator: { $0.isNewline || $0 == "," }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for domain in domains {
            guard let url = URL(string: "https://" + domain), url.host == domain,
                  domain.contains("."), !domain.contains("/"), !domain.contains(":"), !domain.contains("@"), !domain.contains("?"), !domain.contains("#"),
                  domain.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else {
                throw NSError(domain: "WorkProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter plain work-only domains, without URLs, ports or paths."])
            }
        }
        guard flushTracking() else { throw NSError(domain: "WorkProfile", code: 2, userInfo: [NSLocalizedDescriptionKey: trackingErrorMessage ?? "Save tracked time before changing your profile."]) }
        var desired: [String: RuleCondition] = [:]
        for app in profile.workApps { desired["app:" + app] = RuleCondition(field: .bundleIdentifier, operation: .equals, value: app) }
        for domain in domains { desired["host:" + domain] = RuleCondition(field: .host, operation: .equals, value: domain) }
        var updatedProfile = profile
        let removedIDs = profile.ruleIDs.filter { desired[$0.key] == nil }.map(\.value)
        updatedProfile.ruleIDs = profile.ruleIDs.filter { desired[$0.key] != nil }
        let profileRules = desired.map { identity, condition in
            let id = updatedProfile.ruleIDs[identity] ?? UUID()
            updatedProfile.ruleIDs[identity] = id
            return Rule(id: id, name: "Work Profile: " + condition.value, priority: 150, enabled: true, isBuiltIn: false,
                        action: RuleAction(kind: .work, categoryID: categories.first { $0.kind == .work }?.id, projectID: nil), conditions: [condition], origin: .user)
        }
        for (identity, id) in updatedProfile.ruleIDs { profile.ruleIDs[identity] = id }
        try store.applyWorkProfile(presetIDs: profile.presetIDs, rules: profileRules, removingRuleIDs: removedIDs)
        profile = updatedProfile
        try refresh()
        clearReviewAISuggestions()
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
        selectedPresetIDs = try store.enabledPresetIDs()
        learningSuggestions = try store.learningSuggestions()
        latestCorrectionActionID = try store.latestCorrectionActionID()
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
    ) -> ReportComparison? {
        do {
            guard let store else {
                return nil
            }

            let comparison = try store.reportComparison(for: periodKind, containing: date, now: Date())
            errorMessage = nil

            return comparison
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private var reviewAIAnalysisContext: ReviewAIAnalysisContext {
        ReviewAIAnalysisContext(
            harness: reviewAISettings.selectedHarness,
            model: reviewAISettings.selectedModel(for: reviewAISettings.selectedHarness)
                ?? (reviewAISettings.selectedHarness.isDirectProvider ? availableReviewAIModels.first?.modelID : nil),
            reasoning: effectiveReviewAIReasoningEffort,
            profession: reviewAISettings.profession,
            disclosure: reviewAISettings.selectedHarness.isDirectProvider
                ? "v\(reviewAISettings.directDisclosureVersion)-titles-\(reviewAISettings.shareRedactedTitles)" : nil
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
        let status = selectedReviewAIHarnessStatus
        if !selectedHarness.isDirectProvider, status?.isAvailable != true || status?.executablePath == nil {
            reviewAIAnalysisFailed("\(selectedHarness.displayName) is not available. Refresh AI suggestions settings.", scheduled: scheduled)
            return
        }
        let credential: String?
        do {
            credential = selectedHarness.isDirectProvider ? try ReviewAICredentialStore().read(for: selectedHarness) : nil
        } catch {
            reviewAIAnalysisFailed(error.localizedDescription, scheduled: scheduled)
            return
        }
        let disclosureVersion = reviewAISettings.directDisclosureVersion
        let shareTitles = reviewAISettings.shareRedactedTitles

        reviewAIAnalysisState = .analyzing
        activeReviewIsScheduled = scheduled
        let revision = reviewAIRevision
        let context = reviewAIAnalysisContext
        let automaticallyApply = scheduled
            ? reviewAISettings.automaticallyApplyScheduledReviews
            : reviewAISettings.automaticallyApplyHighConfidence

        reviewAIAnalysisTask = Task { @MainActor in
            do {
                let provider: any ReviewAISuggestionProviding
                if selectedHarness.isDirectProvider {
                    provider = DirectReviewAISuggestionProvider(
                        provider: selectedHarness, model: context.model ?? "", apiKey: credential ?? "",
                        consentVersion: disclosureVersion, shareTitles: shareTitles, profession: context.profession
                    )
                } else {
                    let environment = await reviewAIHarnessDiscovery.repairedEnvironment(from: ProcessInfo.processInfo.environment)
                    provider = CLIReviewAISuggestionProvider(
                        harness: selectedHarness, executablePath: status?.executablePath ?? "",
                        environment: environment, model: context.model, reasoningEffort: context.reasoning,
                        profession: context.profession
                    )
                }
                let result = try await service.analyze(
                    provider: provider, context: context, harnessVersion: selectedHarness.isDirectProvider ? "direct-v1-\(shareTitles)" : status?.version,
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

    func saveDirectAICredential(_ key: String) throws {
        try ReviewAICredentialStore().save(key, for: reviewAISettings.selectedHarness)
        stopReviewAIAnalysis()
        errorMessage = nil
    }

    func disconnectDirectAI() throws {
        stopReviewAIAnalysis()
        try ReviewAICredentialStore().remove(for: reviewAISettings.selectedHarness)
        setReviewAIHarnessConfirmed(false)
    }

    func setReviewAIShareTitles(_ enabled: Bool) {
        reviewAISettings.shareRedactedTitles = enabled
        reviewAISettings.confirmedHarnesses.remove(.anthropic)
        reviewAISettings.confirmedHarnesses.remove(.openAI)
        setReviewAIScheduleEnabled(false)
        saveReviewAISettings()
    }

    func selectReviewAIHarness(_ harness: ReviewAIHarnessKind) {
        if harness == .disabled || (harness != reviewAISettings.selectedHarness
            && (harness.isDirectProvider || reviewAISettings.selectedHarness.isDirectProvider)) {
            setReviewAIScheduleEnabled(false)
        }
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
            if harness.isDirectProvider { reviewAISettings.directDisclosureVersion = ReviewAIDirectCatalog.disclosureVersion }
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
        guard reviewSegments.contains(where: { group.segmentIDs.contains($0.id) }) else { return }
        let categoryID = categories.first { $0.kind == kind }?.id

        do {
            _ = try store?.correctSegments(ids: group.segmentIDs, kind: kind, categoryID: categoryID)
            correctionMessage = kind == .ignored ? "Selected recordings removed permanently." : "Selected recordings updated. Remember a scope separately to teach Hago."

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
                _ = try store?.correctSegments(ids: [segment.id], kind: kind, categoryID: categoryID)
            }

            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEnabledPresets(_ ids: Set<String>) {
        guard flushTracking() else { return }
        do {
            try store?.setEnabledPresetIDs(ids)
            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func classificationExplanation(for entry: ClassifiedSegment) -> String {
        (try? store?.classificationExplanation(for: entry)) ?? "Classification reason unavailable"
    }

    func previewRememberedRule(_ rule: Rule) throws -> RuleImpactPreview {
        guard let store else { throw HagoStoreError.missingDatabase }
        return try store.previewRememberedRule(rule)
    }

    func rememberRule(_ rule: Rule) {
        guard flushTracking() else { return }
        do {
            _ = try store?.applyRememberedRule(rule)
            correctionMessage = "Rule remembered. Existing explicit corrections and project assignments were preserved."
            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func undoLatestCorrection() {
        guard flushTracking(), let id = latestCorrectionActionID else { return }
        do {
            let count = try store?.undoCorrection(id: id) ?? 0
            correctionMessage = "Undid the last correction or learned rule (\(count) retained recordings restored). Later choices are preserved."
            try refresh()
            clearReviewAISuggestions()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func dismissLearningSuggestion(_ suggestion: CorrectionLearningSuggestion) {
        do {
            try store?.dismissLearningSuggestion(suggestion)
            try refresh()
        } catch { errorMessage = error.localizedDescription }
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
        captureRevision += 1
        captureTask?.cancel()
        captureTask = nil
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
            captureRevision += 1
            captureTask?.cancel()
            captureTask = nil
            enqueue(recorder.observe(nil, at: now, uptime: ProcessInfo.processInfo.systemUptime))
            persistCheckpoints()
            currentSnapshot = nil
            currentClassification = nil
            currentStateLabel = isTrackingPaused ? "Paused" : "Suspended"
            return
        }
        checkScheduledReview()
        captureCapabilityLabel = reader.captureCapabilityLabel()
        guard captureTask == nil else { return }
        let revision = captureRevision
        captureTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await reader.currentSnapshot()
            guard !Task.isCancelled, revision == captureRevision else { return }
            captureTask = nil
            guard !isTrackingPaused, suspensionReasons.isEmpty else { return }
            let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let valid = snapshot.flatMap { $0.processIdentifier == foregroundPID ? $0 : nil }
            recordObservation(valid)
        }
    }

    private func recordObservation(_ snapshot: ActivitySnapshot?) {
        let classification = snapshot.map { classifier.classify(snapshot: $0, rules: rules) }
        let retained = classification?.kind == .ignored ? nil : snapshot
        let contextChanged = recorder.current?.snapshot.normalizedSignature != retained?.normalizedSignature
        currentSnapshot = retained
        currentClassification = classification
        enqueue(recorder.observe(retained, at: Date(), uptime: ProcessInfo.processInfo.systemUptime))
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
