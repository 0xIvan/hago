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
        appState.ruleReviewRecords.filter { !$0.rule.isWorkDefault }
    }

    private var displayedRecords: [RuleReviewRecord] {
        filteredRecords(specificRecords)
    }

    private var displayedGroups: [RuleListGroup] {
        RuleListGroup.makeGroups(from: displayedRecords)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rules")
                        .font(.title2.weight(.semibold))
                    Text("\(attentionCount) need attention · \(specificRecords.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editingRule = Rule(
                        name: "New Rule",
                        priority: 150,
                        enabled: true,
                        isBuiltIn: false,
                        action: RuleAction(kind: .work, categoryID: categoryID(for: .work), projectID: nil),
                        conditions: [
                            RuleCondition(field: .bundleIdentifier, operation: .equals, value: "")
                        ],
                        origin: .user
                    )
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }

            ClassificationLearningPanel()
            ruleControls

            List {
                if displayedRecords.isEmpty {
                    Text(emptyRulesMessage)
                        .foregroundStyle(.secondary)
                }

                ForEach(displayedGroups) { group in
                    Section {
                        if group.records.allSatisfy({ $0.rule.isBuiltIn }) {
                            DisclosureGroup("\(group.title) (\(group.records.count))", isExpanded: $showsBuiltIns) {
                                ForEach(group.records) { record in ruleRow(record) }
                            }
                        } else {
                            ForEach(group.records) { record in ruleRow(record) }
                        }
                    } header: {
                        if !group.records.allSatisfy({ $0.rule.isBuiltIn }) {
                            Text("\(group.title) (\(group.records.count))")
                        }
                    }
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                projects: appState.projects,
                categories: appState.categories,
                onDelete: { deletedRule, scope in
                    appState.deleteRule(id: deletedRule.id, reclassify: scope)
                },
                onSave: { savedRule, scope in
                    appState.saveRule(savedRule, reclassify: scope)
                }
            )
        }
    }

    private var emptyRulesMessage: String {
        specificRecords.isEmpty ? "No specific rules" : "No matching rules"
    }

    private var attentionCount: Int {
        specificRecords.filter {
            !$0.issues.isDisjoint(with: [.conflict, .duplicate])
        }.count
    }

    private var ruleControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search rules", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            WrappingHStack(horizontalSpacing: 12, verticalSpacing: 8) {
                Picker("Result", selection: $kindFilter) {
                    ForEach(RuleKindFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 160)

                Picker("Status", selection: $statusFilter) {
                    ForEach(RuleStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 145)

                Picker("Source", selection: $sourceFilter) {
                    ForEach(RuleSourceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 145)

                Picker("Field", selection: $fieldFilter) {
                    ForEach(RuleFieldFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .frame(width: 170)
            }
        }
    }

    @ViewBuilder
    private func ruleRow(_ record: RuleReviewRecord) -> some View {
        let rule = record.rule
        HStack {
            Button {
                var updatedRule = rule
                updatedRule.enabled.toggle()
                appState.saveRule(updatedRule, reclassify: .today)
            } label: {
                Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(rule.enabled ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.headline)
                Text(ruleSummary(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(record.origin.displayName)
                    Text("\(record.matchedSegmentCount) direct uses")
                    ForEach(record.issues.sorted(by: { $0.rawValue < $1.rawValue })) { issue in
                        Text(issue.displayName)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(rule.action.kind.displayName)
                .font(.caption)
                .foregroundStyle(color(for: rule.action.kind))

            Button {
                editingRule = rule
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
        }
        .padding(.vertical, 4)
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
            ruleSummary(rule)
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

    private func ruleSummary(_ rule: Rule) -> String {
        rule.conditions
            .map { "\($0.field.displayName) \($0.operation.displayName) \($0.value)" }
            .joined(separator: " and ")
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
            .secondary
        }
    }
}

private struct RuleListGroup: Identifiable {
    var id: String
    var title: String
    var records: [RuleReviewRecord]

    static func makeGroups(from records: [RuleReviewRecord]) -> [RuleListGroup] {
        var remaining = records
        let definitions: [(String, String, (RuleReviewRecord) -> Bool)] = [
            ("attention", "Needs Attention", { !$0.issues.isDisjoint(with: [.conflict, .duplicate]) }),
            ("ai", "AI Applied", { $0.origin == .ai }),
            ("learned", "Learned", { $0.origin == .learned }),
            ("custom", "Custom", { $0.origin == .custom }),
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
    case ignored

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "All Results"
        case .work:
            "Work"
        case .personal:
            "Personal"
        case .review:
            "Needs review"
        case .ignored:
            "Ignored"
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
        case .ignored:
            .ignored
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
            "All Statuses"
        case .enabled:
            "Enabled"
        case .disabled:
            "Disabled"
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
    case ai
    case learned
    case custom
    case builtIn

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "All Sources"
        case .ai:
            "AI Applied"
        case .learned:
            "Learned"
        case .custom:
            "Custom"
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
        switch self {
        case .all:
            "All Fields"
        case .appName:
            RuleField.appName.displayName
        case .bundleIdentifier:
            RuleField.bundleIdentifier.displayName
        case .windowTitle:
            RuleField.windowTitle.displayName
        case .url:
            RuleField.url.displayName
        case .host:
            RuleField.host.displayName
        }
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
    @State private var field: RuleField
    @State private var operation: RuleOperation
    @State private var value: String
    @State private var reclassificationScope: ReclassificationScope?

    var rule: Rule
    var projects: [Project]
    var categories: [HagoCore.Category]
    var allowsDelete: Bool
    var onDelete: (Rule, ReclassificationScope?) -> Void
    var onSave: (Rule, ReclassificationScope?) -> Void

    init(
        rule: Rule,
        projects: [Project],
        categories: [HagoCore.Category],
        allowsDelete: Bool = true,
        onDelete: @escaping (Rule, ReclassificationScope?) -> Void,
        onSave: @escaping (Rule, ReclassificationScope?) -> Void
    ) {
        self.rule = rule
        self.projects = projects
        self.categories = categories
        self.allowsDelete = allowsDelete
        self.onDelete = onDelete
        self.onSave = onSave

        let condition = rule.conditions.first
            ?? RuleCondition(field: .windowTitle, operation: .contains, value: "")

        _name = State(initialValue: rule.name)
        _priority = State(initialValue: rule.priority)
        _enabled = State(initialValue: rule.enabled)
        _kind = State(initialValue: rule.action.kind)
        _projectIDValue = State(initialValue: rule.action.projectID?.uuidString ?? "")
        _field = State(initialValue: condition.field)
        _operation = State(initialValue: condition.operation)
        _value = State(initialValue: condition.value)
        _reclassificationScope = State(initialValue: .today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(name.isEmpty ? "Rule" : name)
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $name)

                Toggle("Enabled", isOn: $enabled)

                Picker("Result", selection: $kind) {
                    ForEach(ActivityKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                DisclosureGroup("Advanced") {
                    Picker("Project", selection: $projectIDValue) {
                        Text("None").tag("")
                        ForEach(projects.filter { !$0.isArchived }) { project in
                            Text(project.name).tag(project.id.uuidString)
                        }
                    }
                    Stepper(value: $priority, in: 1...2_000) {
                        Text("Priority \(priority)")
                    }
                    Text("Specific context takes precedence over priority. Conflicting personal rules need review.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Picker("Field", selection: $field) {
                    ForEach(RuleField.allCases) { field in
                        Text(field.displayName).tag(field)
                    }
                }

                Picker("Operation", selection: $operation) {
                    ForEach(RuleOperation.allCases) { operation in
                        Text(operation.displayName).tag(operation)
                    }
                }

                TextField("Value", text: $value)

                Picker("Reclassify", selection: $reclassificationScope) {
                    Text("Future Only").tag(ReclassificationScope?.none)
                    ForEach(ReclassificationScope.allCases) { scope in
                        Text(scope.displayName).tag(ReclassificationScope?.some(scope))
                    }
                }
            }

            HStack {
                if allowsDelete {
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

                Button {
                    onSave(updatedRule(), reclassificationScope)
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 520)
    }

    private func updatedRule() -> Rule {
        var updatedRule = rule
        updatedRule.name = name
        updatedRule.priority = priority
        updatedRule.enabled = enabled
        updatedRule.isBuiltIn = false
        if rule.origin == .preset {
            updatedRule.origin = .user
            updatedRule.presetID = nil
        }
        updatedRule.action = RuleAction(
            kind: kind,
            categoryID: categories.first { $0.kind == kind }?.id,
            projectID: UUID(uuidString: projectIDValue)
        )
        let updatedCondition = RuleCondition(
                id: rule.conditions.first?.id ?? UUID(),
                field: field,
                operation: operation,
                value: value
            )
        if updatedRule.conditions.isEmpty { updatedRule.conditions = [updatedCondition] }
        else { updatedRule.conditions[0] = updatedCondition }

        return updatedRule
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackingSettingsPanel()
            AccessibilityAccessPanel()

            HStack {
                Text("Ignore Rules")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    editingRule = Rule(
                        name: "New Ignore Rule",
                        priority: 20,
                        enabled: true,
                        isBuiltIn: false,
                        action: RuleAction(kind: .ignored, categoryID: nil, projectID: nil),
                        conditions: [
                            RuleCondition(field: .windowTitle, operation: .contains, value: "")
                        ]
                    )
                } label: {
                    Label("Add Ignore Rule", systemImage: "plus")
                }
            }

            List(appState.rules.filter { $0.action.kind == .ignored }) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.name)
                            .font(.headline)
                        Text(rule.conditions.map { "\($0.field.displayName) \($0.operation.displayName) \($0.value)" }.joined(separator: " and "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editingRule = rule
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .labelStyle(.iconOnly)
                }
                .padding(.vertical, 4)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                projects: appState.projects,
                categories: appState.categories,
                onDelete: { deletedRule, scope in
                    appState.deleteRule(id: deletedRule.id, reclassify: scope)
                },
                onSave: { savedRule, scope in
                    var ignoreRule = savedRule
                    ignoreRule.action = RuleAction(kind: .ignored, categoryID: nil, projectID: nil)
                    appState.saveRule(ignoreRule, reclassify: scope)
                }
            )
        }
    }
}
