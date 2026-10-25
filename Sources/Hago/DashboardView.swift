import Charts
import SwiftUI
import HagoCore

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: WorkProfileStore

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedSection) {
                Section {
                    ForEach(HagoSection.primarySections) { section in
                        SidebarSectionLabel(section: section, reviewCount: appState.reviewGroups.count)
                            .tag(section)
                    }
                }
                Section("Settings") {
                    ForEach(HagoSection.settingsSections) { section in
                        SidebarSectionLabel(section: section, reviewCount: appState.reviewGroups.count)
                            .tag(section)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            selectedSectionView
                .navigationTitle(appState.selectedSection.title)
        }
        .frame(minWidth: 850, minHeight: 650)
        .background(WindowLifecycleView(id: "dashboard"))
        .sheet(isPresented: $profileStore.needsSetup, onDismiss: appState.relaunchAfterOnboardingDismissal) {
            OnboardingView().environmentObject(appState).environmentObject(profileStore)
        }
        .onChange(of: appState.selectedSection) { _, _ in appState.reload() }
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch appState.selectedSection {
        case .overview:
            OverviewTab()
        case .reports:
            ReportsView()
        case .review:
            ReviewTab()
        case .activity:
            RecentActivityTab()
        case .tracking:
            TrackingSettingsView()
        case .rules:
            RulesManagementView()
        case .projects:
            ProjectsSettingsView()
        case .categories:
            CategoriesSettingsView()
        case .privacy:
            PrivacySettingsView()
        case .aiReview:
            ReviewAISettingsView()
        }
    }
}

private struct SidebarSectionLabel: View {
    let section: HagoSection
    let reviewCount: Int

    var body: some View {
        if section == .review && reviewCount > 0 {
            Label(section.title, systemImage: section.symbolName)
                .badge(reviewCount)
        } else {
            Label(section.title, systemImage: section.symbolName)
        }
    }
}

private struct OverviewTab: View {
    @EnvironmentObject private var appState: AppState
    private let formatter = TimeFormatting()

