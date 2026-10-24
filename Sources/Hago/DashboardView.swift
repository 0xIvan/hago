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
                .padding([.review, .rules, .tracking, .privacy].contains(appState.selectedSection) ? 0 : 20)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !appState.accessibilityTrusted {
                    AccessibilityAccessPanel()
                }

                HStack(spacing: 12) {
                    MetricView(title: "Work", value: formatter.compactDuration(appState.todaySummary.workSeconds), color: .blue)
                    MetricView(title: "Personal", value: formatter.compactDuration(appState.todaySummary.personalSeconds), color: .green)
                    MetricView(title: ActivityKind.review.displayName, value: formatter.compactDuration(appState.todaySummary.reviewSeconds), color: .orange)
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
                                        .foregroundStyle(kind == .work ? .blue : .green)
                                    BucketListView(buckets: appState.todaySummary.topApps.filter { $0.kind == kind })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private enum ReviewSort: String, CaseIterable, Identifiable {
    case recent
    case longest

    var id: Self { self }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .longest: "Longest"
        }
    }
}

private struct ReviewTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var inspectingRun: ReviewAIRunSummary?
    @State private var rememberingRule: Rule?
    @State private var selectedGroupID: String?
    @State private var sort = ReviewSort.recent
    @State private var showsAllSuggestions = false
    @FocusState private var listHasKeyboardFocus: Bool
    private let formatter = TimeFormatting()

    private var groups: [AggregatedActivity] {
        let groups = appState.reviewGroups
        switch sort {
        case .recent:
            return groups
        case .longest:
            return groups.sorted { $0.duration > $1.duration }
        }
    }

    var body: some View {
        let groups = groups
        VStack(spacing: 0) {
            header(groups)
            Divider()
            List(selection: selection(in: groups)) {
                correctionBanner
                LearningSuggestionsSection()
                reviewAISuggestionsSection
                reviewItemsSection(groups)
            }
            .listStyle(.inset)
            .focused($listHasKeyboardFocus)
            .onAppear { listHasKeyboardFocus = true }
            .onKeyPress(characters: CharacterSet(charactersIn: "wWpPiI")) { press in
                guard press.modifiers.intersection([.command, .control, .option]).isEmpty,
                      let id = selection(in: groups).wrappedValue,
                      let group = groups.first(where: { $0.id == id }) else { return .ignored }
                let key = press.characters.lowercased()
                classify(group, as: key == "w" ? .work : key == "p" ? .personal : .ignored, in: groups)
                return .handled
            }
        }
        .sheet(item: $rememberingRule) { rule in
            RememberRulePreviewView(rule: rule).environmentObject(appState)
        }
        .sheet(item: $inspectingRun) { run in
            AppliedReviewRulesView(run: run)
                .environmentObject(appState)
        }
    }

    private func selection(in groups: [AggregatedActivity]) -> Binding<String?> {
        Binding(
            get: {
                if let selectedGroupID, groups.contains(where: { $0.id == selectedGroupID }) {
                    return selectedGroupID
                }
                return groups.first?.id
            },
            set: { selectedGroupID = $0 }
        )
    }

    private func classify(_ group: AggregatedActivity, as kind: ActivityKind, in groups: [AggregatedActivity]) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            let remaining = groups.filter { $0.id != group.id }
            selectedGroupID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
        appState.classifyReviewGroup(group, as: kind)
    }

    private func header(_ groups: [AggregatedActivity]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(groups.isEmpty ? "All caught up" : "\(groups.count) to review")
                    .font(.title2.weight(.semibold))
                Text(groups.isEmpty
                     ? "New activity Hago can't classify will show up here."
                     : "\(formatter.compactDuration(groups.reduce(0) { $0 + $1.duration })) unclassified across \(appState.reviewSegments.count) recordings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !groups.isEmpty {
                Picker("Sort", selection: $sort) {
                    ForEach(ReviewSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            aiButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
    private var correctionBanner: some View {
        if let message = appState.correctionMessage {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if appState.latestCorrectionActionID != nil {
                    Button("Undo") { appState.undoLatestCorrection() }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
            .selectionDisabled()
        }
    }

    private let collapsedSuggestionCount = 3

    private var visibleSuggestions: [ReviewAISuggestion] {
        let sorted = appState.reviewAISuggestions.sorted { $0.affectedDuration > $1.affectedDuration }
        return showsAllSuggestions ? sorted : Array(sorted.prefix(collapsedSuggestionCount))
    }

    private var showsAISection: Bool {
        appState.reviewAIAnalysisState != .idle
            || !appState.reviewAISuggestions.isEmpty
            || appState.lastReviewAIUndoMessage != nil
            || (appState.lastReviewAIRunSummary?.automaticallyAppliedCount ?? 0) > 0
    }

    @ViewBuilder
    private var reviewAISuggestionsSection: some View {
        if showsAISection {
            Section("AI suggestions") {
                if let run = appState.lastReviewAIRunSummary,
                   run.automaticallyAppliedCount > 0 {
                    HStack {
                        Text("Applied \(run.automaticallyAppliedCount) high-confidence rule\(run.automaticallyAppliedCount == 1 ? "" : "s") with \(run.harness.displayName).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("View Applied") {
                            inspectingRun = run
                        }
                        if run.status == .completed {
                            Button("Undo") {
                                appState.undoLastReviewAIRun()
                            }
                        } else {
                            Text(run.status == .undone ? "Undone" : "Partially undone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .controlSize(.small)
                    .selectionDisabled()
                }

                if let message = appState.lastReviewAIUndoMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }

                switch appState.reviewAIAnalysisState {
                case .idle:
                    EmptyView()
                case .analyzing:
                    Label("Analyzing activity that needs review…", systemImage: "hourglass")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                case .completed:
                    if appState.reviewAISuggestions.isEmpty {
                        Text("No suggestions this time. Classify the items below by hand.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .selectionDisabled()
                }

                ForEach(visibleSuggestions) { suggestion in
                    ReviewAISuggestionRow(
                        suggestion: suggestion,
                        formattedDuration: formatter.compactDuration(suggestion.affectedDuration)
                    ) { kind in
                        appState.applyReviewAISuggestion(suggestion, as: kind)
                    }
                    .selectionDisabled()
                }

                if appState.reviewAISuggestions.count > collapsedSuggestionCount {
                    Button(showsAllSuggestions
                           ? "Show Fewer"
                           : "Show All \(appState.reviewAISuggestions.count) Suggestions") {
                        showsAllSuggestions.toggle()
                    }
                    .buttonStyle(.link)
                    .selectionDisabled()
                }
            }
        }
    }

    private func reviewItemsSection(_ groups: [AggregatedActivity]) -> some View {
        Section {
            if groups.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("Activity that needs a decision will appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .selectionDisabled()
            }

            ForEach(groups) { group in
                if let item = appState.reviewSegments.first(where: { group.segmentIDs.contains($0.id) }) {
                    ReviewGroupRow(
                        group: group,
                        item: item,
                        explanation: appState.classificationExplanation(for: item),
                        recordingSummary: recordingSummary(for: group),
                        duration: formatter.compactDuration(group.duration),
                        rememberOptions: rememberOptions(for: item),
                        classify: { kind in classify(group, as: kind, in: groups) },
                        remember: { rememberingRule = $0 }
                    )
                    .tag(group.id)
                }
            }
        } header: {
            if !groups.isEmpty {
                HStack {
                    Text("Needs a decision")
                    Spacer()
                    Text("↑ ↓ to move · W Work · P Personal · I Ignore")
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

private struct ReviewGroupRow: View {
    let group: AggregatedActivity
    let item: ClassifiedSegment
    let explanation: String
    let recordingSummary: String
    let duration: String
    let rememberOptions: [Rule]
    let classify: (ActivityKind) -> Void
    let remember: (Rule) -> Void

    private var segment: ActivitySegment { item.segment }

    private var title: String {
        if !segment.snapshot.host.isEmpty { return segment.snapshot.host }
        return segment.windowTitle.isEmpty ? segment.appName : segment.windowTitle
    }

    private var subtitle: String {
        let detail = segment.windowTitle.isEmpty ? "Window title unavailable" : segment.windowTitle
        return title == segment.windowTitle ? segment.appName : "\(segment.appName) · \(detail)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconView(bundleIdentifier: segment.snapshot.bundleIdentifier)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(duration)
                        .font(.headline.monospacedDigit())
                }

                Text(subtitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)

                if let url = segment.url {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text("\(recordingSummary) · \(explanation)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if segment.snapshot.isDiscordWithoutTitle {
                    Text("Channel titles were not captured. Your choice applies only to these recordings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Button {
                        classify(.work)
                    } label: {
                        Label("Work", systemImage: "briefcase")
                    }
                    .help("Mark these recordings as Work (W)")

                    Button {
                        classify(.personal)
                    } label: {
                        Label("Personal", systemImage: "person")
                    }
                    .help("Mark these recordings as Personal (P)")

                    Button(role: .destructive) {
                        classify(.ignored)
                    } label: {
                        Label("Ignore", systemImage: "eye.slash")
                    }
                    .help("Delete these recordings so they never count (I)")

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
                            Label("Always…", systemImage: "wand.and.stars")
                        }
                        .fixedSize()
                        .help("Create a rule so matching activity is classified automatically, including past recordings")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }

    private func optionTitle(_ rule: Rule) -> String {
        let name = rule.name.hasPrefix("Remember ") ? String(rule.name.dropFirst("Remember ".count)) : rule.name
        return name.prefix(1).uppercased() + name.dropFirst()
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

private struct ReviewAISuggestionRow: View {
    let suggestion: ReviewAISuggestion
    let formattedDuration: String
    let apply: (ReviewAISuggestionKind) -> Void

    private let validator = ReviewAISuggestionValidator()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(suggestionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Spacer(minLength: 8)
                Text("\(suggestion.affectedCount) item\(suggestion.affectedCount == 1 ? "" : "s") · \(formattedDuration) · \(Int(round(suggestion.confidence * 100)))% sure")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(suggestion.reason)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(detail)

            HStack(spacing: 6) {
                choiceButton(.work, title: "Work", symbol: "briefcase")
                choiceButton(.personal, title: "Personal", symbol: "person")
                choiceButton(.ignored, title: "Ignore", symbol: "eye.slash")

                if let message = validationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func choiceButton(_ kind: ReviewAISuggestionKind, title: String, symbol: String) -> some View {
        let isSuggested = kind == suggestion.kind && canApply(kind)
        let button = Button(role: kind == .ignored ? .destructive : nil) {
            apply(kind)
        } label: {
            Label(isSuggested ? "Accept \(title)" : title, systemImage: symbol)
        }
        .disabled(!canApply(kind))

        if isSuggested {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var title: String {
        if let condition = suggestion.proposedRuleCondition {
            return condition.value
        }
        guard let sample = suggestion.samples.first else { return "Activity" }
        return sample.windowTitle.isEmpty ? sample.appName : sample.windowTitle
    }

    private var detail: String {
        var lines = [suggestion.reason]
        if let condition = suggestion.proposedRuleCondition {
            lines.append("Rule: \(condition.field.displayName) \(condition.operation.displayName) \(condition.value)")
        }
        if let sample = suggestion.samples.first {
            lines.append("Example: \(sample.windowTitle.isEmpty ? sample.appName : sample.windowTitle)")
        }
        return lines.joined(separator: "\n")
    }

    private func canApply(_ kind: ReviewAISuggestionKind) -> Bool {
        validation(for: kind).canApply
    }

    private func validation(for kind: ReviewAISuggestionKind) -> ReviewAISuggestionValidationResult {
        var correctedSuggestion = suggestion
        correctedSuggestion.kind = kind
        return validator.validationResult(for: correctedSuggestion)
    }

    private var validationMessage: String? {
        if suggestion.kind == .ignored {
            return "Ignored suggestions are never applied automatically."
        }

        if suggestion.kind == .unsure {
            return "Choose Work or Personal to apply."
        }

        let workValidation = validation(for: .work)
        let personalValidation = validation(for: .personal)
        guard !workValidation.canApply, !personalValidation.canApply else {
            return nil
        }

        if let message = validationMessage(for: workValidation) {
            return message
        }

        return validationMessage(for: personalValidation)
    }

    private func validationMessage(for validation: ReviewAISuggestionValidationResult) -> String? {
        switch validation {
        case .applyAllowed:
            nil
        case .manualOnly(let message), .rejected(let message):
            message
        }
    }

    private var symbolName: String {
        switch suggestion.kind {
        case .work:
            "briefcase"
        case .personal:
            "person"
        case .ignored:
            "eye.slash"
        case .unsure:
            "questionmark.circle"
        }
    }

    private var suggestionTitle: String {
        switch suggestion.kind {
        case .work:
            "Work?"
        case .personal:
            "Personal?"
        case .ignored:
            "Ignore?"
        case .unsure:
            "Unsure"
        }
    }

    private var color: Color {
        switch suggestion.kind {
        case .work:
            .blue
        case .personal:
            .green
        case .ignored:
            .gray
        case .unsure:
            .orange
        }
    }
}

private struct RecentActivityTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var kindFilter = ActivityKindFilter.all
    @State private var projectFilterID = ActivityProjectFilter.all
    @State private var sort = ActivitySort.newest
    @State private var presentation = ActivityPresentation.grouped
    @State private var ruleInspection: ActivityRuleInspection?
    @State private var timeEditing: ClassifiedSegment?

    private let formatter = TimeFormatting()

    private var displayedSegments: [ClassifiedSegment] {
        sortedSegments(filteredSegments(appState.activitySegments))
    }

    private var displayedGroups: [AggregatedActivity] {
        sortedGroups(ActivityAggregation.groups(from: filteredSegments(appState.activitySegments)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            activityControls

            List {
                if presentation == .grouped, displayedGroups.isEmpty {
                    Text(emptyActivityMessage)
                        .foregroundStyle(.secondary)
                } else if presentation == .individual, displayedSegments.isEmpty {
                    Text(emptyActivityMessage)
                        .foregroundStyle(.secondary)
                }

                if presentation == .grouped {
                    ForEach(displayedGroups) { group in
                        aggregatedActivityRow(group)
                    }
                } else {
                    ForEach(displayedSegments) { item in
                        individualActivityRow(item)
                    }
                }
            }
        }
        .sheet(item: $ruleInspection) { inspection in
            ActivityRuleInspectorView(inspection: inspection)
                .environmentObject(appState)
        }
        .sheet(item: $timeEditing) { item in
            ActivityTimeEditor(item: item).environmentObject(appState)
        }
        .onAppear {
            appState.selectActivityDate(HagoCalendar.shared.dayInterval(containing: Date()).start)
        }
    }

    private func aggregatedActivityRow(_ group: AggregatedActivity) -> some View {
        Button {
            guard let sample = appState.activitySegments.first(where: { group.segmentIDs.contains($0.id) }) else {
                return
            }

            ruleInspection = ActivityRuleInspection(
                id: group.id,
                title: group.name,
                detail: "\(group.segmentCount) entries · \(formatter.compactDuration(group.duration))",
                sample: sample,
                appliedRuleIDs: group.appliedRuleIDs
            )
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(color(for: group.kind))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(group.name)
                            .font(.headline)
                        if group.name != group.appName {
                            Text(group.appName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let projectName = group.projectName {
                            Text(projectName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(group.segmentCount) entries · \(group.categoryName ?? group.kind.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formatter.compactDuration(group.duration))
                    .font(.subheadline.monospacedDigit())

                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Inspect applied rule")
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func individualActivityRow(_ item: ClassifiedSegment) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color(for: item.classification.kind))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.segment.appName)
                        .font(.headline)
                    if let projectName = item.projectName {
                        Text(projectName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.segment.windowTitle.isEmpty ? item.classification.kind.displayName : item.segment.windowTitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatter.compactDuration(item.segment.duration))
                .font(.subheadline.monospacedDigit())

            Button {
                timeEditing = item
            } label: {
                Label("Edit Time", systemImage: "clock")
            }
            .labelStyle(.iconOnly)
            .help("Remove unattended time")

            Button {
                ruleInspection = ActivityRuleInspection(
                    id: item.id.uuidString,
                    title: activityName(for: item),
                    detail: item.segment.startedAt.formatted(.dateTime.hour().minute()),
                    sample: item,
                    appliedRuleIDs: item.classification.ruleID.map { [$0] } ?? []
                )
            } label: {
                Label("Inspect Rule", systemImage: "slider.horizontal.3")
            }
            .labelStyle(.iconOnly)
            .help("Inspect applied rule")

            Menu {
                Button {
                    appState.updateSegmentClassification(item, as: .work)
                } label: {
                    Label("Work", systemImage: symbol(for: .work))
                }

                Button {
                    appState.updateSegmentClassification(item, as: .personal)
                } label: {
                    Label("Personal", systemImage: symbol(for: .personal))
                }

                Button(role: .destructive) {
                    appState.updateSegmentClassification(item, as: .ignored)
                } label: {
                    Label("Ignore", systemImage: symbol(for: .ignored))
                }
            } label: {
                Label(categoryName(for: item), systemImage: symbol(for: item.classification.kind))
                    .lineLimit(1)
            }
            .menuStyle(.button)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var emptyActivityMessage: String {
        appState.activitySegments.isEmpty ? "No activity for this day" : "No matching activity"
    }

    private var activityControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            WrappingHStack(horizontalSpacing: 12, verticalSpacing: 8) {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { appState.activityDate },
                        set: { appState.selectActivityDate($0) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .fixedSize()

                TextField("Search activity", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Picker("View", selection: $presentation) {
                    ForEach(ActivityPresentation.allCases) { presentation in
                        Text(presentation.title).tag(presentation)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            WrappingHStack(horizontalSpacing: 12, verticalSpacing: 8) {
                Picker("Category", selection: $kindFilter) {
                    ForEach(ActivityKindFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 170)

                Picker("Project", selection: $projectFilterID) {
                    Text("All Projects").tag(ActivityProjectFilter.all)
                    Text("No Project").tag(ActivityProjectFilter.none)
                    ForEach(appState.projects) { project in
                        Text(project.name).tag(project.id.uuidString)
                    }
                }
                .frame(width: 190)

                Picker("Sort", selection: $sort) {
                    ForEach(ActivitySort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .frame(width: 180)
            }
        }
    }

    private func filteredSegments(_ segments: [ClassifiedSegment]) -> [ClassifiedSegment] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return segments.filter { item in
            if let kind = kindFilter.kind, item.classification.kind != kind {
                return false
            }

            if projectFilterID == ActivityProjectFilter.none, item.classification.projectID != nil {
                return false
            }

            if projectFilterID != ActivityProjectFilter.all, projectFilterID != ActivityProjectFilter.none {
                guard item.classification.projectID?.uuidString == projectFilterID else {
                    return false
                }
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

    private func sortedSegments(_ segments: [ClassifiedSegment]) -> [ClassifiedSegment] {
        switch sort {
        case .newest:
            segments.sorted { $0.segment.startedAt > $1.segment.startedAt }
        case .oldest:
            segments.sorted { $0.segment.startedAt < $1.segment.startedAt }
        case .longest:
            segments.sorted { $0.segment.duration > $1.segment.duration }
        case .shortest:
            segments.sorted { $0.segment.duration < $1.segment.duration }
        case .app:
            segments.sorted {
                $0.segment.appName.localizedCaseInsensitiveCompare($1.segment.appName) == .orderedAscending
            }
        case .category:
            segments.sorted {
                categoryName(for: $0).localizedCaseInsensitiveCompare(categoryName(for: $1)) == .orderedAscending
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
        case .shortest:
            groups.sorted { $0.duration < $1.duration }
        case .app:
            groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .category:
            groups.sorted {
                ($0.categoryName ?? $0.kind.displayName)
                    .localizedCaseInsensitiveCompare($1.categoryName ?? $1.kind.displayName) == .orderedAscending
            }
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

    private func symbol(for kind: ActivityKind) -> String {
        switch kind {
        case .work:
            "briefcase"
        case .personal:
            "person"
        case .review:
            "questionmark.circle"
        case .ignored:
            "eye.slash"
        }
    }

    private func color(for kind: ActivityKind) -> Color {
        switch kind {
        case .work:
            .blue
        case .personal:
            .green
        case .review:
            .orange
        case .ignored:
            .gray
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(inspection.title)
                    .font(.title2.weight(.semibold))
                Text(inspection.detail)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)

            Text(appState.classificationExplanation(for: inspection.sample))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            Menu("Remember a Scope…") {
                ForEach(rememberedRuleFactory.rules(from: inspection.sample, kind: inspection.sample.classification.kind, categoryID: inspection.sample.classification.categoryID)) { rule in
                    Button(rule.name) { rememberingRule = rule }
                }
            }.padding(.horizontal)

            if appliedRules.count > 1 {
                Picker("Applied Rule", selection: $selectedRuleID) {
                    ForEach(appliedRules) { rule in
                        Text(rule.name).tag(Optional(rule.id))
                    }
                }
                .padding(.horizontal)
            } else if let rule = appliedRules.first {
                LabeledContent("Applied Rule", value: rule.name)
                    .padding(.horizontal)
            } else {
                Label(
                    suggestedRule == nil
                        ? "No rule is applied to this activity."
                        : "No rule is applied. Create one from this activity.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }

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
                .frame(width: 520, height: 260)
            }
        }
        .sheet(item: $rememberingRule) { rule in
            RememberRulePreviewView(rule: rule).environmentObject(appState)
        }
    }
}

private enum ActivityKindFilter: String, CaseIterable, Identifiable {
    case all
    case work
    case personal
    case review

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "All Categories"
        case .work:
            "Work"
        case .personal:
            "Personal"
        case .review:
            "Needs review"
        }
    }

    var kind: ActivityKind? {
        switch self {
        case .all:
            nil
        case .work:
            .work
        case .personal:
            .personal
        case .review:
            .review
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
            "Grouped"
        case .individual:
            "Individual"
        }
    }
}

private enum ActivitySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case longest
    case shortest
    case app
    case category

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
        case .shortest:
            "Shortest First"
        case .app:
            "App A-Z"
        case .category:
            "Category A-Z"
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
