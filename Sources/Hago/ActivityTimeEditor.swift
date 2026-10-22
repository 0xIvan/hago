import HagoCore
import SwiftUI

struct ActivityTimeEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let item: ClassifiedSegment
    @State private var start: Date
    @State private var end: Date

    init(item: ClassifiedSegment) {
        self.item = item
        _start = State(initialValue: item.segment.startedAt)
        _end = State(initialValue: item.segment.endedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Time — \(item.segment.appName)").font(.headline)
            Text("Remove unattended time within this interval. Removing a middle range splits the activity; the remaining time keeps its classification. Removed time cannot be undone.")
                .foregroundStyle(.secondary)
            Text("Recorded: \(item.segment.startedAt.formatted()) – \(item.segment.endedAt.formatted())")
                .font(.caption)
            DatePicker("Remove from", selection: $start, in: item.segment.startedAt...item.segment.endedAt)
            DatePicker("Remove until", selection: $end, in: item.segment.startedAt...item.segment.endedAt)
            if let error = appState.errorMessage ?? appState.trackingErrorMessage {
                Text(error).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Remove Selected Time", role: .destructive) {
                    if appState.removeActivityTime(item, from: start, to: end) { dismiss() }
                }
                .disabled(start >= end)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
