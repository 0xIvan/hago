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
                        SidebarSectionLabel(section: section, reviewCount: appState.reviewSubjectCount)
                            .tag(section)
                    }
                }
                Section("Settings") {
                    ForEach(HagoSection.settingsSections) { section in
                        SidebarSectionLabel(section: section, reviewCount: appState.reviewSubjectCount)
                            .tag(section)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                SidebarTodayFooter()
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

private struct SidebarTodayFooter: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            DayRing(
                day: HagoCalendar.shared.dayInterval(containing: appState.todaySummary.date),
                spans: ActivityAggregation.timelineSpans(from: appState.todayTimeline),
                now: Date(),
                lineWidth: 4
            )
            .frame(width: 30, height: 30)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 1) {
                Text(appState.isTrackingPaused ? "Paused" : "Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(TimeFormatting().compactDuration(appState.todayTrackedSeconds))
                    .font(.hagoNumber(14))
            }

            Spacer(minLength: 4)

            Button {
                appState.toggleTracking()
            } label: {
                Image(systemName: appState.isTrackingPaused ? "play.fill" : "pause.fill")
                    .font(.caption)
                    .frame(width: 24, height: 24)
                    .background(HagoPalette.track, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(appState.isTrackingPaused ? "Resume tracking" : "Pause tracking")
            .accessibilityLabel(appState.isTrackingPaused ? "Resume tracking" : "Pause tracking")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { appState.selectedSection = .overview }
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
    @State private var week: ReportSummary?

    private let formatter = TimeFormatting()

    private var summary: DaySummary { appState.todaySummary }

    private var day: DateInterval {
        HagoCalendar.shared.dayInterval(containing: summary.date)
    }

    private var spans: [ActivityTimelineSpan] {
        ActivityAggregation.timelineSpans(from: appState.todayTimeline)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageTop {
                PageHeader(
                    title: "Today",
                    subtitle: summary.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
                ) {
                    if appState.reviewSubjectCount > 0 {
                        Button {
                            appState.selectedSection = .review
                        } label: {
                            Label("Review \(appState.reviewSubjectCount)", systemImage: HagoSection.review.symbolName)
                        }
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !appState.accessibilityTrusted {
                        AccessibilityAccessPanel()
                    }
                    hero
                    HStack(alignment: .top, spacing: 16) {
                        TopItemsCard(kind: .work, summary: summary, timeline: appState.todayTimeline)
                        TopItemsCard(kind: .personal, summary: summary, timeline: appState.todayTimeline)
                    }
                    if let week {
                        WeekCard(week: week) { appState.selectedSection = .reports }
                    }
                }
                .padding(20)
            }
        }
        .task(id: "\(summary.date.timeIntervalSince1970)-\(Int(appState.todayTrackedSeconds / 300))") {
            week = appState.loadReportPair(for: .week, containing: Date())?.current
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 32) {
            DayRing(day: day, spans: spans, now: Date(), lineWidth: 18, showsHours: true) { arc in
                if let arc {
                    ArcSummary(arc: arc, timeline: appState.todayTimeline)
                } else {
                    VStack(spacing: 2) {
                        Text(formatter.compactDuration(appState.todayTrackedSeconds))
                            .font(.hagoNumber(32))
                        Text("tracked today")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 260, height: 260)

            VStack(alignment: .leading, spacing: 22) {
                NowCard()
                VStack(spacing: 16) {
                    KindTotalRow(kind: .work, seconds: summary.workSeconds, total: appState.todayTrackedSeconds)
                    KindTotalRow(kind: .personal, seconds: summary.personalSeconds, total: appState.todayTrackedSeconds)
                    if summary.reviewSeconds > 0 {
                        KindTotalRow(kind: .review, seconds: summary.reviewSeconds, total: appState.todayTrackedSeconds) {
                            appState.selectedSection = .review
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .hagoCard(padding: 24)
    }
}

/// What the hovered block on the day ring was mostly spent on.
private struct ArcSummary: View {
    let arc: RingArc
    let timeline: [ClassifiedSegment]

    private var mainName: String? {
        var durations: [String: TimeInterval] = [:]
        for entry in timeline where entry.classification.kind == arc.kind
            && entry.segment.endedAt > arc.startedAt && entry.segment.startedAt < arc.endedAt {
            let snapshot = entry.segment.snapshot
            durations[snapshot.host.isEmpty ? snapshot.appName : snapshot.host, default: 0] += entry.segment.duration
        }
        return durations.max { $0.value < $1.value }?.key
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(arc.kind.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(arc.kind.tint)
            if let mainName {
                Text(mainName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(HagoDuration.text(arc.trackedSeconds))
                .font(.hagoNumber(22))
            Text("\(arc.startedAt.formatted(date: .omitted, time: .shortened)) – \(arc.endedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}

private struct NowCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            if appState.isTrackingPaused {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking paused")
                        .font(.headline)
                    Text("Nothing is being recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Resume") { appState.toggleTracking() }
            } else if appState.isAway {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Away")
                        .font(.headline)
                    Text("Time away isn't counted. Hago picks up when you're back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else if let snapshot = appState.currentSnapshot {
                AppIconView(bundleIdentifier: snapshot.bundleIdentifier, host: snapshot.host, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(kind?.tint ?? .secondary)
                            .symbolEffect(.pulse)
                        Text("Now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let kind {
                            Text("· \(kind.displayName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(kind.tint)
                        }
                    }
                    Text(snapshot.host.isEmpty ? snapshot.appName : snapshot.host)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            } else {
                Image(systemName: "hourglass")
                    .foregroundStyle(.secondary)
                Text("Waiting for your first activity")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(HagoPalette.track.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var kind: ActivityKind? {
        appState.currentClassification?.kind == .ignored ? nil : appState.currentClassification?.kind
    }
}

private struct KindTotalRow: View {
    let kind: ActivityKind
    let seconds: TimeInterval
    let total: TimeInterval
    var review: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(kind == .review ? "Not filed yet" : kind.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let review {
                    Button("Review", action: review)
                        .buttonStyle(.link)
                        .font(.callout)
                }
                Spacer()
                Text(TimeFormatting().compactDuration(seconds))
                    .font(.hagoNumber(24))
                    .foregroundStyle(kind.tint)
            }
            ShareBar(fraction: total > 0 ? seconds / total : 0, color: kind.tint, height: 6)
        }
    }
}

private struct TopItemsCard: View {
    let kind: ActivityKind
    let summary: DaySummary
    let timeline: [ClassifiedSegment]

    private var buckets: [TimeBucket] {
        Array(summary.topApps.filter { $0.kind == kind }.prefix(6))
    }

    /// Top-app buckets are named by site or app; recover what to draw an icon from.
    private var iconSources: [String: (bundleIdentifier: String, host: String?)] {
        var sources: [String: (bundleIdentifier: String, host: String?)] = [:]
        for entry in timeline where entry.classification.kind == kind {
            let snapshot = entry.segment.snapshot
            sources[snapshot.appName] = sources[snapshot.appName] ?? (snapshot.bundleIdentifier, nil)
            if !snapshot.host.isEmpty {
                sources[snapshot.host] = sources[snapshot.host] ?? (snapshot.bundleIdentifier, snapshot.host)
            }
        }
        return sources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind == .work ? "Work went to" : "Personal went to")
                    .font(.headline)
                Spacer()
            }

            if buckets.isEmpty {
                Text("Nothing yet today")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let sources = iconSources
                let longest = buckets.first?.seconds ?? 1
                ForEach(buckets) { bucket in
                    let source = sources[bucket.name]
                    HStack(spacing: 10) {
                        AppIconView(
                            bundleIdentifier: source?.bundleIdentifier ?? "",
                            host: source?.host ?? (bucket.name.contains(".") ? bucket.name : nil),
                            size: 26
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(bucket.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text(HagoDuration.text(bucket.seconds))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ShareBar(fraction: bucket.seconds / max(longest, 1), color: kind.tint, height: 4)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .hagoCard()
    }
}

private struct WeekCard: View {
    let week: ReportSummary
    let openReports: () -> Void

    private let formatter = TimeFormatting()

    private var scale: TimeInterval {
        max(4 * 3_600, week.buckets.map(\.total).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("This Week")
                    .font(.headline)
                Text("\(formatter.compactDuration(week.totalSeconds)) tracked · \(formatter.compactDuration(week.workSeconds)) work")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reports", action: openReports)
                    .buttonStyle(.link)
            }

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(week.buckets) { bucket in
                    WeekDayColumn(bucket: bucket, scale: scale)
                }
            }
        }
        .hagoCard()
    }
}

private struct WeekDayColumn: View {
    let bucket: ReportBucket
    let scale: TimeInterval

    private var isToday: Bool {
        let now = Date()
        return bucket.startDate <= now && now < bucket.endDate
    }

    var body: some View {
        VStack(spacing: 7) {
            Text(bucket.total > 0 ? HagoDuration.text(bucket.total) : " ")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    segment(bucket.reviewSeconds, .review, height: geometry.size.height)
                    segment(bucket.personalSeconds, .personal, height: geometry.size.height)
                    segment(bucket.workSeconds, .work, height: geometry.size.height)
                }
                .frame(maxWidth: .infinity)
                .background(HagoPalette.track)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(maxWidth: 40)
            .frame(height: 96)
            Text(bucket.startDate.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? AnyShapeStyle(HagoPalette.work) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .help(bucket.startDate.formatted(.dateTime.weekday(.wide).day().month()))
    }

    private func segment(_ seconds: TimeInterval, _ kind: ActivityKind, height: CGFloat) -> some View {
        Rectangle()
            .fill(kind.tint.gradient)
            .frame(height: height * min(seconds / scale, 1))
    }
}

private extension ReportBucket {
    var total: TimeInterval { workSeconds + personalSeconds + reviewSeconds }
}

private struct ReviewEntry: Identifiable {
    let group: AggregatedActivity
    let item: ClassifiedSegment
    let suggestion: ReviewAISuggestion?
    /// False when AI never sees this activity, such as Discord without channel titles.
    let isAIEligible: Bool

    var id: String { group.id }
}

private enum ReviewAIState {
    case pick(ReviewAISuggestion)
    case needsYou
    case unchecked
}

/// A selectable Review row: a whole website or app, or one of its pages when expanded.
private struct PendingReviewIgnore {
    let row: ReviewRow
    let rows: [ReviewRow]
}

private struct ReviewRow: Identifiable {
    let id: String
    let subjectID: String
    let entries: [ReviewEntry]
    let isPage: Bool

    var item: ClassifiedSegment { entries[0].item }
    var segmentIDs: [UUID] { entries.flatMap(\.group.segmentIDs) }
    var segmentCount: Int { entries.reduce(0) { $0 + $1.group.segmentCount } }
    var duration: TimeInterval { entries.reduce(0) { $0 + $1.group.duration } }
    var firstStartedAt: Date { entries.map(\.group.firstStartedAt).min() ?? .distantPast }
    var lastEndedAt: Date { entries.map(\.group.lastEndedAt).max() ?? .distantPast }
    var isGroup: Bool { entries.count > 1 }

    var suggestion: ReviewAISuggestion? {
        guard let first = entries[0].suggestion,
              entries.allSatisfy({ $0.suggestion?.id == first.id }) else { return nil }
        return first
    }

    var aiState: ReviewAIState {
        if let suggestion, ReviewSuggestionChoice.canAccept(suggestion) { return .pick(suggestion) }
        if entries.contains(where: { $0.isAIEligible && $0.suggestion == nil }) { return .unchecked }
        return .needsYou
    }

    var pick: ReviewAISuggestion? {
        if case .pick(let suggestion) = aiState { return suggestion }
        return nil
    }

    var isUnchecked: Bool {
        if case .unchecked = aiState { return true }
        return false
    }
}

private struct ReviewSectionRows: Identifiable {
    let id: String
    let title: String
    let subjects: [ReviewRow]
}

private struct ReviewTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var inspectingRun: ReviewAIRunSummary?
    @State private var rememberingRule: Rule?
    @State private var selectedRowID: String?
    @State private var hoveredRowID: String?
    @State private var expandedSubjectIDs: Set<String> = []
    @State private var confirmsBulkAccept = false
    @State private var pendingIgnore: PendingReviewIgnore?
    @FocusState private var listHasKeyboardFocus: Bool

    private var aiEnabled: Bool {
        appState.reviewAIIsReady
    }

    private var subjects: [ReviewRow] {
        let suggestionsByID = Dictionary(
            appState.reviewAISuggestions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let segmentsByID = Dictionary(
            appState.reviewSegments.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let entries = appState.reviewGroups.compactMap { group -> ReviewEntry? in
            guard let item = group.segmentIDs.lazy.compactMap({ segmentsByID[$0] }).first else {
                return nil
            }
            let aiGroupID = item.classification.isManual || item.segment.snapshot.isPrivate
                ? nil
                : ReviewAISuggestionRequest(reviewSegments: [item]).groups.first?.id
            return ReviewEntry(
                group: group,
                item: item,
                suggestion: aiGroupID.flatMap { suggestionsByID[$0] },
                isAIEligible: aiGroupID != nil
            )
        }

        var order: [String] = []
        var entriesBySubject: [String: [ReviewEntry]] = [:]
        for entry in entries {
            let key = ActivityAggregation.reviewSubjectKey(for: entry.item.segment.snapshot)
            if entriesBySubject[key] == nil { order.append(key) }
            entriesBySubject[key, default: []].append(entry)
        }
        return order.map { key in
            ReviewRow(
                id: key,
                subjectID: key,
                entries: (entriesBySubject[key] ?? []).sorted { $0.group.duration > $1.group.duration },
                isPage: false
            )
        }
        .sorted { $0.duration > $1.duration }
    }

    private func sections(for subjects: [ReviewRow]) -> [ReviewSectionRows] {
        guard aiEnabled else {
            return [ReviewSectionRows(id: "needsYou", title: "Needs your call", subjects: subjects)]
        }
        var picks: [ReviewRow] = [], needsYou: [ReviewRow] = [], unchecked: [ReviewRow] = []
        for subject in subjects {
            switch subject.aiState {
            case .pick: picks.append(subject)
            case .needsYou: needsYou.append(subject)
            case .unchecked: unchecked.append(subject)
            }
        }
        return [
            ReviewSectionRows(id: "picks", title: "AI has a pick", subjects: picks),
            ReviewSectionRows(id: "needsYou", title: "AI left these to you", subjects: needsYou),
            ReviewSectionRows(id: "unchecked", title: "Not checked by AI yet", subjects: unchecked)
        ]
        .filter { !$0.subjects.isEmpty }
    }

    private func expandedRows(for subjects: [ReviewRow]) -> [ReviewRow] {
        subjects.flatMap { subject -> [ReviewRow] in
            guard subject.isGroup, expandedSubjectIDs.contains(subject.id) else { return [subject] }
            return [subject] + subject.entries.map { entry in
                ReviewRow(id: "\(subject.id)|\(entry.id)", subjectID: subject.id, entries: [entry], isPage: true)
            }
        }
    }

    private func bulkPicks(in subjects: [ReviewRow]) -> [ReviewAISuggestion] {
        subjects.compactMap(\.pick).filter { $0.kind == .work || $0.kind == .personal }
    }

    var body: some View {
        let subjects = subjects
        let sections = sections(for: subjects)
        let rows = sections.flatMap { expandedRows(for: $0.subjects) }
        let selectedID = selectedID(in: rows)
        let bulkPicks = bulkPicks(in: subjects)
        VStack(spacing: 0) {
            header(subjects, bulkPicks: bulkPicks)
            ScrollViewReader { proxy in
                List {
                    if subjects.isEmpty {
                        ContentUnavailableView(
                            "Nothing needs you",
                            systemImage: "checkmark.circle",
                            description: Text(aiEnabled
                                ? "AI files new activity as it comes in. Anything it can't decide will show up here."
                                : "Activity Hago can't file on its own will show up here.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    ForEach(sections) { section in
                        reviewSection(section, selectedID: selectedID, rows: rows)
                    }
                    LearningSuggestionsSection()
                    if !rows.isEmpty {
                        Text("↑ ↓ move · → open · W Work · P Personal · I Ignore · A accept AI pick")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
                .focusable()
                .focusEffectDisabled()
                .focused($listHasKeyboardFocus)
                .onAppear { listHasKeyboardFocus = true }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard let index = rows.firstIndex(where: { $0.id == selectedID }) else { return .ignored }
                    let next = press.key == .upArrow ? index - 1 : index + 1
                    guard rows.indices.contains(next) else { return .handled }
                    selectedRowID = rows[next].id
                    proxy.scrollTo(rows[next].id)
                    return .handled
                }
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    guard let row = rows.first(where: { $0.id == selectedID }) else { return .ignored }
                    if press.key == .rightArrow, row.isGroup {
                        expandedSubjectIDs.insert(row.subjectID)
                    } else if press.key == .leftArrow {
                        expandedSubjectIDs.remove(row.subjectID)
                        selectedRowID = row.subjectID
                    }
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "wWpPiIaA")) { press in
                    guard press.modifiers.intersection([.command, .control, .option]).isEmpty,
                          let row = rows.first(where: { $0.id == selectedID }) else { return .ignored }
                    switch press.characters.lowercased() {
                    case "w": decide(row, as: .work, in: rows)
                    case "p": decide(row, as: .personal, in: rows)
                    case "i": decide(row, as: .ignored, in: rows)
                    default:
                        guard let pick = row.pick else { return .ignored }
                        accept(pick, for: row, in: rows)
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
            "Accept \(bulkPicks.count) AI pick\(bulkPicks.count == 1 ? "" : "s")?",
            isPresented: $confirmsBulkAccept
        ) {
            Button("Accept \(bulkPicks.count)") {
                appState.applyReviewAISuggestions(bulkPicks)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each pick becomes a Work or Personal rule, so these sites and apps are filed automatically from now on, including their past recordings. You can change them in Rules.")
        }
        .confirmationDialog(
            "Delete \(pendingIgnore?.row.segmentCount ?? 0) recording\(pendingIgnore?.row.segmentCount == 1 ? "" : "s")?",
            isPresented: Binding(get: { pendingIgnore != nil }, set: { if !$0 { pendingIgnore = nil } }),
            presenting: pendingIgnore
        ) { ignore in
            Button("Delete", role: .destructive) { file(ignore.row, as: .ignored, in: ignore.rows) }
            Button("Cancel", role: .cancel) {}
        } message: { ignore in
            Text("\(HagoDuration.text(ignore.row.duration)) will be removed permanently and can't be undone. To stop recording it in future, add it to Privacy → Never record.")
        }
    }

    private func selectedID(in rows: [ReviewRow]) -> String? {
        if let selectedRowID, rows.contains(where: { $0.id == selectedRowID }) {
            return selectedRowID
        }
        return rows.first?.id
    }

    private func selectNext(after row: ReviewRow, removing removed: (ReviewRow) -> Bool, in rows: [ReviewRow]) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let remaining = rows.enumerated().filter { !removed($0.element) }
        selectedRowID = remaining.first(where: { $0.offset > index })?.element.id ?? remaining.last?.element.id
    }

    private func decided(by row: ReviewRow) -> (ReviewRow) -> Bool {
        let groupIDs = Set(row.entries.map(\.id))
        return { other in
            other.id == row.id
                || (!row.isPage && other.subjectID == row.subjectID)
                || (other.isPage && groupIDs.isSuperset(of: other.entries.map(\.id)))
        }
    }

    /// Ignore always asks first and deletes only the recordings shown, even when AI picked it. On a whole
    /// site or app, choosing what AI picked accepts its rule, and Work or Personal remembers it, so it never
    /// comes back to Review; a single page or window only files those recordings.
    private func decide(_ row: ReviewRow, as kind: ActivityKind, in rows: [ReviewRow]) {
        if kind == .ignored {
            pendingIgnore = PendingReviewIgnore(row: row, rows: rows)
            return
        }
        if !row.isPage, let pick = row.pick, ReviewSuggestionChoice.kind(pick) == kind {
            accept(pick, for: row, in: rows)
            return
        }
        file(row, as: kind, in: rows)
    }

    private func file(_ row: ReviewRow, as kind: ActivityKind, in rows: [ReviewRow]) {
        selectNext(after: row, removing: decided(by: row), in: rows)
        if let rule = rememberedRule(for: row, as: kind) {
            appState.rememberRule(rule)
        } else {
            appState.classifyReview(segmentIDs: row.segmentIDs, as: kind)
        }
    }

    private func rememberedRule(for row: ReviewRow, as kind: ActivityKind) -> Rule? {
        guard !row.isPage else { return nil }
        return rememberOptions(for: row).last { $0.action.kind == kind }
    }

    private func accept(_ suggestion: ReviewAISuggestion, for row: ReviewRow, in rows: [ReviewRow]) {
        let decided = decided(by: row)
        selectNext(after: row, removing: { decided($0) || $0.suggestion?.id == suggestion.id }, in: rows)
        appState.applyReviewAISuggestion(suggestion, as: suggestion.kind)
    }

    private func header(_ subjects: [ReviewRow], bulkPicks: [ReviewAISuggestion]) -> some View {
        let unchecked = aiEnabled ? subjects.filter(\.isUnchecked).count : 0
        return PageTop {
            PageHeader(
                title: subjects.isEmpty ? "All caught up" : "\(subjects.count) left to review",
                subtitle: subjects.isEmpty ? nil : subtitle(subjects, unchecked: unchecked)
            ) {
                headerActions(subjects, bulkPicks: bulkPicks, unchecked: unchecked)
            }
            notices
        }
    }

    private func subtitle(_ subjects: [ReviewRow], unchecked: Int) -> String {
        let total = "\(HagoDuration.text(subjects.reduce(0) { $0 + $1.duration })) not filed yet"
        let ai: String
        if !aiEnabled {
            ai = "Set up AI and it will file most of this for you."
        } else if appState.reviewAIAnalysisState == .analyzing {
            ai = "AI is going through them now."
        } else if unchecked > 0 {
            let next = appState.reviewAISettings.scheduleEnabled
                ? appState.reviewAIScheduleState.nextRunAt.map { " It checks again at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
                : ""
            ai = "AI hasn't looked at \(unchecked == subjects.count ? "these" : "\(unchecked) of these") yet.\(next)"
        } else {
            ai = "AI looked at all of these and needs your call."
        }
        return "\(total) · \(ai)"
    }

    @ViewBuilder
    private func headerActions(_ subjects: [ReviewRow], bulkPicks: [ReviewAISuggestion], unchecked: Int) -> some View {
        if appState.reviewAIAnalysisState == .analyzing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button("Stop") { appState.stopReviewAIAnalysis() }
            }
        } else if !aiEnabled {
            Button {
                appState.openHagoWindow(section: .aiReview)
            } label: {
                Label("Set Up AI…", systemImage: "sparkles")
            }
            .help("Connect an AI provider to file this activity for you")
        } else {
            if unchecked > 0 {
                Button {
                    appState.analyzeReview()
                } label: {
                    Label("Check with AI", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .help("Ask \(appState.reviewAISettings.selectedHarness.displayName) to look at these now")
            }
            if !bulkPicks.isEmpty {
                Button {
                    confirmsBulkAccept = true
                } label: {
                    Label("Accept \(bulkPicks.count) AI Pick\(bulkPicks.count == 1 ? "" : "s")", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .help("Turn every Work and Personal pick below into a rule")
            }
            if unchecked == 0, bulkPicks.isEmpty, !subjects.isEmpty {
                Button {
                    appState.analyzeReview()
                } label: {
                    Label("Ask Again", systemImage: "arrow.clockwise")
                }
                .help("Ask \(appState.reviewAISettings.selectedHarness.displayName) to look at these again")
            }
        }
    }

    /// One quiet line for what just happened: an undoable choice, AI's automatic filing, or an AI error.
    @ViewBuilder
    private var notices: some View {
        let run = appState.lastReviewAIRunSummary.flatMap {
            $0.automaticallyAppliedCount > 0 && $0.createdAt > Date().addingTimeInterval(-86_400) ? $0 : nil
        }
        let failure: String? = if case .failed(let message) = appState.reviewAIAnalysisState { message } else { nil }

        if failure != nil || appState.correctionMessage != nil || run != nil || appState.lastReviewAIUndoMessage != nil {
            HStack(spacing: 16) {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    Button("Try Again") { appState.analyzeReview() }
                } else if let message = appState.correctionMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .lineLimit(1)
                    if appState.latestCorrectionActionID != nil {
                        Button("Undo") { appState.undoLatestCorrection() }
                    }
                }
                Spacer(minLength: 0)
                if let undoMessage = appState.lastReviewAIUndoMessage {
                    Text(undoMessage)
                } else if let run {
                    Label("AI filed \(run.automaticallyAppliedCount) automatically", systemImage: "sparkles")
                    Button("View") { inspectingRun = run }
                    if run.canUndo {
                        Button("Undo") { appState.undoLastReviewAIRun() }
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .buttonStyle(.link)
            .controlSize(.small)
        }
    }

    private func reviewSection(_ section: ReviewSectionRows, selectedID: String?, rows: [ReviewRow]) -> some View {
        Section(section.title) {
            ForEach(expandedRows(for: section.subjects)) { row in
                let isSelected = row.id == selectedID
                ReviewGroupRow(
                    row: row,
                    showsAI: aiEnabled,
                    explanation: row.isGroup ? nil : appState.classificationExplanation(for: row.item),
                    recordingSummary: recordingSummary(for: row),
                    duration: HagoDuration.text(row.duration),
                    rememberOptions: rememberOptions(for: row),
                    isExpanded: row.isGroup ? expandedSubjectIDs.contains(row.subjectID) : nil,
                    showsActions: isSelected || row.id == hoveredRowID,
                    toggleExpanded: {
                        if expandedSubjectIDs.remove(row.subjectID) == nil {
                            expandedSubjectIDs.insert(row.subjectID)
                        }
                    },
                    decide: { kind in decide(row, as: kind, in: rows) },
                    remember: { rememberingRule = $0 }
                )
                .id(row.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedRowID = row.id
                    listHasKeyboardFocus = true
                }
                .onHover { hovering in
                    if hovering {
                        hoveredRowID = row.id
                    } else if hoveredRowID == row.id {
                        hoveredRowID = nil
                    }
                }
                .hagoRowBackground(isSelected: isSelected, isHovered: row.id == hoveredRowID)
            }
        }
    }

    /// Only offer "Always…" scopes that cover every page in the row.
    private func rememberOptions(for row: ReviewRow) -> [Rule] {
        let classifier = ActivityClassifier()
        return [ActivityKind.work, .personal].flatMap { kind in
            RememberedRuleFactory().rules(
                from: row.item,
                kind: kind,
                categoryID: appState.categories.first(where: { $0.kind == kind })?.id
            )
        }
        .filter { rule in
            row.entries.allSatisfy { classifier.matches(rule: rule, snapshot: $0.item.segment.snapshot) }
        }
    }

    private func recordingSummary(for row: ReviewRow) -> String {
        if row.segmentCount == 1 {
            return row.firstStartedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        let first = row.firstStartedAt.formatted(.dateTime.month(.abbreviated).day())
        let last = row.lastEndedAt.formatted(.dateTime.month(.abbreviated).day())
        let dateRange = Calendar.current.isDate(row.firstStartedAt, inSameDayAs: row.lastEndedAt)
            ? first : "\(first)–\(last)"
        return "\(row.segmentCount) recordings · \(dateRange)"
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
    @EnvironmentObject private var appState: AppState
    let row: ReviewRow
    let showsAI: Bool
    let explanation: String?
    let recordingSummary: String
    let duration: String
    let rememberOptions: [Rule]
    let isExpanded: Bool?
    let showsActions: Bool
    let toggleExpanded: () -> Void
    let decide: (ActivityKind) -> Void
    let remember: (Rule) -> Void

    private var segment: ActivitySegment { row.item.segment }
    private var isWebsite: Bool { !segment.snapshot.host.isEmpty }
    private var pickedKind: ActivityKind? { row.pick.flatMap(ReviewSuggestionChoice.kind) }

    private var title: String {
        if row.isPage {
            return segment.windowTitle.isEmpty ? segment.url ?? segment.appName : segment.windowTitle
        }
        if isWebsite { return segment.snapshot.host }
        if row.isGroup { return segment.appName }
        return segment.windowTitle.isEmpty ? segment.appName : segment.windowTitle
    }

    private var meta: String {
        if row.isPage { return recordingSummary }
        var parts: [String] = []
        if title != segment.appName { parts.append(segment.appName) }
        if row.isGroup {
            parts.append("\(row.entries.count) \(isWebsite ? "pages" : "windows")")
        } else if !segment.windowTitle.isEmpty, title != segment.windowTitle {
            parts.append(segment.windowTitle)
        }
        parts.append(recordingSummary)
        return parts.joined(separator: " · ")
    }

    private var showsExplanation: Bool {
        explanation?.hasPrefix("Conflicting rules") == true
    }

    private var tooltip: String {
        [segment.url, explanation].compactMap { $0 }.joined(separator: "\n")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if row.isPage {
                Color.clear.frame(width: 58, height: 1)
            } else {
                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded == true ? 90 : 0))
                        .frame(width: 16, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isExpanded == nil ? 0 : 1)
                .disabled(isExpanded == nil)
                .accessibilityLabel(isExpanded == true ? "Hide \(isWebsite ? "pages" : "windows")" : "Show \(isWebsite ? "pages" : "windows")")

                AppIconView(bundleIdentifier: segment.snapshot.bundleIdentifier, host: segment.snapshot.host, size: 30)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(row.isPage ? .body : .headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(meta)
                    .font(row.isPage ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if showsExplanation, let explanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                if !row.isGroup, segment.snapshot.isDiscordWithoutTitle {
                    Text("Channel titles were not captured. Your choice applies only to these recordings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showsAI, let suggestion = row.suggestion {
                    SuggestionLine(suggestion: suggestion, isPick: row.pick != nil)
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
        .padding(.vertical, row.isPage ? 2 : 6)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ForEach([ActivityKind.work, .personal]) { kind in
                if kind == pickedKind {
                    pickButton(kind)
                } else {
                    Button(kind.displayName) { decide(kind) }
                        .help(row.isPage || rememberOptions.isEmpty
                              ? "File these recordings as \(kind.displayName)"
                              : "Always file \(title) as \(kind.displayName), including past recordings")
                }
            }

            if pickedKind == .ignored {
                pickButton(.ignored)
            } else {
                Button(role: .destructive) { decide(.ignored) } label: {
                    Image(systemName: "eye.slash")
                        .accessibilityLabel("Ignore")
                }
                .help("Delete these recordings so they never count")
            }

            if !rememberOptions.isEmpty {
                Menu {
                    ForEach([ActivityKind.work, .personal]) { kind in
                        let options = rememberOptions.filter { $0.action.kind == kind }
                        if !options.isEmpty {
                            Section("Always \(kind.displayName)") {
                                ForEach(options) { rule in
                                    Button(appState.summary(for: rule)) { remember(rule) }
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

    private func pickButton(_ kind: ActivityKind) -> some View {
        Button { decide(kind) } label: {
            Label(kind == .ignored ? "Ignore" : kind.displayName, systemImage: "sparkles")
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(kind.tint)
        .help("Accept AI's pick: \(pickHelp(kind))")
    }

    private func pickHelp(_ kind: ActivityKind) -> String {
        let scope = row.pick?.proposedRuleCondition.map { condition in
            appState.summary(for: Rule(name: "", priority: 0, enabled: true, isBuiltIn: false,
                                       action: RuleAction(kind: kind, categoryID: nil, projectID: nil),
                                       conditions: [condition]))
        } ?? title
        return kind == .ignored ? "never record \(scope) (A)" : "always file \(scope) as \(kind.displayName) (A)"
    }
}

private struct SuggestionLine: View {
    let suggestion: ReviewAISuggestion
    let isPick: Bool

    private var label: String {
        switch suggestion.kind {
        case .unsure: "Unsure"
        case .ignored: isPick ? "Ignore" : "Leans Ignore"
        default: isPick ? suggestion.kind.displayName : "Leans \(suggestion.kind.displayName)"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Label(label, systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isPick ? (ReviewSuggestionChoice.kind(suggestion)?.tint ?? .secondary) : .secondary)
            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help("\(suggestion.reason)\n\(Int(round(suggestion.confidence * 100)))% confident")
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
            .environmentObject(appState)
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

    /// A recording that runs past 4am is listed on both days, so totals count only this day's part.
    private func secondsInDay(_ item: ClassifiedSegment) -> TimeInterval {
        let day = calendar.dayInterval(containing: appState.activityDate)
        return max(0, min(item.segment.endedAt, day.end).timeIntervalSince(max(item.segment.startedAt, day.start)))
    }

    private var daySubtitle: String {
        let total = appState.activitySegments.reduce(0) { $0 + secondsInDay($1) }
        let count = appState.activitySegments.count
        guard count > 0 else { return dayStart.formatted(date: .complete, time: .omitted) }
        return "\(HagoDuration.text(total)) tracked · \(count) recording\(count == 1 ? "" : "s")"
    }

    private func kindChips(_ segments: [ClassifiedSegment]) -> some View {
        let totals = Dictionary(grouping: segments, by: \.classification.kind)
            .mapValues { $0.reduce(0) { $0 + secondsInDay($1) } }
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
            AppIconView(bundleIdentifier: sample?.segment.snapshot.bundleIdentifier ?? "", host: sample?.segment.snapshot.host, size: 28)

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

            AppIconView(bundleIdentifier: segment.snapshot.bundleIdentifier, host: segment.snapshot.host, size: 24)

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
                AppIconView(bundleIdentifier: inspection.sample.segment.snapshot.bundleIdentifier, host: inspection.sample.segment.snapshot.host, size: 36)
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
                                            Button(appState.summary(for: rule)) { rememberingRule = rule }
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
        .hagoCard()
    }
}
