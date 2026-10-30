import SwiftUI
import HagoCore

struct RuleEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var scope: RuleScope
    @State private var customConditions: [RuleCondition]
    @State private var usesCustomConditions: Bool
    @State private var customName: String
    @State private var enabled: Bool
    @State private var kind: ActivityKind
    @State private var projectIDValue: String
    @State private var reclassificationScope: ReclassificationScope?
    @State private var matchSummary: RuleMatchSummary?
    @State private var deletesPastRecordings = true

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

        let parsedScope = RuleScope(conditions: rule.conditions)
        _scope = State(initialValue: parsedScope ?? RuleScope(target: lockedKind == .ignored ? .app : .website))
        _usesCustomConditions = State(initialValue: parsedScope == nil && !rule.conditions.isEmpty)
        _customConditions = State(initialValue: rule.conditions.isEmpty
            ? [RuleCondition(field: .host, operation: .equals, value: "")]
            : rule.conditions)
        _customName = State(initialValue: parsedScope == nil ? rule.name : "")
        _enabled = State(initialValue: rule.enabled)
        _kind = State(initialValue: lockedKind ?? rule.action.kind)
        _projectIDValue = State(initialValue: rule.action.projectID?.uuidString ?? "")
        _reclassificationScope = State(initialValue: .allHistory)
    }

    private var isNew: Bool {
        rule.name.isEmpty
    }

    private var targets: [RuleTarget] {
        lockedKind == .ignored ? RuleTarget.allCases : [.app, .website, .page]
    }

    private var conditions: [RuleCondition] {
        if usesCustomConditions {
            return customConditions.map { condition in
                var trimmed = condition
                trimmed.value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed
            }
        }
        // Keep stored conditions when the scope is unchanged so undo fingerprints stay valid.
        if RuleScope(conditions: rule.conditions) == scope {
            return rule.conditions
        }
        return scope.conditions
    }

    private var canSave: Bool {
        usesCustomConditions
            ? !customConditions.contains { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            : scope.isComplete
    }

    private var title: String {
        if lockedKind == .ignored { return isNew ? "Never Record" : "Edit Never Record" }
        return isNew ? "New Rule" : "Edit Rule"
    }

    private var coverageText: String {
        if usesCustomConditions {
            return RuleDescription.summary(for: Rule(name: "", priority: 0, enabled: true, isBuiltIn: false,
                                                     action: RuleAction(kind: kind, categoryID: nil, projectID: nil),
                                                     conditions: conditions))
        }
        return scope.isComplete ? scope.summary(appName: appState.appName(for:)) : "Choose what this rule covers."
    }

    var body: some View {
        Group {
            if lockedKind == .ignored && !usesCustomConditions {
                neverRecordBody
            } else {
                ruleBody
            }
        }
        .task(id: conditions.map { "\($0.field.rawValue):\($0.operation.rawValue):\($0.value)" }) {
            matchSummary = nil
            guard canSave else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            matchSummary = appState.ruleMatchSummary(Rule(
                name: "", priority: rule.priority, enabled: true, isBuiltIn: false,
                action: rule.action, conditions: conditions
            ))
        }
    }

    /// Never record has one job, so it gets its own plain sheet: what to skip, and what to do
    /// with recordings already saved. Matching history is deleted, so that choice is spelled out.
    private var neverRecordBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isNew ? "Never Record" : "Edit Never Record")
                    .font(.title2.weight(.semibold))
                Text("Hago won't save any time spent here.")
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 20)

            Form {
                Section {
                    Picker("Type", selection: Binding(
                        get: { scope.target },
                        set: { target in
                            guard target != scope.target else { return }
                            scope = RuleScope(target: target)
                        }
                    )) {
                        ForEach(RuleTarget.allCases.filter { $0 != .page || scope.target == .page }) { target in
                            Text(target.displayName).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch scope.target {
                    case .app:
                        LabeledContent("App") {
                            AppChooser(bundleIdentifier: $scope.value)
                        }
                    case .website:
                        WebsiteField(value: $scope.value)
                        Toggle("Include subdomains", isOn: $scope.includesSubdomains)
                    case .page:
                        TextField("Page address", text: $scope.value, prompt: Text("https://github.com/acme/project"))
                        Toggle("Include pages under this address", isOn: $scope.includesSubpages)
                    case .title:
                        LabeledContent("Window title") {
                            HStack(spacing: 8) {
                                TitleMatchPicker(selection: $scope.titleMatch)
                                TextField("Window title", text: $scope.value, prompt: Text("Dashlane"))
                                    .labelsHidden()
                                    .frame(width: 200)
                            }
                        }
                    }
                    if scope.target != .title, !scope.title.isEmpty {
                        titleField
                    }
                } footer: {
                    Label(scope.isComplete ? scope.summary(appName: appState.appName(for:)) : "Choose what Hago should skip.", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let matchSummary, matchSummary.count > 0 {
                    Section {
                        Toggle(
                            "Delete \(matchSummary.count) past recording\(matchSummary.count == 1 ? "" : "s") (\(HagoDuration.text(matchSummary.seconds)))",
                            isOn: $deletesPastRecordings
                        )
                    } footer: {
                        Text(deletesPastRecordings ? "They're removed from your history for good." : "They stay in your history.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if allowsDelete && !isNew {
                    Button("Remove Rule", role: .destructive) {
                        onDelete(rule, .allHistory)
                        dismiss()
                    }
                    .help("Start recording this again. Recordings already deleted don't come back.")
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isNew ? "Never Record" : "Save") {
                    onSave(updatedRule(), deletesPastRecordings ? .allHistory : nil)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520)
    }

    private var ruleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 20)

            Form {
                Section {
                    if usesCustomConditions {
                        CustomConditionsEditor(conditions: $customConditions)
                    } else {
                        Picker("Covers", selection: Binding(
                            get: { scope.target },
                            set: { target in
                                guard target != scope.target else { return }
                                scope = RuleScope(target: target)
                            }
                        )) {
                            ForEach(targets) { target in
                                Label(target.displayName, systemImage: target.symbolName).tag(target)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        scopeFields
                    }
                } header: {
                    Text(lockedKind == .ignored ? "Never record" : "What should this rule cover?")
                } footer: {
                    coverageFooter
                }

                if lockedKind == nil {
                    Section("Count it as") {
                        Picker("Result", selection: $kind) {
                            ForEach([ActivityKind.work, .personal, .review]) { kind in
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
                    Picker("Past activity", selection: $reclassificationScope) {
                        Text(lockedKind == .ignored ? "Delete matches from all history" : "Update all history").tag(ReclassificationScope?.some(.allHistory))
                        Text(lockedKind == .ignored ? "Delete today's matches" : "Update today only").tag(ReclassificationScope?.some(.today))
                        Text(lockedKind == .ignored ? "Keep them" : "Leave unchanged").tag(ReclassificationScope?.none)
                    }
                    if !isNew {
                        Toggle("Rule is on", isOn: $enabled)
                    }
                    if usesCustomConditions {
                        TextField("Name", text: $customName, prompt: Text("Rule name"))
                    }
                } footer: {
                    Text(lockedKind == .ignored
                         ? "Matching activity is never saved and wins over every other rule."
                         : "When several rules match, the most specific one wins: a page beats a window title, and a title beats a whole website or app.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
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

                if !usesCustomConditions {
                    Button("Advanced…") {
                        customConditions = scope.isComplete ? scope.conditions : customConditions
                        usesCustomConditions = true
                    }
                    .help("Match on app name, page address patterns or regular expressions")
                } else if let parsed = RuleScope(conditions: conditions) {
                    Button("Simple View") {
                        scope = parsed
                        usesCustomConditions = false
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isNew ? "Add Rule" : "Save") {
                    onSave(updatedRule(), reclassificationScope)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(minWidth: 600, maxWidth: 600, minHeight: 400)
    }

    @ViewBuilder
    private var scopeFields: some View {
        switch scope.target {
        case .app:
            LabeledContent("App") {
                AppChooser(bundleIdentifier: $scope.value)
            }
            titleField
        case .website:
            WebsiteField(value: $scope.value)
            Toggle("Include subdomains", isOn: $scope.includesSubdomains)
                .help("For example docs.\(scope.normalizedValue.isEmpty ? "github.com" : scope.normalizedValue)")
            titleField
        case .page:
            TextField("Page address", text: $scope.value, prompt: Text("https://github.com/acme/project"))
            Toggle("Include pages under this address", isOn: $scope.includesSubpages)
        case .title:
            LabeledContent("Window title") {
                HStack(spacing: 8) {
                    TitleMatchPicker(selection: $scope.titleMatch)
                    TextField("Window title", text: $scope.value, prompt: Text("Dashlane"))
                        .labelsHidden()
                        .frame(width: 200)
                }
            }
        }
    }

    private var titleField: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TitleMatchPicker(selection: $scope.titleMatch)
                TextField("Window title", text: $scope.title, prompt: Text("Optional"))
                    .labelsHidden()
                    .frame(width: 200)
            }
        } label: {
            Text("Only when the title")
            Text("Leave empty to cover everything.")
        }
    }

    private var coverageFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(coverageText, systemImage: "scope")
                .foregroundStyle(.primary)
            if let matchSummary {
                Text(matchSummary.count == 0
                     ? "No past recordings match yet."
                     : "Matches \(matchSummary.count) past recording\(matchSummary.count == 1 ? "" : "s") (\(HagoDuration.text(matchSummary.seconds))). Your manual corrections stay as they are.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

    private func updatedRule() -> Rule {
        var updatedRule = rule
        let resultKind = lockedKind ?? kind
        updatedRule.conditions = conditions
        let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if usesCustomConditions {
            updatedRule.name = trimmedName.isEmpty
                ? "\(RuleDescription.summary(for: updatedRule)) → \(resultKind.displayName)"
                : trimmedName
        } else {
            updatedRule.name = scope.defaultName(kind: resultKind, appName: appState.appName(for:))
        }
        updatedRule.enabled = enabled
        updatedRule.isBuiltIn = false
        if rule.origin == .preset {
            updatedRule.origin = .user
            updatedRule.presetID = nil
        }
        updatedRule.action = RuleAction(
            kind: resultKind,
            categoryID: categories.first { $0.kind == resultKind }?.id,
            projectID: lockedKind == nil ? UUID(uuidString: projectIDValue) : nil
        )
        return updatedRule
    }
}

private struct TitleMatchPicker: View {
    @Binding var selection: TitleMatch

    var body: some View {
        Picker("Match", selection: $selection) {
            ForEach(TitleMatch.allCases) { match in
                Text(match.displayName).tag(match)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

private struct WebsiteField: View {
    @EnvironmentObject private var appState: AppState
    @Binding var value: String
    @FocusState private var isFocused: Bool
    @State private var isTyping = false

    private var suggestions: [String] {
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isFocused, isTyping, !query.isEmpty else { return [] }
        return Array(appState.recordedHosts().lazy.filter {
            $0 != query && ($0.hasPrefix(query) || $0.contains("." + query))
        }.prefix(5))
    }

    var body: some View {
        TextField("Website", text: $value, prompt: Text("github.com"))
            .focused($isFocused)
            .onChange(of: value) { isTyping = isFocused }
        ForEach(suggestions, id: \.self) { host in
            Button {
                value = host
                isFocused = false
            } label: {
                Label(host, systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private struct AppChooser: View {
    @EnvironmentObject private var appState: AppState
    @Binding var bundleIdentifier: String
    @State private var showsList = false

    var body: some View {
        Button {
            showsList = true
        } label: {
            HStack(spacing: 6) {
                if bundleIdentifier.isEmpty {
                    Text("Choose App…")
                } else {
                    AppIconView(bundleIdentifier: bundleIdentifier, size: 16)
                    Text(appState.appName(for: bundleIdentifier))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $showsList, arrowEdge: .bottom) {
            AppChooserList(selection: $bundleIdentifier, isPresented: $showsList)
                .environmentObject(appState)
        }
    }
}

private struct AppChooserList: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selection: String
    @Binding var isPresented: Bool
    @State private var search = ""
    @State private var installed: [DetectedWorkApp] = []

    private struct Choice: Identifiable {
        var id: String
        var name: String
        var detail: String?
    }

    private var choices: [Choice] {
        let recorded = appState.recordedApps()
        let recordedIDs = Set(recorded.map(\.bundleIdentifier))
        let all = recorded.map { Choice(id: $0.bundleIdentifier, name: $0.name, detail: HagoDuration.text($0.seconds)) }
            + installed.filter { !recordedIDs.contains($0.id) }.map { Choice(id: $0.id, name: $0.name, detail: nil) }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? all : all.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, prompt: "Search apps")
                .padding(10)
            Divider()
            List(choices) { choice in
                Button {
                    selection = choice.id
                    isPresented = false
                } label: {
                    HStack(spacing: 10) {
                        AppIconView(bundleIdentifier: choice.id, size: 22)
                        Text(choice.name)
                        Spacer()
                        if let detail = choice.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        if choice.id == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 320, height: 380)
        .onAppear { installed = DetectedWorkApp.installed() }
    }
}

private struct CustomConditionsEditor: View {
    @Binding var conditions: [RuleCondition]

    var body: some View {
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

                TextField("Value", text: $condition.value)
                    .labelsHidden()

                if conditions.count > 1 {
                    Button {
                        conditions.removeAll { $0.id == condition.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove condition")
                }
            }
        }

        Button {
            conditions.append(RuleCondition(field: .windowTitle, operation: .contains, value: ""))
        } label: {
            Label("Add Condition", systemImage: "plus")
        }
        .buttonStyle(.borderless)

        if conditions.count > 1 {
            Text("All conditions must match.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
