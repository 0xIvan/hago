import SwiftUI
import UniformTypeIdentifiers

struct WorkAppSelectionView: View {
    @Binding var selectedIDs: Set<String>
    @State private var apps: [DetectedWorkApp] = []
    @State private var showsPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose apps that should default to Work. More specific rules can classify exceptions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(selectedIDs.sorted(), id: \.self) { id in
                let app = apps.first { $0.id == id } ?? DetectedWorkApp.application(withID: id)
                HStack(spacing: 8) {
                    if let app {
                        Image(nsImage: app.icon).resizable().frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "app").frame(width: 22, height: 22)
                    }
                    Text(app?.name ?? id)
                    Spacer()
                    Button {
                        selectedIDs.remove(id)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(app?.name ?? id)")
                }
                .padding(8)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            }
            Button {
                showsPicker = true
            } label: {
                Label(selectedIDs.isEmpty ? "Choose Apps…" : "Add or Remove Apps…", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { apps = DetectedWorkApp.installed() }
        .sheet(isPresented: $showsPicker) {
            WorkAppPicker(apps: $apps, selectedIDs: $selectedIDs)
        }
    }
}

private struct WorkAppPicker: View {
    @Binding var apps: [DetectedWorkApp]
    @Binding var selectedIDs: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var showsBrowser = false
    @State private var error: String?

    private var filteredApps: [DetectedWorkApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose work apps").font(.title2.weight(.semibold))
            Text("These apps default to Work. Specific site, title, and project rules take precedence.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Search installed apps", text: $search)
                .textFieldStyle(.roundedBorder)
            List(filteredApps) { app in
                Toggle(isOn: Binding(
                    get: { selectedIDs.contains(app.id) },
                    set: { selected in
                        if selected { selectedIDs.insert(app.id) }
                        else { selectedIDs.remove(app.id) }
                    }
                )) {
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon).resizable().frame(width: 26, height: 26)
                        Text(app.name)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 4)
            }
            .overlay {
                if filteredApps.isEmpty {
                    Text("No apps found. Try another search or browse for an app.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Browse…") { showsBrowser = true }
                Spacer()
                Text("\(selectedIDs.count) selected").foregroundStyle(.secondary)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
        .fileImporter(isPresented: $showsBrowser, allowedContentTypes: [.applicationBundle], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                var invalidNames: [String] = []
                for url in urls {
                    guard let app = DetectedWorkApp(url: url) else {
                        invalidNames.append(url.lastPathComponent)
                        continue
                    }
                    if !apps.contains(where: { $0.id == app.id }) { apps.append(app) }
                    selectedIDs.insert(app.id)
                }
                apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                error = invalidNames.isEmpty ? nil : "Could not identify: " + invalidNames.joined(separator: ", ")
            } catch {
                self.error = error.localizedDescription
            }
        }
        .fileDialogDefaultDirectory(URL(fileURLWithPath: "/Applications"))
    }
}