    var body: some View {
        VStack(spacing: 0) {
            PageTop {
                PageHeader(
                    title: "Today",
                    subtitle: "\(appState.todaySummary.date.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(HagoDuration.text(appState.todayTrackedSeconds)) tracked"
                ) {
                    if !appState.reviewGroups.isEmpty {
                        Button {
                            appState.selectedSection = .review
                        } label: {
                            Label("Review \(appState.reviewGroups.count)", systemImage: HagoSection.review.symbolName)
                        }
                    }
                    Button {
                        appState.selectedSection = .activity
                    } label: {
                        Label("Activity", systemImage: HagoSection.activity.symbolName)
                    }
                }
            }
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !appState.accessibilityTrusted {
                    AccessibilityAccessPanel()
                }

                HStack(spacing: 12) {
                    MetricView(title: "Work", value: formatter.compactDuration(appState.todaySummary.workSeconds), color: ActivityKind.work.tint)
                    MetricView(title: "Personal", value: formatter.compactDuration(appState.todaySummary.personalSeconds), color: ActivityKind.personal.tint)
                    MetricView(title: ActivityKind.review.displayName, value: formatter.compactDuration(appState.todaySummary.reviewSeconds), color: ActivityKind.review.tint)
                }

                HStack(alignment: .top, spacing: 16) {
                    SectionPanel(title: "Today’s Timeline") {
                        DailyTimelineChart(day: appState.todaySummary.date, entries: appState.todayTimeline)
                            .id(appState.todaySummary.date)
                            .frame(height: 420)
                    }

                    SectionPanel(title: "Top Apps & Sites") {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach([ActivityKind.work, .personal]) { kind in
                                if kind == .personal {
                                    Divider()
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    Text(kind.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(kind.tint)
                                    BucketListView(buckets: appState.todaySummary.topApps.filter { $0.kind == kind })
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private enum ReviewSort: String, CaseIterable, Identifiable {
    case recent
    case longest
    case suggested

    var id: Self { self }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .longest: "Longest"
        case .suggested: "AI First"
        }
    }
}

private struct ReviewEntry: Identifiable {
    let group: AggregatedActivity
    let item: ClassifiedSegment
    let suggestion: ReviewAISuggestion?

    var id: String { group.id }
}

private struct ReviewTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var inspectingRun: ReviewAIRunSummary?
    @State private var rememberingRule: Rule?
    @State private var selectedGroupID: String?
    @State private var hoveredGroupID: String?
    @State private var sort = ReviewSort.recent
    @State private var confirmsBulkAccept = false
    @FocusState private var listHasKeyboardFocus: Bool

    private var entries: [ReviewEntry] {
        let suggestionsByID = Dictionary(
            appState.reviewAISuggestions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let entries = appState.reviewGroups.compactMap { group -> ReviewEntry? in
            guard let item = appState.reviewSegments.first(where: { group.segmentIDs.contains($0.id) }) else {
                return nil
            }
            let suggestion = suggestionsByID.isEmpty
                ? nil
                : ReviewAISuggestionRequest(reviewSegments: [item]).groups.first.flatMap { suggestionsByID[$0.id] }
            return ReviewEntry(group: group, item: item, suggestion: suggestion)
        }

        switch sort {
        case .recent:
            return entries
        case .longest:
            return entries.sorted { $0.group.duration > $1.group.duration }
        case .suggested:
            return entries.enumerated().sorted { first, second in
                let firstConfidence = first.element.suggestion.map { (ReviewSuggestionChoice.canAccept($0) ? 1 : 0) + $0.confidence } ?? -1
                let secondConfidence = second.element.suggestion.map { (ReviewSuggestionChoice.canAccept($0) ? 1 : 0) + $0.confidence } ?? -1
                if firstConfidence != secondConfidence { return firstConfidence > secondConfidence }
                return first.offset < second.offset
            }
            .map(\.element)
        }
    }

    private var confidentSuggestions: [ReviewAISuggestion] {
        appState.reviewAISuggestions.filter { suggestion in
            (suggestion.kind == .work || suggestion.kind == .personal)
                && suggestion.confidence >= 0.9
                && ReviewAISuggestionValidator().validationResult(for: suggestion).canApply
        }
    }

    var body: some View {
        let entries = entries
        let selectedID = selectedID(in: entries)
        VStack(spacing: 0) {
            header(entries)
            ScrollViewReader { proxy in
                List {
                    CorrectionBanner()
                    LearningSuggestionsSection()
                    reviewItemsSection(entries, selectedID: selectedID)
                }
                .listStyle(.inset)
                .focusable()
                .focusEffectDisabled()
                .focused($listHasKeyboardFocus)
                .onAppear { listHasKeyboardFocus = true }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard let index = entries.firstIndex(where: { $0.id == selectedID }) else { return .ignored }
                    let next = press.key == .upArrow ? index - 1 : index + 1
                    guard entries.indices.contains(next) else { return .handled }
                    selectedGroupID = entries[next].id
                    proxy.scrollTo(entries[next].id)
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "wWpPiIaA")) { press in
                    guard press.modifiers.intersection([.command, .control, .option]).isEmpty,
                          let entry = entries.first(where: { $0.id == selectedID }) else { return .ignored }
                    switch press.characters.lowercased() {
                    case "w": classify(entry, as: .work, in: entries)
                    case "p": classify(entry, as: .personal, in: entries)
                    case "i": classify(entry, as: .ignored, in: entries)
                    default:
                        guard let suggestion = entry.suggestion, ReviewSuggestionChoice.canAccept(suggestion) else {
                            return .ignored
                        }
                        accept(suggestion, for: entry, in: entries)
                    }
                    return .handled
                }
            }
        }
        .sheet(item: $rememberingRule) { rule in
            RememberRulePreviewView(rule: rule).environmentObject(appState)
        }
        .sheet(item: $inspectingRun) { run in
            AppliedReviewRulesView(run: run)
                .environmentObject(appState)
        }
        .confirmationDialog(
            "Accept \(confidentSuggestions.count) AI suggestions?",
            isPresented: $confirmsBulkAccept
        ) {
            Button("Create \(confidentSuggestions.count) Rules") {
                appState.applyReviewAISuggestions(confidentSuggestions)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each suggestion at 90% confidence or higher becomes a Work or Personal rule and reclassifies its \(confidentSuggestions.reduce(0) { $0 + $1.affectedCount }) recordings. You can edit or delete the rules in Rules.")
        }
    }

    private func selectedID(in entries: [ReviewEntry]) -> String? {
        if let selectedGroupID, entries.contains(where: { $0.id == selectedGroupID }) {
            return selectedGroupID
        }
        return entries.first?.id
    }

    private func selectNext(after entry: ReviewEntry, removing removedIDs: Set<String>, in entries: [ReviewEntry]) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let remaining = entries.enumerated().filter { !removedIDs.contains($0.element.id) }
        selectedGroupID = remaining.first(where: { $0.offset > index })?.element.id ?? remaining.last?.element.id
    }

    private func classify(_ entry: ReviewEntry, as kind: ActivityKind, in entries: [ReviewEntry]) {
        selectNext(after: entry, removing: [entry.id], in: entries)
        appState.classifyReviewGroup(entry.group, as: kind)
    }

    private func accept(_ suggestion: ReviewAISuggestion, for entry: ReviewEntry, in entries: [ReviewEntry]) {
        let covered = Set(entries.filter { $0.suggestion?.id == suggestion.id }.map(\.id))
        selectNext(after: entry, removing: covered.union([entry.id]), in: entries)
        appState.applyReviewAISuggestion(suggestion, as: suggestion.kind)
    }

    private func header(_ entries: [ReviewEntry]) -> some View {
        PageTop {
            PageHeader(
                title: entries.isEmpty ? "All caught up" : "\(entries.count) to review",
                subtitle: entries.isEmpty
                    ? "New activity Hago can't classify will show up here."
                    : "\(HagoDuration.text(entries.reduce(0) { $0 + $1.group.duration })) unclassified across \(appState.reviewSegments.count) recordings"
            ) {
                if !entries.isEmpty {
                    Picker("Sort", selection: $sort) {
                        ForEach(ReviewSort.allCases.filter { $0 != .suggested || !appState.reviewAISuggestions.isEmpty }) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                aiButton
            }

            aiStatus
        }
    }

    @ViewBuilder
    private var aiButton: some View {
        if appState.reviewAIAnalysisState == .analyzing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button("Stop", role: .destructive) { appState.stopReviewAIAnalysis() }
            }
        } else if appState.reviewAISettings.selectedHarness == .disabled {
            Button {
                appState.openHagoWindow(section: .aiReview)
            } label: {
                Label("Set Up AI…", systemImage: "sparkles")
            }
            .help("Connect an AI provider to suggest how to file this activity")
        } else if !confidentSuggestions.isEmpty {
            Button {
                confirmsBulkAccept = true
            } label: {
                Label("Accept \(confidentSuggestions.count) Confident", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .help("Accept every AI suggestion at 90% confidence or higher")
        } else {
            Button {
                appState.analyzeReview()
            } label: {
                Label("Suggest with AI", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.reviewSegments.isEmpty)
            .help("Ask \(appState.reviewAISettings.selectedHarness.displayName) to suggest rules")
        }
    }

    @ViewBuilder
    private var aiStatus: some View {
        let run = appState.lastReviewAIRunSummary.flatMap { $0.automaticallyAppliedCount > 0 ? $0 : nil }
        let suggestionCount = appState.reviewAISuggestions.count
        let message: (text: String, isError: Bool)? = switch appState.reviewAIAnalysisState {
        case .analyzing:
            ("Analyzing with \(appState.reviewAISettings.selectedHarness.displayName)…", false)
        case .failed(let message):
            (message, true)
        case .completed where suggestionCount == 0:
            ("No AI suggestions this time. Classify the items below by hand.", false)
        default:
            suggestionCount > 0 ? ("\(suggestionCount) AI suggestion\(suggestionCount == 1 ? "" : "s") shown on the items below. Press A to accept one.", false) : nil
        }

        if message != nil || run != nil || appState.lastReviewAIUndoMessage != nil {
            HStack(spacing: 8) {
                Image(systemName: message?.isError == true ? "exclamationmark.triangle.fill" : "sparkles")
                    .foregroundStyle(message?.isError == true ? Color.red : Color.purple)
                if let message {
                    Text(message.text)
                        .foregroundStyle(message.isError ? Color.red : Color.secondary)
                        .lineLimit(2)
                }
                if let undoMessage = appState.lastReviewAIUndoMessage {
                    Text(undoMessage).foregroundStyle(.secondary)
                }
                Spacer()
                if let run {
                    Text("Auto-applied \(run.automaticallyAppliedCount) rule\(run.automaticallyAppliedCount == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Button("View") { inspectingRun = run }
                    if run.status == .completed {
                        Button("Undo") { appState.undoLastReviewAIRun() }
                    }
                }
                if suggestionCount > 0, sort != .suggested {
                    Button("Show AI First") { sort = .suggested }
                }
            }
            .font(.callout)
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func reviewItemsSection(_ entries: [ReviewEntry], selectedID: String?) -> some View {
        Section {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("Activity that needs a decision will appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }

            ForEach(entries) { entry in
                let isSelected = entry.id == selectedID
                ReviewGroupRow(
                    entry: entry,
                    explanation: appState.classificationExplanation(for: entry.item),
                    recordingSummary: recordingSummary(for: entry.group),
                    duration: HagoDuration.text(entry.group.duration),
                    rememberOptions: rememberOptions(for: entry.item),
                    showsActions: isSelected || entry.id == hoveredGroupID,
                    classify: { kind in classify(entry, as: kind, in: entries) },
                    accept: { suggestion in accept(suggestion, for: entry, in: entries) },
                    remember: { rememberingRule = $0 }
                )
                .id(entry.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedGroupID = entry.id
                    listHasKeyboardFocus = true
                }
                .onHover { hovering in
                    if hovering {
                        hoveredGroupID = entry.id
                    } else if hoveredGroupID == entry.id {
                        hoveredGroupID = nil
                    }
                }
                .hagoRowBackground(isSelected: isSelected, isHovered: entry.id == hoveredGroupID)
            }
        } header: {
            if !entries.isEmpty {
                HStack {
                    Text("Needs a decision")
                    Spacer()
                    Text("↑ ↓ move · W Work · P Personal · I Ignore · A Accept AI")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func rememberOptions(for item: ClassifiedSegment) -> [Rule] {
        [ActivityKind.work, .personal].flatMap { kind in
            RememberedRuleFactory().rules(
                from: item,
                kind: kind,
                categoryID: appState.categories.first(where: { $0.kind == kind })?.id
            )
        }
    }

    private func recordingSummary(for group: AggregatedActivity) -> String {
        if group.segmentCount == 1 {
            return group.firstStartedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        let first = group.firstStartedAt.formatted(.dateTime.month(.abbreviated).day())
        let last = group.lastEndedAt.formatted(.dateTime.month(.abbreviated).day())
        let dateRange = Calendar.current.isDate(group.firstStartedAt, inSameDayAs: group.lastEndedAt)
            ? first : "\(first)–\(last)"
        return "\(group.segmentCount) recordings · \(dateRange)"
    }
}

private enum ReviewSuggestionChoice {
    static func kind(_ suggestion: ReviewAISuggestion) -> ActivityKind? {
        switch suggestion.kind {
        case .work: .work
        case .personal: .personal
        case .ignored: .ignored
        case .unsure: nil
        }
    }

    static func canAccept(_ suggestion: ReviewAISuggestion) -> Bool {
        kind(suggestion) != nil && ReviewAISuggestionValidator().validationResult(for: suggestion).canApply
    }
}

private struct ReviewGroupRow: View {
    let entry: ReviewEntry
    let explanation: String
    let recordingSummary: String
    let duration: String
    let rememberOptions: [Rule]
    let showsActions: Bool
    let classify: (ActivityKind) -> Void
    let accept: (ReviewAISuggestion) -> Void
    let remember: (Rule) -> Void

    private var segment: ActivitySegment { entry.item.segment }

    private var title: String {
        if !segment.snapshot.host.isEmpty { return segment.snapshot.host }
        return segment.windowTitle.isEmpty ? segment.appName : segment.windowTitle
    }

    private var meta: String {
        var parts: [String] = []
        if title != segment.appName { parts.append(segment.appName) }
        if !segment.windowTitle.isEmpty, title != segment.windowTitle { parts.append(segment.windowTitle) }
        parts.append(recordingSummary)
        return parts.joined(separator: " · ")
    }

    private var showsExplanation: Bool {
        explanation.hasPrefix("Conflicting rules")
    }

    private var tooltip: String {
        [segment.url, explanation].compactMap { $0 }.joined(separator: "\n")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconView(bundleIdentifier: segment.snapshot.bundleIdentifier, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(meta)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if showsExplanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                if segment.snapshot.isDiscordWithoutTitle {
                    Text("Channel titles were not captured. Your choice applies only to these recordings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let suggestion = entry.suggestion {
                    SuggestionLine(suggestion: suggestion)
                }
            }
            .help(tooltip)

            Spacer(minLength: 12)

            actions
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)

            Text(duration)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if let suggestion = entry.suggestion,
               ReviewSuggestionChoice.canAccept(suggestion),
               let kind = ReviewSuggestionChoice.kind(suggestion) {
                Button {
                    accept(suggestion)
                } label: {
                    Label(kind == .ignored ? "Accept Ignore" : "Accept \(kind.displayName)", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .help("Create the suggested rule and file \(suggestion.affectedCount) recording\(suggestion.affectedCount == 1 ? "" : "s") (A)")
            }

            ClassifyButtons(currentKind: .review, classify: classify)

            if !rememberOptions.isEmpty {
                Menu {
                    ForEach([ActivityKind.work, .personal]) { kind in
                        let options = rememberOptions.filter { $0.action.kind == kind }
                        if !options.isEmpty {
                            Section("Always \(kind.displayName)") {
                                ForEach(options) { rule in
                                    Button(optionTitle(rule)) { remember(rule) }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .accessibilityLabel("Always")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Always classify matching activity this way, including past recordings")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func optionTitle(_ rule: Rule) -> String {
        let name = rule.name.hasPrefix("Remember ") ? String(rule.name.dropFirst("Remember ".count)) : rule.name
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

private struct SuggestionLine: View {
    let suggestion: ReviewAISuggestion

    private var color: Color {
        ReviewSuggestionChoice.kind(suggestion)?.tint ?? ActivityKind.review.tint
    }

    private var label: String {
        switch suggestion.kind {
        case .unsure: "AI unsure"
        case .ignored: "AI: Ignore"
        default: "AI: \(suggestion.kind.displayName)"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Label(label, systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text("\(Int(round(suggestion.confidence * 100)))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(suggestion.reason)
    }
}

private struct AppliedReviewRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var details: [ReviewAIAppliedRule] = []
    @State private var editingRule: Rule?

    let run: ReviewAIRunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Applied Rules")
                        .font(.title2.weight(.semibold))
                    Text("\(run.harness.displayName) · \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            List {
                ForEach(details) { detail in
                    HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(detail.currentRule?.name ?? detail.appliedCondition.value)
                            .font(.headline)
                        Text("\(detail.appliedCondition.field.displayName) \(detail.appliedCondition.operation.displayName) \(detail.appliedCondition.value)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(detail.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text("\(Int((detail.confidence * 100).rounded()))% confidence")
                            Text(detail.appliedKind.displayName)
                            Text(stateLabel(detail.state))
                                .foregroundStyle(detail.state == .unchanged ? Color.secondary : Color.orange)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let rule = detail.currentRule {
                        Button(rule.enabled ? "Disable" : "Enable") {
                            var updatedRule = rule
                            updatedRule.enabled.toggle()
                            appState.saveRule(updatedRule, reclassify: .today)
                            reload()
                        }
                        Button("Edit") {
                            editingRule = rule
                        }
                    }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 480)
        .onAppear(perform: reload)
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                projects: appState.projects,
                categories: appState.categories,
                onDelete: { deletedRule, scope in
                    appState.deleteRule(id: deletedRule.id, reclassify: scope)
                    reload()
                },
                onSave: { savedRule, scope in
                    appState.saveRule(savedRule, reclassify: scope)
                    reload()
                }
            )
        }
    }

    private func reload() {
        details = appState.appliedReviewAIRules(for: run.id)
    }

    private func stateLabel(_ state: ReviewAIAppliedRuleState) -> String {
        switch state {
        case .unchanged:
            "Unchanged"
        case .changed:
            "Changed after analysis"
        case .removed:
            "Removed"
        }
    }
}

private struct PendingIgnore: Identifiable {
    let id = UUID()
    let segmentIDs: [UUID]
    let title: String
    let duration: TimeInterval
}

private struct RecentActivityTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var kindFilter: ActivityKind?
    @State private var projectFilterID = ActivityProjectFilter.all
    @State private var sort = ActivitySort.newest
    @State private var presentation = ActivityPresentation.grouped
    @State private var ruleInspection: ActivityRuleInspection?
    @State private var timeEditing: ClassifiedSegment?
    @State private var pendingIgnore: PendingIgnore?
    @State private var hoveredID: String?
    @State private var showsCalendar = false

    private let calendar = HagoCalendar.shared

    private var dayStart: Date {
        calendar.dayInterval(containing: appState.activityDate).start
    }

    private var isToday: Bool {
        dayStart == calendar.dayInterval(containing: Date()).start
    }

    private var dayTitle: String {
        if isToday { return "Today" }
        let yesterday = calendar.dayInterval(containing: Date()).start.addingTimeInterval(-86_400)
        if dayStart == calendar.dayInterval(containing: yesterday).start { return "Yesterday" }
        return dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var searchedSegments: [ClassifiedSegment] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return appState.activitySegments.filter { item in
            if projectFilterID == ActivityProjectFilter.none, item.classification.projectID != nil {
                return false
            }

            if projectFilterID != ActivityProjectFilter.all, projectFilterID != ActivityProjectFilter.none,
               item.classification.projectID?.uuidString != projectFilterID {
                return false
            }

            guard !trimmedSearchText.isEmpty else {
                return true
            }

            return [
                item.segment.appName,
                item.segment.windowTitle,
                item.segment.url ?? "",
                item.projectName ?? "",
                categoryName(for: item)
            ]
                .contains { value in
                    value.lowercased().contains(trimmedSearchText)
                }
        }
    }

    var body: some View {
        let searched = searchedSegments
        let displayed = searched.filter { kindFilter == nil || $0.classification.kind == kindFilter }
        let segmentsByID = Dictionary(appState.activitySegments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = sortedGroups(ActivityAggregation.groups(from: displayed))
        let segments = sortedSegments(displayed)
        let longest = groups.map(\.duration).max() ?? 1

        VStack(spacing: 0) {
            PageTop {
                PageHeader(title: dayTitle, subtitle: daySubtitle) {
                    Button {
                        showsCalendar = true
                    } label: {
                        Label("Choose Date", systemImage: "calendar")
                    }
                    .labelStyle(.iconOnly)
                    .help("Choose a date")
                    .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                        DatePicker(
                            "Date",
                            selection: Binding(
                                get: { appState.activityDate },
                                set: { date in
                                    appState.selectActivityDate(date)
                                    showsCalendar = false
                                }
                            ),
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding()
                    }

                    PeriodNavigator(
                        currentTitle: "Today",
                        isCurrent: isToday,
                        canGoForward: !isToday,
                        step: { offset in
                            appState.selectActivityDate(dayStart.addingTimeInterval(Double(offset) * 86_400 + 4 * 3_600))
                        },
                        reset: { appState.selectActivityDate(Date()) }
                    )
                }

                kindChips(searched)

                HStack(spacing: 10) {
                    SearchField(text: $searchText, prompt: "Search apps, sites, titles")

                    FilterMenu(
                        activeCount: projectFilterID == ActivityProjectFilter.all ? 0 : 1,
                        clear: { projectFilterID = ActivityProjectFilter.all }
                    ) {
                        Picker("Project", selection: $projectFilterID) {
                            Text("Any Project").tag(ActivityProjectFilter.all)
                            Text("No Project").tag(ActivityProjectFilter.none)
                            ForEach(appState.projects) { project in
                                Text(project.name).tag(project.id.uuidString)
                            }
                        }
                    }

                    Picker("Sort", selection: $sort) {
                        ForEach(ActivitySort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Picker("View", selection: $presentation) {
                        ForEach(ActivityPresentation.allCases) { presentation in
                            Text(presentation.title).tag(presentation)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            List {
                CorrectionBanner()

                if displayed.isEmpty {
                    ContentUnavailableView {
                        Label(
                            appState.activitySegments.isEmpty ? "No activity" : "No matching activity",
                            systemImage: "clock"
                        )
                    } description: {
                        Text(appState.activitySegments.isEmpty
                             ? "Nothing was recorded on this day."
                             : "Try a different search or clear the filters.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                if presentation == .grouped {
                    ForEach(groups) { group in
                        groupRow(group, sample: group.segmentIDs.lazy.compactMap { segmentsByID[$0] }.first, longest: longest)
                    }
                } else {
                    ForEach(segments) { item in
                        segmentRow(item)
                    }
                }
            }
            .listStyle(.inset)
        }
        .sheet(item: $ruleInspection) { inspection in
            ActivityRuleInspectorView(inspection: inspection)
                .environmentObject(appState)
        }
        .sheet(item: $timeEditing) { item in
            ActivityTimeEditor(item: item).environmentObject(appState)
        }
        .confirmationDialog(
            "Ignore \(pendingIgnore?.title ?? "")?",
            isPresented: Binding(get: { pendingIgnore != nil }, set: { if !$0 { pendingIgnore = nil } }),
            presenting: pendingIgnore
        ) { ignore in
            Button("Delete \(ignore.segmentIDs.count) Recording\(ignore.segmentIDs.count == 1 ? "" : "s")", role: .destructive) {
                appState.reclassifyActivity(segmentIDs: ignore.segmentIDs, as: .ignored)
            }
            Button("Cancel", role: .cancel) {}
        } message: { ignore in
            Text("\(HagoDuration.text(ignore.duration)) will be removed permanently. To stop recording it in future, add it to Privacy → Never record.")
        }
        .onAppear {
            appState.selectActivityDate(calendar.dayInterval(containing: Date()).start)
        }
    }

    private var daySubtitle: String {
        let total = appState.activitySegments.reduce(0) { $0 + $1.segment.duration }
        let count = appState.activitySegments.count
        guard count > 0 else { return dayStart.formatted(date: .complete, time: .omitted) }
        return "\(HagoDuration.text(total)) tracked · \(count) recording\(count == 1 ? "" : "s")"
    }

    private func kindChips(_ segments: [ClassifiedSegment]) -> some View {
        let totals = Dictionary(grouping: segments, by: \.classification.kind)
            .mapValues { $0.reduce(0) { $0 + $1.segment.duration } }
        let kinds = [ActivityKind.work, .personal, .review].filter { totals[$0, default: 0] > 0 || kindFilter == $0 }

        return HStack(spacing: 8) {
            KindFilterChip(
                title: "All",
                duration: totals.values.reduce(0, +),
                tint: .secondary,
                isSelected: kindFilter == nil,
                select: { kindFilter = nil }
            )
            ForEach(kinds) { kind in
                KindFilterChip(
                    title: kind.displayName,
                    duration: totals[kind, default: 0],
                    tint: kind.tint,
                    isSelected: kindFilter == kind,
                    select: { kindFilter = kindFilter == kind ? nil : kind }
                )
            }
            Spacer()
        }
    }

    private func groupRow(_ group: AggregatedActivity, sample: ClassifiedSegment?, longest: TimeInterval) -> some View {
        let isHovered = hoveredID == group.id
        return HStack(spacing: 12) {
            AppIconView(bundleIdentifier: sample?.segment.snapshot.bundleIdentifier ?? "", size: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                    ActivityKindBadge(kind: group.kind)
                    if let projectName = group.projectName {
                        ProjectLabel(name: projectName)
                    }
                }
                Text(groupMeta(group))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Capsule()
                    .fill(group.kind.tint.opacity(0.55))
                    .frame(width: max(4, 180 * group.duration / max(longest, 1)), height: 4)
            }

            Spacer(minLength: 12)

            rowActions(currentKind: group.kind, isVisible: isHovered) { kind in
                classify(group.segmentIDs, title: group.name, duration: group.duration, as: kind)
            }

            Text(HagoDuration.text(group.duration))
                .font(.body.monospacedDigit())
                .frame(minWidth: 52, alignment: .trailing)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let sample else { return }
            ruleInspection = ActivityRuleInspection(
                id: group.id,
                title: group.name,
                detail: "\(group.segmentCount) recordings · \(HagoDuration.text(group.duration))",
                sample: sample,
                appliedRuleIDs: group.appliedRuleIDs
            )
        }
        .onHover { hovering in updateHover(group.id, hovering) }
        .hagoRowBackground(isSelected: false, isHovered: isHovered)
        .help("Click to see why it was classified this way")
    }

    private func segmentRow(_ item: ClassifiedSegment) -> some View {
        let id = item.id.uuidString
        let isHovered = hoveredID == id
        let segment = item.segment
        let title = segment.windowTitle.isEmpty ? activityName(for: item) : segment.windowTitle
        var meta = [segment.appName]
        if !segment.snapshot.host.isEmpty { meta.append(segment.snapshot.host) }

        return HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(segment.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.callout.monospacedDigit())
                Text(segment.endedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 64, alignment: .trailing)

            AppIconView(bundleIdentifier: segment.snapshot.bundleIdentifier, size: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ActivityKindBadge(kind: item.classification.kind)
                    if let projectName = item.projectName {
                        ProjectLabel(name: projectName)
                    }
                }
                Text(meta.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                rowActions(currentKind: item.classification.kind, isVisible: true) { kind in
                    classify([item.id], title: title, duration: segment.duration, as: kind)
                }
                Button {
                    timeEditing = item
                } label: {
                    Image(systemName: "scissors")
                        .accessibilityLabel("Edit Time")
                }
                .help("Remove unattended time")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)

            Text(HagoDuration.text(segment.duration))
                .font(.body.monospacedDigit())
                .frame(minWidth: 52, alignment: .trailing)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            ruleInspection = ActivityRuleInspection(
                id: id,
                title: title,
                detail: "\(segment.startedAt.formatted(date: .omitted, time: .shortened))–\(segment.endedAt.formatted(date: .omitted, time: .shortened)) · \(HagoDuration.text(segment.duration))",
                sample: item,
                appliedRuleIDs: item.classification.ruleID.map { [$0] } ?? []
            )
        }
        .onHover { hovering in updateHover(id, hovering) }
        .hagoRowBackground(isSelected: false, isHovered: isHovered)
        .help("Click to see why it was classified this way")
    }

    private func rowActions(currentKind: ActivityKind, isVisible: Bool, classify: @escaping (ActivityKind) -> Void) -> some View {
        ClassifyButtons(currentKind: currentKind, classify: classify)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
    }

    private func classify(_ ids: [UUID], title: String, duration: TimeInterval, as kind: ActivityKind) {
        if kind == .ignored {
            pendingIgnore = PendingIgnore(segmentIDs: ids, title: title, duration: duration)
        } else {
            appState.reclassifyActivity(segmentIDs: ids, as: kind)
        }
    }

    private func updateHover(_ id: String, _ hovering: Bool) {
        if hovering {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    private func groupMeta(_ group: AggregatedActivity) -> String {
        var parts: [String] = []
        if group.name != group.appName { parts.append(group.appName) }
        parts.append("\(group.segmentCount) recording\(group.segmentCount == 1 ? "" : "s")")
        let first = group.firstStartedAt.formatted(date: .omitted, time: .shortened)
        let last = group.lastEndedAt.formatted(date: .omitted, time: .shortened)
        parts.append(first == last ? first : "\(first)–\(last)")
        return parts.joined(separator: " · ")
    }

    private func sortedSegments(_ segments: [ClassifiedSegment]) -> [ClassifiedSegment] {
        switch sort {
        case .newest:
            segments.sorted { $0.segment.startedAt > $1.segment.startedAt }
        case .oldest:
            segments.sorted { $0.segment.startedAt < $1.segment.startedAt }
        case .longest:
            segments.sorted { $0.segment.duration > $1.segment.duration }
        case .app:
            segments.sorted {
                $0.segment.appName.localizedCaseInsensitiveCompare($1.segment.appName) == .orderedAscending
            }
        }
    }

    private func sortedGroups(_ groups: [AggregatedActivity]) -> [AggregatedActivity] {
        switch sort {
        case .newest:
            groups.sorted { $0.lastEndedAt > $1.lastEndedAt }
        case .oldest:
            groups.sorted { $0.firstStartedAt < $1.firstStartedAt }
        case .longest:
            groups.sorted { $0.duration > $1.duration }
        case .app:
            groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func categoryName(for item: ClassifiedSegment) -> String {
        guard let categoryName = item.categoryName, !categoryName.isEmpty else {
            return item.classification.kind.displayName
        }

        return categoryName
    }

    private func activityName(for item: ClassifiedSegment) -> String {
        let host = item.segment.snapshot.host
        guard item.segment.source == .chrome, !host.isEmpty else {
            return item.segment.appName
        }

        return host
    }
}

private struct ActivityRuleInspection: Identifiable {
    var id: String
    var title: String
    var detail: String
    var sample: ClassifiedSegment
    var appliedRuleIDs: [UUID]
}

private struct ActivityRuleInspectorView: View {
    @EnvironmentObject private var appState: AppState

    var inspection: ActivityRuleInspection

    @State private var selectedRuleID: UUID?
    @State private var rememberingRule: Rule?

    private let rememberedRuleFactory = RememberedRuleFactory()

    init(inspection: ActivityRuleInspection) {
        self.inspection = inspection
        _selectedRuleID = State(initialValue: inspection.appliedRuleIDs.first)
    }

    private var appliedRules: [Rule] {
        inspection.appliedRuleIDs.compactMap { ruleID in
            appState.rules.first { $0.id == ruleID }
        }
    }

    private var selectedRule: Rule? {
        guard let selectedRuleID else {
            return nil
        }

        return appState.rules.first { $0.id == selectedRuleID }
    }

    private var suggestedRule: Rule? {
        rememberedRuleFactory.rule(
            from: inspection.sample,
            kind: inspection.sample.classification.kind,
            categoryID: inspection.sample.classification.categoryID
        )
    }

    private var rememberOptions: [Rule] {
        [ActivityKind.work, .personal].flatMap { kind in
            rememberedRuleFactory.rules(
                from: inspection.sample,
                kind: kind,
                categoryID: appState.categories.first(where: { $0.kind == kind })?.id
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppIconView(bundleIdentifier: inspection.sample.segment.snapshot.bundleIdentifier, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(inspection.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(inspection.detail)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ActivityKindBadge(kind: inspection.sample.classification.kind)
            }
            .padding([.horizontal, .top], 20)

            VStack(alignment: .leading, spacing: 10) {
                Label(appState.classificationExplanation(for: inspection.sample), systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    if appliedRules.count > 1 {
                        Picker("Applied rule", selection: $selectedRuleID) {
                            ForEach(appliedRules) { rule in
                                Text(rule.name).tag(Optional(rule.id))
                            }
                        }
                        .fixedSize()
                    } else if let rule = appliedRules.first {
                        LabeledContent("Applied rule", value: rule.name)
                    } else {
                        Text(suggestedRule == nil
                             ? "No rule applies to this activity."
                             : "No rule applies yet. Create one below.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !rememberOptions.isEmpty {
                        Menu {
                            ForEach([ActivityKind.work, .personal]) { kind in
                                let options = rememberOptions.filter { $0.action.kind == kind }
                                if !options.isEmpty {
                                    Section("Always \(kind.displayName)") {
                                        ForEach(options) { rule in
                                            Button(rule.name) { rememberingRule = rule }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Always…", systemImage: "wand.and.stars")
                        }
                        .fixedSize()
                    }
                }
            }
            .padding(20)

            Divider()

            if let rule = selectedRule ?? suggestedRule {
                RuleEditorView(
                    rule: rule,
                    projects: appState.projects,
                    categories: appState.categories,
                    allowsDelete: selectedRule != nil,
                    onDelete: { deletedRule, scope in
                        appState.deleteRule(id: deletedRule.id, reclassify: scope)
                    },
                    onSave: { savedRule, scope in
                        appState.saveRule(savedRule, reclassify: scope)
                    }
                )
                .id(rule.id)
            } else {
                ContentUnavailableView(
                    "No Editable Rule",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This browser activity does not contain a URL that can be turned into a safe rule.")
                )
                .frame(width: 600, height: 260)
            }
        }
        .frame(width: 600)
        .frame(maxHeight: 600)
        .sheet(item: $rememberingRule) { rule in
            RememberRulePreviewView(rule: rule).environmentObject(appState)
        }
    }
}

private enum ActivityProjectFilter {
    static let all = "all"
    static let none = "none"
}

private enum ActivityPresentation: String, CaseIterable, Identifiable {
    case grouped
    case individual

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .grouped:
            "By App"
        case .individual:
            "Timeline"
        }
    }
}

private enum ActivitySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case longest
    case app

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .newest:
            "Newest First"
        case .oldest:
            "Oldest First"
        case .longest:
            "Longest First"
        case .app:
            "Name A–Z"
        }
    }
}

private struct DailyTimelineChart: View {
    var day: Date
    var entries: [ClassifiedSegment]

    @State private var selectedSpanID: UUID?
    @State private var tooltipPosition: CGPoint?
    @State private var zoomedInterval: DateInterval?
    @State private var panStartInterval: DateInterval?
    @State private var isPanning = false

    private let formatter = TimeFormatting()
    private let tooltipWidth: CGFloat = 240
    private let barWidth: CGFloat = 120

    private var spans: [ActivityTimelineSpan] {
        ActivityAggregation.timelineSpans(from: entries)
    }

    private var selectedSpan: ActivityTimelineSpan? {
        spans.first { $0.id == selectedSpanID }
    }

    private var dayInterval: DateInterval {
        HagoCalendar.shared.dayInterval(containing: day)
    }

    private var visibleInterval: DateInterval {
        zoomedInterval ?? TimelineViewport.defaultInterval(for: day, calendar: .current)
    }

    var body: some View {
        Chart {
            RectangleMark(
                x: .value("Day", "Today"),
                yStart: .value("Time", visibleInterval.start),
                yEnd: .value("Time", visibleInterval.end),
                width: .fixed(barWidth)
            )
            .foregroundStyle(Color.primary.opacity(0.05))
            .accessibilityHidden(true)

            ForEach(spans) { span in
                RectangleMark(
                    x: .value("Day", "Today"),
                    yStart: .value("Time", span.startedAt),
                    yEnd: .value("Time", span.endedAt),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(by: .value("Type", span.kind.displayName))
                .accessibilityLabel(span.kind.displayName)
                .accessibilityValue("\(span.startedAt.formatted(date: .omitted, time: .shortened)) – \(span.endedAt.formatted(date: .omitted, time: .shortened)), \(formatter.compactDuration(span.endedAt.timeIntervalSince(span.startedAt)))")
            }

            if let selectedSpan {
                RuleMark(y: .value("Selected Block", selectedSpan.endedAt))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartForegroundStyleScale([
            "Work": .blue,
            "Personal": .green,
            ActivityKind.review.displayName: .orange
        ])
        .chartLegend(position: .bottom, spacing: 16)
        .chartXScale(domain: ["Today"])
        .chartXAxis(.hidden)
        .chartYScale(domain: visibleInterval.start...visibleInterval.end)
        .chartPlotStyle { plot in
            plot.clipped()
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: TimelineViewport.axisDates(in: visibleInterval, calendar: .current)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard !isPanning else { return }
                            switch phase {
                            case .active(let location):
                                updateSelection(at: location, proxy: proxy, geometry: geometry)
                            case .ended:
                                clearSelection()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updatePan(value, proxy: proxy, geometry: geometry)
                                }
                                .onEnded { _ in
                                    panStartInterval = nil
                                    isPanning = false
                                }
                        )

                    if let plotFrame = proxy.plotFrame {
                        let plotAreaFrame = geometry[plotFrame]
                        TimelineScrollZoomView { delta, location in
                            guard !isPanning else { return }
                            clearSelection()
                            zoomedInterval = TimelineViewport.zoom(
                                visibleInterval,
                                by: exp(-Double(delta) * 0.01),
                                around: Double(location.y / plotAreaFrame.height),
                                within: dayInterval
                            )
                        }
                        .frame(width: barWidth, height: plotAreaFrame.height)
                        .position(x: plotAreaFrame.midX, y: plotAreaFrame.midY)
                    }

                    if entries.isEmpty {
                        Text("No activity tracked today")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }

                    if let selectedSpan, let tooltipPosition {
                        TimelineBlockTooltip(span: selectedSpan)
                            .frame(width: tooltipWidth)
                            .offset(
                                x: min(max(tooltipPosition.x - tooltipWidth / 2, 0), max(0, geometry.size.width - tooltipWidth)),
                                y: max(0, tooltipPosition.y - 120)
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if zoomedInterval != nil {
                Button("Reset zoom") {
                    zoomedInterval = nil
                    clearSelection()
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
    }

    private func clearSelection() {
        selectedSpanID = nil
        tooltipPosition = nil
    }

    private func updatePan(_ value: DragGesture.Value, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plotAreaFrame = geometry[plotFrame]
        guard plotAreaFrame.height > 0,
              plotAreaFrame.contains(value.startLocation),
              abs(value.startLocation.x - plotAreaFrame.midX) <= barWidth / 2 else {
            clearSelection()
            return
        }

        // Apply the full drag translation to the original range so successive updates do not compound the shift.
        let initialInterval = panStartInterval ?? visibleInterval
        if panStartInterval == nil {
            panStartInterval = initialInterval
        }

        guard isPanning || abs(value.translation.height) >= 3 else {
            updateSelection(at: value.location, proxy: proxy, geometry: geometry)
            return
        }

        isPanning = true
        clearSelection()
        zoomedInterval = TimelineViewport.pan(
            initialInterval,
            by: -Double(value.translation.height / plotAreaFrame.height) * initialInterval.duration,
            within: dayInterval
        )
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            clearSelection()
            return
        }

        let plotAreaFrame = geometry[plotFrame]
        guard plotAreaFrame.contains(location),
              abs(location.x - plotAreaFrame.midX) <= barWidth / 2,
              let time = proxy.value(atY: location.y - plotAreaFrame.minY, as: Date.self),
              let span = spans.first(where: { $0.startedAt <= time && time < $0.endedAt }) else {
            clearSelection()
            return
        }

        selectedSpanID = span.id
        tooltipPosition = location
    }
}

private struct TimelineBlockTooltip: View {
    var span: ActivityTimelineSpan

    private let formatter = TimeFormatting()

    private var duration: TimeInterval {
        span.endedAt.timeIntervalSince(span.startedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(span.kind.displayName) block")
                .font(.caption.weight(.semibold))
            Divider()
            Text("\(span.startedAt.formatted(date: .omitted, time: .standard)) – \(span.endedAt.formatted(date: .omitted, time: .standard))")
                .monospacedDigit()
            Text(duration < 60
                 ? "\(Int(duration))s"
                 : formatter.compactDuration(duration))
                .monospacedDigit()
        }
        .font(.caption)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }
}

struct BucketListView: View {
    var buckets: [TimeBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if buckets.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(buckets) { bucket in
                HStack {
                    Text(bucket.name)
                        .lineLimit(1)
                    Spacer()
                    Text(TimeFormatting().compactDuration(bucket.seconds))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MetricView: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SectionPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
