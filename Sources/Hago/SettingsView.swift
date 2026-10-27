import AppKit
import SwiftUI
import HagoCore

struct RulesSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var pane: RulesPane
    @State private var editingRule: Rule?
    @State private var searchText = ""
    @State private var kindFilter = RuleKindFilter.all
    @State private var statusFilter = RuleStatusFilter.all
    @State private var sourceFilter = RuleSourceFilter.all
    @State private var targetFilter = RuleTargetFilter.all
    @State private var showsBuiltIns = false

    private var specificRecords: [RuleReviewRecord] {
        appState.ruleReviewRecords.filter { !$0.rule.isWorkDefault && $0.rule.action.kind != .ignored }
    }

    private var displayedRecords: [RuleReviewRecord] {
        filteredRecords(specificRecords)
    }

    private var displayedGroups: [RuleListGroup] {
        RuleListGroup.makeGroups(from: displayedRecords)
    }

    private var activeFilterCount: Int {
        [kindFilter != .all, statusFilter != .all, sourceFilter != .all, targetFilter != .all].filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            PageTop {
                PageHeader(
                    title: "\(specificRecords.count) specific rule\(specificRecords.count == 1 ? "" : "s")",
                    subtitle: RulesPane.rules.caption
                ) {
                    RulesPanePicker(selection: $pane)
                }
                toolbar
            }

            List {
                if displayedRecords.isEmpty {
                    ContentUnavailableView {
                        Label(specificRecords.isEmpty ? "No rules yet" : "No matching rules", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text(specificRecords.isEmpty
                             ? "Choose Always… in Review, or add a rule here."
                             : "Try a different search or clear the filters.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                ForEach(displayedGroups) { group in
                    Section {
                        if group.isCollapsible {
                            DisclosureGroup(isExpanded: $showsBuiltIns) {
                                ForEach(group.records) { record in ruleRow(record) }
                            } label: {
                                Text("\(group.title) (\(group.records.count))")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(group.records) { record in ruleRow(record) }
                        }
                    } header: {
                        if !group.isCollapsible {
                            Text("\(group.title) (\(group.records.count))")
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                projects: appState.projects,
                categories: appState.categories,
                allowsDelete: specificRecords.contains { $0.rule.id == rule.id },
                onDelete: { deletedRule, scope in
                    appState.deleteRule(id: deletedRule.id, reclassify: scope)
                },
                onSave: { savedRule, scope in
                    appState.saveRule(savedRule, reclassify: scope)
                }
            )
            .environmentObject(appState)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            SearchField(text: $searchText, prompt: "Search rules, sites, apps")

            FilterMenu(activeCount: activeFilterCount, clear: {
                kindFilter = .all
                statusFilter = .all
                sourceFilter = .all
                targetFilter = .all
            }) {
                Picker("Result", selection: $kindFilter) {
                    ForEach(RuleKindFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                Picker("Source", selection: $sourceFilter) {
                    ForEach(RuleSourceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                Picker("Status", selection: $statusFilter) {
                    ForEach(RuleStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                Picker("Covers", selection: $targetFilter) {
                    ForEach(RuleTargetFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
            }

            Button {
                editingRule = Rule(
                    name: "",
                    priority: 150,
                    enabled: true,
                    isBuiltIn: false,
                    action: RuleAction(kind: .work, categoryID: categoryID(for: .work), projectID: nil),
                    conditions: [
                        RuleCondition(field: .host, operation: .domain, value: "")
                    ],
                    origin: .user
                )
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func ruleRow(_ record: RuleReviewRecord) -> some View {
        let rule = record.rule
        HStack(spacing: 12) {
            Toggle("Enabled", isOn: Binding(
                get: { rule.enabled },
                set: { setEnabled($0, for: rule) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(rule.enabled ? "Turn this rule off" : "Turn this rule on")

            Button {
                editingRule = rule
            } label: {
                HStack(spacing: 12) {
                    RuleScopeIcon(rule: rule)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(appState.summary(for: rule))
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            ActivityKindBadge(kind: rule.action.kind)
                        }
                        if RuleScope(conditions: rule.conditions) == nil {
                            Text(rule.name)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        HStack(spacing: 8) {
                            Text(record.origin.displayName)
                            Text(record.matchedSegmentCount == 1 ? "1 match" : "\(record.matchedSegmentCount) matches")
                            if let projectName = projectName(for: rule) {
                                Label(projectName, systemImage: "folder")
                            }
                            ForEach(record.issues.sorted(by: { $0.rawValue < $1.rawValue })) { issue in
                                Label(issue.displayName, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(rule.enabled ? 1 : 0.55)
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit…") { editingRule = rule }
            Button(rule.enabled ? "Turn Off" : "Turn On") { setEnabled(!rule.enabled, for: rule) }
            Divider()
            Button("Delete", role: .destructive) {
                appState.deleteRule(id: rule.id, reclassify: .today)
            }
        }
    }

    private func setEnabled(_ enabled: Bool, for rule: Rule) {
        var updatedRule = rule
        updatedRule.enabled = enabled
        appState.saveRule(updatedRule, reclassify: .today)
    }

    private func filteredRecords(_ records: [RuleReviewRecord]) -> [RuleReviewRecord] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return records.filter { record in
            let rule = record.rule
            if let kind = kindFilter.kind, rule.action.kind != kind {
                return false
            }

            if let enabled = statusFilter.enabled, rule.enabled != enabled {
                return false
            }

            if let origin = sourceFilter.origin, record.origin != origin {
                return false
            }

            if targetFilter != .all, targetFilter != RuleTargetFilter(rule: rule) {
                return false
            }

            guard !trimmedSearchText.isEmpty else {
                return true
            }

            return searchableValues(for: rule)
                .contains { value in
                    value.lowercased().contains(trimmedSearchText)
                }
        }
    }

    private func searchableValues(for rule: Rule) -> [String] {
        [
            rule.name,
            rule.action.kind.displayName,
            rule.isBuiltIn ? "built in" : "user",
            rule.enabled ? "enabled" : "disabled",
            projectName(for: rule) ?? "",
            RuleDescription.summary(for: rule),
            appState.summary(for: rule)
        ]
    }

    private func projectName(for rule: Rule) -> String? {
        guard let projectID = rule.action.projectID else {
            return nil
        }

        return appState.projects.first { $0.id == projectID }?.name
    }

    private func categoryID(for kind: ActivityKind) -> UUID? {
        appState.categories.first { $0.kind == kind }?.id
    }
}

enum RuleDescription {
    static func summary(for rule: Rule) -> String {
        rule.conditions
            .map { "\($0.field.displayName) \($0.operation.displayName) \($0.value)" }
            .joined(separator: " and ")
    }
}

private struct RuleListGroup: Identifiable {
    var id: String
    var title: String
    var records: [RuleReviewRecord]

    var isCollapsible: Bool {
        id == "built-in"
    }

    static func makeGroups(from records: [RuleReviewRecord]) -> [RuleListGroup] {
        var remaining = records
        let definitions: [(String, String, (RuleReviewRecord) -> Bool)] = [
            ("attention", "Needs Attention", { !$0.issues.isDisjoint(with: [.conflict, .duplicate]) }),
            ("custom", "Your Rules", { $0.origin == .custom }),
            ("learned", "Learned From Your Choices", { $0.origin == .learned }),
            ("ai", "Added by AI", { $0.origin == .ai }),
            ("built-in", "Built-in", { $0.origin == .builtIn })
        ]

        return definitions.compactMap { id, title, includes in
            let matches = remaining
                .filter(includes)
                .sorted { first, second in
                    let kindOrder = first.rule.action.kind.rawValue.localizedCaseInsensitiveCompare(
                        second.rule.action.kind.rawValue
                    )
                    if kindOrder != .orderedSame {
                        return kindOrder == .orderedAscending
                    }
                    return first.rule.name.localizedCaseInsensitiveCompare(second.rule.name) == .orderedAscending
                }
            remaining.removeAll { record in matches.contains(where: { $0.id == record.id }) }
            guard !matches.isEmpty else {
                return nil
            }
            return RuleListGroup(id: id, title: title, records: matches)
        }
    }
}

private enum RuleKindFilter: String, CaseIterable, Identifiable {
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
            "Any Result"
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

private enum RuleStatusFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "On and Off"
        case .enabled:
            "On"
        case .disabled:
            "Off"
        }
    }

    var enabled: Bool? {
        switch self {
        case .all:
            nil
        case .enabled:
            true
        case .disabled:
            false
        }
    }
}

private enum RuleSourceFilter: String, CaseIterable, Identifiable {
    case all
    case custom
    case learned
    case ai
    case builtIn

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "Any Source"
        case .custom:
            "Custom"
        case .learned:
            "Learned"
        case .ai:
            "AI Applied"
        case .builtIn:
            "Built-in"
        }
    }

    var origin: RuleOrigin? {
        switch self {
        case .all:
            nil
        case .ai:
            .ai
        case .learned:
            .learned
        case .custom:
            .custom
        case .builtIn:
            .builtIn
        }
    }
}

private enum RuleTargetFilter: String, CaseIterable, Identifiable {
    case all
    case app
    case website
    case page
    case title
    case custom

    init(rule: Rule) {
        switch RuleScope(conditions: rule.conditions)?.target {
        case .app: self = .app
        case .website: self = .website
        case .page: self = .page
        case .title: self = .title
        case nil: self = .custom
        }
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "Anything"
        case .app: "Apps"
        case .website: "Websites"
        case .page: "Pages"
        case .title: "Window titles"
        case .custom: "Advanced"
        }
    }
}

struct RuleScopeIcon: View {
    let rule: Rule

    var body: some View {
        Group {
            if let scope = RuleScope(conditions: rule.conditions), scope.target == .app {
                AppIconView(bundleIdentifier: scope.normalizedValue, size: 24)
            } else if let scope = RuleScope(conditions: rule.conditions), scope.target == .website || scope.target == .page {
                let host = scope.target == .website ? scope.normalizedValue : URL(string: scope.normalizedValue)?.host
                AppIconView(bundleIdentifier: "", host: host, size: 24, placeholderSymbol: scope.target.symbolName)
            } else {
                Image(systemName: (RuleScope(conditions: rule.conditions)?.target.symbolName) ?? "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
    }
}

enum RulesPane: String, CaseIterable, Identifiable {
    case rules = "Specific Rules"
    case defaults = "Work Defaults"

    var id: Self { self }

    var caption: String {
        switch self {
        case .rules:
            "Rules for particular sites, pages, window titles and apps. They win over work defaults. Ignore rules live in Privacy."
        case .defaults:
            "Apps and sites that count as Work unless a specific rule says otherwise."
        }
    }
}

private struct RulesPanePicker: View {
    @Binding var selection: RulesPane

    var body: some View {
        Picker("Configure", selection: $selection) {
            ForEach(RulesPane.allCases) { pane in Text(pane.rawValue).tag(pane) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

struct RulesManagementView: View {
    @State private var pane = RulesPane.rules

    var body: some View {
        VStack(spacing: 0) {
            if pane == .rules {
                RulesSettingsView(pane: $pane)
            } else {
                PageTop {
                    PageHeader(title: "Work defaults", subtitle: RulesPane.defaults.caption) {
                        RulesPanePicker(selection: $pane)
                    }
                }
                WorkProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ProjectsSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var weekTotals: [String: TimeInterval] = [:]
    @State private var monthTotals: [String: TimeInterval] = [:]

    private var active: [Project] { appState.projects.filter { !$0.isArchived } }
    private var archived: [Project] { appState.projects.filter(\.isArchived) }

    var body: some View {
        VStack(spacing: 0) {
            PageTop {
                PageHeader(
                    title: "Projects",
                    subtitle: "Track time per client or product. A rule assigns the project, and Reports adds it up."
                ) {
                    Button {
                        appState.saveProject(Project(
                            name: "New Project",
                            colorHex: SwatchPalette.next(after: appState.projects.map(\.colorHex)),
                            isArchived: false
                        ))
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if appState.projects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "folder",
                    description: Text("Add a project, then pick it in a rule so its time shows up in Reports.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                            ForEach(active) { project in
                                ProjectCard(
                                    project: project,
                                    week: weekTotals[project.name] ?? 0,
                                    month: monthTotals[project.name] ?? 0,
                                    ruleCount: appState.rules.filter { $0.action.projectID == project.id }.count
                                )
                                .id(project.id)
                            }
                        }
                        if !archived.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Archived")
                                    .font(.headline)
                                Text("Archived projects keep their history but can't be picked in rules.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                ForEach(archived) { project in
                                    HStack(spacing: 10) {
                                        Circle().fill(Color(hex: project.colorHex) ?? .accentColor).frame(width: 10, height: 10)
                                        Text(project.name)
                                        Spacer()
                                        Button("Restore") {
                                            var restored = project
                                            restored.isArchived = false
                                            appState.saveProject(restored)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                            .hagoCard(padding: 14)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task(id: appState.projects.map(\.name)) {
            weekTotals = projectTotals(.week)
            monthTotals = projectTotals(.month)
        }
    }

    private func projectTotals(_ period: ReportPeriodKind) -> [String: TimeInterval] {
        let buckets = appState.loadReportPair(for: period, containing: Date())?.current.topProjects ?? []
        return Dictionary(buckets.map { ($0.name, $0.seconds) }, uniquingKeysWith: +)
    }
}

private struct ProjectCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var project: Project
    @State private var autosaveTask: Task<Void, Never>?
    let week: TimeInterval
    let month: TimeInterval
    let ruleCount: Int

    init(project: Project, week: TimeInterval, month: TimeInterval, ruleCount: Int) {
        _project = State(initialValue: project)
        self.week = week
        self.month = month
        self.ruleCount = ruleCount
    }

    private var color: Color { Color(hex: project.colorHex) ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ColorSwatchButton(colorHex: $project.colorHex)
                TextField("Name", text: $project.name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                Menu {
                    Button("Archive") { project.isArchived = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(week > 0 ? HagoDuration.text(week) : "0m")
                        .font(.hagoNumber(24))
                        .foregroundStyle(week > 0 ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
                    Text("this week").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(month > 0 ? HagoDuration.text(month) : "0m")
                        .font(.hagoNumber(24))
                        .foregroundStyle(month > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    Text("this month").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(ruleCount == 0 ? "No rule assigns it yet. Pick it in a rule under Rules." : "Assigned by \(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hagoCard(padding: 16)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous)
                .fill(color)
                .frame(width: 4)
        }
        .onChange(of: project) { _, updated in
            autosaveTask?.cancel()
            if updated.isArchived {
                appState.saveProject(updated)
                return
            }
            autosaveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                appState.saveProject(updated)
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            appState.saveProject(project)
        }
    }
}

struct CategoriesSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            PageTop {
                PageHeader(
                    title: "Categories",
                    subtitle: "Split Work and Personal into finer groups, like Meetings or Learning. Rules decide which category activity lands in."
                ) {
                    EmptyView()
                }
            }
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    CategoryGroup(kind: .work)
                    CategoryGroup(kind: .personal)
                }
                .padding(20)
            }
        }
    }
}

private struct CategoryGroup: View {
    @EnvironmentObject private var appState: AppState
    let kind: ActivityKind

    private var categories: [HagoCore.Category] {
        appState.categories.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(kind.tint).frame(width: 12, height: 12)
                Text(kind.displayName).font(.headline)
                Spacer()
                Text("\(categories.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            ForEach(categories) { category in
                CategoryRow(category: category, ruleCount: appState.rules.filter { $0.action.categoryID == category.id }.count)
                    .id(category.id)
                Divider()
            }
            Button {
                appState.saveCategory(HagoCore.Category(
                    name: "New category",
                    kind: kind,
                    colorHex: SwatchPalette.next(after: appState.categories.map(\.colorHex))
                ))
            } label: {
                Label("Add \(kind.displayName) category", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hagoCard(padding: 16)
    }
}

private struct CategoryRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var category: HagoCore.Category
    @State private var autosaveTask: Task<Void, Never>?
    let ruleCount: Int

    init(category: HagoCore.Category, ruleCount: Int) {
        _category = State(initialValue: category)
        self.ruleCount = ruleCount
    }

    private var otherKind: ActivityKind { category.kind == .work ? .personal : .work }

    var body: some View {
        HStack(spacing: 10) {
            ColorSwatchButton(colorHex: $category.colorHex)
            TextField("Name", text: $category.name)
                .textFieldStyle(.plain)
            Text(ruleCount == 0 ? "No rules" : "\(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Button("Move to \(otherKind.displayName)") { category.kind = otherKind }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 6)
        .onChange(of: category) { old, updated in
            autosaveTask?.cancel()
            if old.kind != updated.kind {
                appState.saveCategory(updated)
                return
            }
            autosaveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                appState.saveCategory(updated)
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            appState.saveCategory(category)
        }
    }
}

private enum SwatchPalette {
    static let colors = [
        "#2563EB", "#7C3AED", "#DB2777", "#DC2626", "#EA580C", "#D97706",
        "#16A34A", "#0D9488", "#0891B2", "#475569", "#9A5A2F", "#0A496E"
    ]

    static func next(after used: [String]) -> String {
        let used = Set(used.map { $0.uppercased() })
        return colors.first { !used.contains($0) } ?? colors[used.count % colors.count]
    }
}

/// A colour dot that opens a small palette, with the system colour panel for anything else.
private struct ColorSwatchButton: View {
    @Binding var colorHex: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Circle()
                .fill(Color(hex: colorHex) ?? .accentColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.black.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Change colour")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 8), count: 6), spacing: 8) {
                    ForEach(SwatchPalette.colors, id: \.self) { hex in
                        Button {
                            colorHex = hex
                            isPresented = false
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? .accentColor)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if hex.caseInsensitiveCompare(colorHex) == .orderedSame {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                ColorPicker("Other colour", selection: Binding(
                    get: { Color(hex: colorHex) ?? .accentColor },
                    set: { if let hex = $0.hexString { colorHex = hex } }
                ), supportsOpacity: false)
            }
            .padding(14)
        }
    }
}

private extension Color {
    init?(hex: String) {
        var trimmedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHex.hasPrefix("#") {
            trimmedHex.removeFirst()
        }

        guard trimmedHex.count == 6, let value = UInt64(trimmedHex, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else {
            return nil
        }

        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))

        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct AccessibilityAccessPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SectionPanel(title: "Accessibility") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        appState.accessibilityTrusted ? "Access granted" : "Window titles unavailable",
                        systemImage: appState.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle"
                    )
                    Text(appState.captureCapabilityLabel).font(.caption).foregroundStyle(.secondary)
                    Text("Chrome records sites and page titles, and skips private windows. Safari and other browsers count as app time only, with no sites or titles, because Hago can't tell whether their windows are private.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(appState.accessibilityTrusted
                         ? "Accessibility access lets Hago read active window titles."
                         : "Hago cannot read other apps’ window titles. App-level tracking continues; ambiguous activity needs review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !appState.accessibilityTrusted {
                    Button("Grant Access") {
                        appState.requestAccessibilityPermission()
                    }
                }
            }
        }
    }
}

struct PrivacySettingsView: View {
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Hago \(Date().formatted(.iso8601.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let count = appState.exportActivity(to: url) {
            exportMessage = "Exported \(count) recording\(count == 1 ? "" : "s") to \(url.lastPathComponent)."
        }
    }

    @EnvironmentObject private var appState: AppState
    @State private var editingRule: Rule?
    @State private var confirmsDeleteAll = false
    @State private var exportMessage: String?
    @State private var query = ""
    @State private var filter = IgnoreFilter.all
    @State private var showsAll = false
    @State private var siteIconsEnabled = SiteIcons.isEnabled

    private static let collapsedCount = 8

    private var shownRules: [Rule] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return ignoreRules.filter { rule in
            filter.includes(rule) && (needle.isEmpty
                || IgnoreRuleRow.title(for: rule).localizedCaseInsensitiveContains(needle)
                || IgnoreRuleRow.detail(for: rule).localizedCaseInsensitiveContains(needle))
        }
    }

    private var ignoreRules: [Rule] {
        appState.rules
            .filter { $0.action.kind == .ignored }
            .sorted { first, second in
                if first.isBuiltIn != second.isBuiltIn { return !first.isBuiltIn }
                return IgnoreRuleRow.title(for: first)
                    .localizedCaseInsensitiveCompare(IgnoreRuleRow.title(for: second)) == .orderedAscending
            }
    }

    var body: some View {
        Form {
            neverRecord
            yourData
            Section {
                LabeledContent {
                    if appState.accessibilityTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { appState.requestAccessibilityPermission() }
                    }
                } label: {
                    Text("Accessibility")
                    Text(appState.accessibilityTrusted
                         ? "Lets Hago read window titles so it can tell work from personal inside the same app."
                         : "Without it, Hago tracks apps only and more activity lands in Review.")
                }
                ChromeAccessRows()
            } header: {
                Text("Permissions")
            } footer: {
                Text(appState.captureCapabilityLabel)
            }

            Section("Always private") {
                Label("Incognito and private browser windows are never recorded.", systemImage: "eye.slash")
                Label("Chrome windows are checked before recording. Safari and other browsers count as app time only, never sites or titles.", systemImage: "safari")
                Label("Everything stays on this Mac. AI suggestions only send data when you connect a provider.", systemImage: "lock")
                Toggle(isOn: Binding(
                    get: { siteIconsEnabled },
                    set: { enabled in
                        siteIconsEnabled = enabled
                        UserDefaults.standard.set(enabled, forKey: SiteIcons.enabledKey)
                        Task { await SiteIcons.shared.removeAll() }
                    }
                )) {
                    Text("Show site icons")
                    Text("Downloads each site's icon once, from that site, with no cookies. Off shows letters instead.")
                }
                .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all recorded time?", isPresented: $confirmsDeleteAll) {
            Button("Delete All Recorded Time", role: .destructive) { appState.deleteAllActivity() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every recording on this Mac is removed and can't be undone. Daily backups in the Backups folder are kept until you delete them.")
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                projects: appState.projects,
                categories: appState.categories,
                lockedKind: .ignored,
                onDelete: { deletedRule, scope in
                    appState.deleteRule(id: deletedRule.id, reclassify: scope)
                },
                onSave: { savedRule, scope in
                    appState.saveRule(savedRule, reclassify: scope)
                }
            )
            .environmentObject(appState)
        }
    }

    private var neverRecord: some View {
        Section {
            if ignoreRules.isEmpty {
                Text("Nothing here yet. Add an app, website, or window title Hago should never record.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search", text: $query)
                            .textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Picker("Show", selection: $filter) {
                        ForEach(IgnoreFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                let shown = shownRules
                if shown.isEmpty {
                    Text("No matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(showsAll || !query.isEmpty ? shown : Array(shown.prefix(Self.collapsedCount))) { rule in
                    IgnoreRuleRow(
                        rule: rule,
                        edit: { editingRule = rule },
                        setEnabled: { enabled in
                            var updatedRule = rule
                            updatedRule.enabled = enabled
                            appState.saveRule(updatedRule, reclassify: .today)
                        },
                        delete: { appState.deleteRule(id: rule.id, reclassify: .today) }
                    )
                }
                if query.isEmpty, shown.count > Self.collapsedCount {
                    Button(showsAll ? "Show fewer" : "Show all \(shown.count)") { showsAll.toggle() }
                        .buttonStyle(.link)
                }
            }
        } header: {
            HStack {
                Text("Never record")
                Spacer()
                Menu {
                    Button("An App…") { addIgnoreRule(field: .bundleIdentifier, operation: .equals) }
                    Button("A Website…") { addIgnoreRule(field: .host, operation: .domain) }
                    Button("A Page…") { addIgnoreRule(field: .url, operation: .equals) }
                    Button("Window Titles…") { addIgnoreRule(field: .windowTitle, operation: .contains) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .fixedSize()
            }
        } footer: {
            Text("\(ignoreRules.count) rule\(ignoreRules.count == 1 ? "" : "s"). Matching activity is never saved and wins over every other rule.")
        }
    }

    private var yourData: some View {
        Section {
            LabeledContent {
                Button("Export CSV…", action: exportCSV)
            } label: {
                Text("Export")
                Text(exportMessage ?? "Every recording with its time, kind, project, app, title and address.")
            }
            if let backups = appState.backups {
                LabeledContent {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([backups.databaseURL])
                    }
                } label: {
                    Text("Database and backups")
                    Text("A copy is kept each day for the last \(backups.keeping) days in Backups/Daily beside the database.")
                }
            }
            LabeledContent {
                Button("Delete All…", role: .destructive) { confirmsDeleteAll = true }
            } label: {
                Text("Delete recorded time")
                Text("Rules, projects and settings stay.")
            }
        } header: {
            Text("Your data")
        }
    }

    private func addIgnoreRule(field: RuleField, operation: RuleOperation) {
        editingRule = Rule(
            name: "",
            priority: 20,
            enabled: true,
            isBuiltIn: false,
            action: RuleAction(kind: .ignored, categoryID: nil, projectID: nil),
            conditions: [RuleCondition(field: field, operation: operation, value: "")]
        )
    }
}

private enum IgnoreFilter: String, CaseIterable, Identifiable {
    case all, apps, sites, titles, off

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .apps: "Apps"
        case .sites: "Sites"
        case .titles: "Titles"
        case .off: "Off"
        }
    }

    func includes(_ rule: Rule) -> Bool {
        let field = rule.conditions.first?.field
        switch self {
        case .all: return true
        case .apps: return field == .bundleIdentifier || field == .appName
        case .sites: return field == .host || field == .url
        case .titles: return field == .windowTitle
        case .off: return !rule.enabled
        }
    }
}

private struct IgnoreRuleRow: View {
    let rule: Rule
    let edit: () -> Void
    let setEnabled: (Bool) -> Void
    let delete: () -> Void

    static func title(for rule: Rule) -> String {
        guard let condition = rule.conditions.first else { return rule.name }
        if condition.field == .bundleIdentifier,
           let app = DetectedWorkApp.application(withID: condition.value) {
            return app.name
        }
        return condition.value
    }

    private var condition: RuleCondition? {
        rule.conditions.first
    }

    private var detail: String { Self.detail(for: rule) }

    static func detail(for rule: Rule) -> String {
        var parts = [RuleDescription.summary(for: rule)]
        if let scope = RuleScope(conditions: rule.conditions) {
            parts = [scope.summary(appName: { DetectedWorkApp.application(withID: $0)?.name ?? $0 })]
        }
        if rule.isBuiltIn { parts.append("Built-in") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: rule))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Edit…", action: edit)
                .controlSize(.small)

            Toggle("Enabled", isOn: Binding(get: { rule.enabled }, set: { setEnabled($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .opacity(rule.enabled ? 1 : 0.55)
        .contextMenu {
            Button("Edit…", action: edit)
            Button(rule.enabled ? "Turn Off" : "Turn On") { setEnabled(!rule.enabled) }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch condition?.field {
        case .bundleIdentifier:
            AppIconView(bundleIdentifier: condition?.value ?? "", size: 22)
        case .host:
            AppIconView(bundleIdentifier: "", host: condition?.value, size: 22, placeholderSymbol: "globe")
        case .url:
            Image(systemName: "globe").foregroundStyle(.secondary)
        case .appName:
            Image(systemName: "app").foregroundStyle(.secondary)
        case .windowTitle, nil:
            Image(systemName: "macwindow").foregroundStyle(.secondary)
        }
    }
}
