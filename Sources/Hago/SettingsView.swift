import AppKit
import SwiftUI
import HagoCore

struct RulesSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingRule: Rule?
    @State private var searchText = ""
    @State private var kindFilter = RuleKindFilter.all
    @State private var statusFilter = RuleStatusFilter.all
    @State private var sourceFilter = RuleSourceFilter.all
    @State private var fieldFilter = RuleFieldFilter.all
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
        [kindFilter != .all, statusFilter != .all, sourceFilter != .all, fieldFilter != .all].filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

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
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search rules, sites, apps", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))

            Menu {
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
                Picker("Matches On", selection: $fieldFilter) {
                    ForEach(RuleFieldFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                if activeFilterCount > 0 {
                    Divider()
                    Button("Clear Filters") {
                        kindFilter = .all
                        statusFilter = .all
                        sourceFilter = .all
                        fieldFilter = .all
                    }
                }
            } label: {
                Label(
                    activeFilterCount == 0 ? "Filter" : "Filter (\(activeFilterCount))",
                    systemImage: activeFilterCount == 0
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .fixedSize()

            Button {
                editingRule = Rule(
                    name: "",
                    priority: 150,
                    enabled: true,
                    isBuiltIn: false,
                    action: RuleAction(kind: .work, categoryID: categoryID(for: .work), projectID: nil),
                    conditions: [
                        RuleCondition(field: .host, operation: .equals, value: "")
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
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(rule.name)
                                .font(.headline)
                                .lineLimit(1)
                            ActivityKindBadge(kind: rule.action.kind)
                        }
                        Text(RuleDescription.summary(for: rule))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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

            if let field = fieldFilter.field, !rule.conditions.contains(where: { $0.field == field }) {
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
            RuleDescription.summary(for: rule)
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

struct ActivityKindBadge: View {
    let kind: ActivityKind

    var body: some View {
        Text(kind.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch kind {
        case .work:
            .blue
        case .personal:
            .green
        case .review:
            .orange
        case .ignored:
            .secondary
        }
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

private enum RuleFieldFilter: String, CaseIterable, Identifiable {
    case all
    case appName
    case bundleIdentifier
    case windowTitle
    case url
    case host

    var id: String {
        rawValue
    }

    var title: String {
        field?.displayName ?? "Any Field"
    }

    var field: RuleField? {
        switch self {
        case .all:
            nil
        case .appName:
            .appName
        case .bundleIdentifier:
            .bundleIdentifier
        case .windowTitle:
            .windowTitle
        case .url:
            .url
        case .host:
            .host
        }
    }
}

struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var priority: Int
    @State private var enabled: Bool
    @State private var kind: ActivityKind
    @State private var projectIDValue: String
    @State private var conditions: [RuleCondition]
    @State private var reclassificationScope: ReclassificationScope?

    var rule: Rule
    var projects: [Project]
    var categories: [HagoCore.Category]
    var allowsDelete: Bool
    var lockedKind: ActivityKind?
    var onDelete: (Rule, ReclassificationScope?) -> Void
    var onSave: (Rule, ReclassificationScope?) -> Void

    init(
        rule: Rule,
        projects: [Project],
        categories: [HagoCore.Category],
        allowsDelete: Bool = true,
        lockedKind: ActivityKind? = nil,
        onDelete: @escaping (Rule, ReclassificationScope?) -> Void,
        onSave: @escaping (Rule, ReclassificationScope?) -> Void
    ) {
        self.rule = rule
        self.projects = projects
        self.categories = categories
        self.allowsDelete = allowsDelete
        self.lockedKind = lockedKind
        self.onDelete = onDelete
        self.onSave = onSave

        _name = State(initialValue: rule.name)
        _priority = State(initialValue: rule.priority)
        _enabled = State(initialValue: rule.enabled)
        _kind = State(initialValue: lockedKind ?? rule.action.kind)
        _projectIDValue = State(initialValue: rule.action.projectID?.uuidString ?? "")
        _conditions = State(initialValue: rule.conditions.isEmpty
            ? [RuleCondition(field: .windowTitle, operation: .contains, value: "")]
            : rule.conditions)
        _reclassificationScope = State(initialValue: .today)
    }

    private var isNew: Bool {
        rule.name.isEmpty
    }

    private var hasEmptyCondition: Bool {
        conditions.contains { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? (lockedKind == .ignored ? "Never Record" : "New Rule") : "Edit Rule")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 20)

            Form {
                Section {
                    ForEach($conditions) { $condition in
                        HStack(spacing: 8) {
                            Picker("Field", selection: $condition.field) {
                                ForEach(RuleField.allCases) { field in
                                    Text(field.displayName).tag(field)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()

                            Picker("Operation", selection: $condition.operation) {
                                ForEach(RuleOperation.allCases) { operation in
                                    Text(operation.displayName).tag(operation)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()

                            TextField("Value", text: $condition.value, prompt: Text(placeholder(for: condition.field)))
                                .labelsHidden()

                            if conditions.count > 1 {
                                Button {
                                    conditions.removeAll { $0.id == condition.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove this condition")
                            }
                        }
                    }

                    Button {
                        conditions.append(RuleCondition(field: .windowTitle, operation: .contains, value: ""))
                    } label: {
                        Label("Add Condition", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("When activity matches")
                } footer: {
                    if conditions.count > 1 {
                        Text("All conditions must match.")
                    }
                }

                if lockedKind == nil {
                    Section("Classify it as") {
                        Picker("Result", selection: $kind) {
                            ForEach(ActivityKind.allCases.filter { $0 != .ignored || rule.action.kind == .ignored }) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Picker("Project", selection: $projectIDValue) {
                            Text("None").tag("")
                            ForEach(projects.filter { !$0.isArchived }) { project in
                                Text(project.name).tag(project.id.uuidString)
                            }
                        }
                    }
                }

                Section {
                    TextField("Name", text: $name, prompt: Text(suggestedName))
                    Toggle("Enabled", isOn: $enabled)
                    Picker("Apply to existing activity", selection: $reclassificationScope) {
                        Text("Don't Change").tag(ReclassificationScope?.none)
                        ForEach(ReclassificationScope.allCases) { scope in
                            Text(scope.displayName).tag(ReclassificationScope?.some(scope))
                        }
                    }
                    if lockedKind == nil {
                        Stepper(value: $priority, in: 1...2_000) {
                            LabeledContent("Priority", value: "\(priority)")
                        }
                    }
                } header: {
                    Text("Details")
                } footer: {
                    if lockedKind == nil {
                        Text("More specific rules win over broader ones; priority breaks ties. Ignore rules always win.")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if allowsDelete && !isNew {
                    Button(role: .destructive) {
                        onDelete(rule, reclassificationScope)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isNew ? "Add" : "Save") {
                    onSave(updatedRule(), reclassificationScope)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(hasEmptyCondition)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(minWidth: 600, maxWidth: 600, minHeight: 480)
    }

    private var suggestedName: String {
        let value = conditions.first?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return "Rule name" }
        return lockedKind == .ignored ? "Ignore \(value)" : "\(kind.displayName): \(value)"
    }

    private func placeholder(for field: RuleField) -> String {
        switch field {
        case .appName: "Slack"
        case .bundleIdentifier: "com.tinyspeck.slackmacgap"
        case .windowTitle: "Standup"
        case .url: "https://github.com/acme"
        case .host: "github.com"
        }
    }

    private func updatedRule() -> Rule {
        var updatedRule = rule
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedRule.name = trimmedName.isEmpty ? suggestedName : trimmedName
        updatedRule.priority = priority
        updatedRule.enabled = enabled
        updatedRule.isBuiltIn = false
        if rule.origin == .preset {
            updatedRule.origin = .user
            updatedRule.presetID = nil
        }
        let resultKind = lockedKind ?? kind
        updatedRule.action = RuleAction(
            kind: resultKind,
            categoryID: categories.first { $0.kind == resultKind }?.id,
            projectID: lockedKind == nil ? UUID(uuidString: projectIDValue) : nil
        )
        updatedRule.conditions = conditions.map { condition in
            var trimmed = condition
            trimmed.value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed
        }

        return updatedRule
    }
}

struct RulesManagementView: View {
    @State private var selection = Pane.rules

    private enum Pane: String, CaseIterable, Identifiable {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Configure", selection: $selection) {
                    ForEach(Pane.allCases) { pane in Text(pane.rawValue).tag(pane) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text(selection.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if selection == .rules {
                RulesSettingsView()
            } else {
                WorkProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ProjectsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Projects")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    appState.saveProject(Project(name: "New Project", colorHex: "#2563EB", isArchived: false))
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
            }

            List(appState.projects) { project in
                ProjectEditorRow(project: project)
                    .environmentObject(appState)
            }
        }
    }
}

private struct ProjectEditorRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var project: Project
    @State private var autosaveTask: Task<Void, Never>?

    init(project: Project) {
        _project = State(initialValue: project)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $project.name)
            ColorInputView(colorHex: $project.colorHex)
            Toggle("Archived", isOn: $project.isArchived)
                .frame(width: 120)
        }
        .padding(.vertical, 4)
        .onChange(of: project) { _, updatedProject in
            scheduleAutosave(updatedProject)
        }
        .onDisappear {
            autosaveTask?.cancel()
            appState.saveProject(project)
        }
    }

    private func scheduleAutosave(_ updatedProject: Project) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }

            appState.saveProject(updatedProject)
        }
    }
}

struct CategoriesSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Categories")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    appState.saveCategory(HagoCore.Category(name: "New Category", kind: .work, colorHex: "#2563EB"))
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
            }

            List(appState.categories) { category in
                CategoryEditorRow(category: category)
                    .environmentObject(appState)
            }
        }
    }
}

private struct CategoryEditorRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var category: HagoCore.Category
    @State private var autosaveTask: Task<Void, Never>?

    init(category: HagoCore.Category) {
        _category = State(initialValue: category)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $category.name)
            Picker("Kind", selection: $category.kind) {
                ForEach(ActivityKind.allCases.filter { $0 != .ignored }) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .frame(width: 180)
            ColorInputView(colorHex: $category.colorHex)
        }
        .padding(.vertical, 4)
        .onChange(of: category) { _, updatedCategory in
            scheduleAutosave(updatedCategory)
        }
        .onDisappear {
            autosaveTask?.cancel()
            appState.saveCategory(category)
        }
    }

    private func scheduleAutosave(_ updatedCategory: HagoCore.Category) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }

            appState.saveCategory(updatedCategory)
        }
    }
}

private struct ColorInputView: View {
    @Binding var colorHex: String

    private var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker(
                "Color",
                selection: Binding(
                    get: { color },
                    set: { newColor in
                        if let hex = newColor.hexString {
                            colorHex = hex
                        }
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .fixedSize()

            TextField("Color", text: $colorHex)
                .font(.body.monospaced())
                .frame(width: 94)
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
                    Text("Chrome supports verified public-window capture. Safari and other browsers are excluded until private-window status can be verified.")
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
    @EnvironmentObject private var appState: AppState
    @State private var editingRule: Rule?

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
                Label("Chrome windows are checked before recording. Safari and other browsers are skipped until private windows can be detected.", systemImage: "safari")
                Label("Everything stays on this Mac. AI suggestions only send data when you connect a provider.", systemImage: "lock")
            }

            Section {
                if ignoreRules.isEmpty {
                    Text("Nothing here yet. Add an app, website, or window title Hago should never record.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ignoreRules) { rule in
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
            } header: {
                HStack {
                    Text("Never record")
                    Spacer()
                    Menu {
                        Button("An App…") { addIgnoreRule(field: .bundleIdentifier, operation: .equals) }
                        Button("A Website…") { addIgnoreRule(field: .host, operation: .domain) }
                        Button("Window Titles Containing…") { addIgnoreRule(field: .windowTitle, operation: .contains) }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .fixedSize()
                }
            } footer: {
                Text("Matching activity is never saved and wins over every other rule.")
            }
        }
        .formStyle(.grouped)
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

    private var detail: String {
        var parts = [RuleDescription.summary(for: rule)]
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
        case .host, .url:
            Image(systemName: "globe").foregroundStyle(.secondary)
        case .appName:
            Image(systemName: "app").foregroundStyle(.secondary)
        case .windowTitle, nil:
            Image(systemName: "macwindow").foregroundStyle(.secondary)
        }
    }
}
