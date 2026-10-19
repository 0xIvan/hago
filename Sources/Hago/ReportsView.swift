import Charts
import SwiftUI
import HagoCore

struct ReportsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode = ReportMode.weeks
    @State private var anchorDate = Date()
    @State private var reportPair: (current: ReportSummary, previous: ReportSummary)?

    private let formatter = TimeFormatting()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            reportControls

            if let reportPair {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        reportHeader(reportPair.current, previous: reportPair.previous)
                        reportMetrics(reportPair.current, previous: reportPair.previous)

                        SectionPanel(title: mode.chartTitle) {
                            ReportPeriodChart(report: reportPair.current, mode: mode)
                                .id([reportPair.current.startDate, reportPair.current.endDate])
                                .frame(height: 260)
                        }

                        HStack(alignment: .top, spacing: 16) {
                            SectionPanel(title: "Top Apps & Sites") {
                                ReportBucketComparisonList(
                                    currentBuckets: reportPair.current.topApps,
                                    previousBuckets: reportPair.previous.topApps
                                )
                            }

                            SectionPanel(title: "Top Projects") {
                                ReportBucketComparisonList(
                                    currentBuckets: reportPair.current.topProjects,
                                    previousBuckets: reportPair.previous.topProjects
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No report data")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: reloadReport)
        .onChange(of: mode) {
            reloadReport()
        }
        .onChange(of: anchorDate) {
            reloadReport()
        }
    }

    private var reportControls: some View {
        WrappingHStack(horizontalSpacing: 12, verticalSpacing: 8) {
            Picker("Period", selection: $mode) {
                ForEach(ReportMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button {
                shiftPeriod(by: -1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)

            Text(reportPair.map { periodTitle($0.current) } ?? mode.title)
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 220, alignment: .center)

            Button {
                shiftPeriod(by: 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)

            Button {
                anchorDate = Date()
            } label: {
                Label("Today", systemImage: "calendar")
            }
        }
    }

    private func reportHeader(_ report: ReportSummary, previous: ReportSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(periodTitle(report))
                .font(.title2.weight(.semibold))
            Text("Compared with \(periodTitle(previous))")
                .foregroundStyle(.secondary)
        }
    }

    private func reportMetrics(_ report: ReportSummary, previous: ReportSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ReportMetricCard(
                title: "Work",
                value: formatter.compactDuration(report.workSeconds),
                delta: durationDelta(report.workSeconds, previous.workSeconds),
                color: .blue
            )
            ReportMetricCard(
                title: "Personal",
                value: formatter.compactDuration(report.personalSeconds),
                delta: durationDelta(report.personalSeconds, previous.personalSeconds),
                color: .green
            )
            ReportMetricCard(
                title: "Total",
                value: formatter.compactDuration(report.totalSeconds),
                delta: durationDelta(report.totalSeconds, previous.totalSeconds),
                color: .primary
            )
            ReportMetricCard(
                title: "Work Ratio",
                value: percent(report.workRatio),
                delta: ratioDelta(report.workRatio, previous.workRatio),
                color: .purple
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func reloadReport() {
        reportPair = appState.loadReportPair(for: mode.periodKind, containing: anchorDate)
    }

    private func shiftPeriod(by offset: Int) {
        let component: Calendar.Component = mode == .weeks ? .weekOfYear : .month
        anchorDate = Calendar.current.date(byAdding: component, value: offset, to: anchorDate) ?? anchorDate
    }

    private func periodTitle(_ report: ReportSummary) -> String {
        switch report.periodKind {
        case .week:
            let endDate = report.endDate.addingTimeInterval(-1)
            return "\(report.startDate.formatted(.dateTime.month(.abbreviated).day())) - \(endDate.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month:
            return report.startDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private func durationDelta(_ current: TimeInterval, _ previous: TimeInterval) -> String {
        let delta = current - previous
        guard delta != 0 else {
            return "no change"
        }

        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(formatter.compactDuration(abs(delta)))"
    }

    private func ratioDelta(_ current: Double, _ previous: Double) -> String {
        let delta = current - previous
        guard delta != 0 else {
            return "no change"
        }

        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(Int(round(abs(delta) * 100))) pts"
    }

    private func percent(_ value: Double) -> String {
        "\(Int(round(value * 100)))%"
    }
}

private enum ReportMode: String, CaseIterable, Identifiable {
    case weeks
    case months

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .weeks:
            "Weeks"
        case .months:
            "Months"
        }
    }

    var periodKind: ReportPeriodKind {
        switch self {
        case .weeks:
            .week
        case .months:
            .month
        }
    }

    var chartTitle: String {
        switch self {
        case .weeks:
            "Daily Breakdown"
        case .months:
            "Weekly Breakdown"
        }
    }
}

private struct ReportPeriodChart: View {
    var report: ReportSummary
    var mode: ReportMode

    @State private var selectedBucketID: Date?
    @State private var tooltipX: CGFloat?

    private let tooltipWidth: CGFloat = 180

    private var selectedBucket: ReportBucket? {
        report.buckets.first { $0.id == selectedBucketID }
    }

    private var maximumHours: Double {
        ChartScale.maximumHours(
            for: report.buckets.map { $0.workSeconds + $0.personalSeconds + $0.reviewSeconds }
        )
    }

    var body: some View {
        Chart {
            ForEach(Array(report.buckets.enumerated()), id: \.element.id) { index, bucket in
                BarMark(
                    x: .value("Period", bucketTitle(bucket, index: index)),
                    y: .value("Hours", bucket.workSeconds / 3_600)
                )
                .foregroundStyle(by: .value("Type", "Work"))

                BarMark(
                    x: .value("Period", bucketTitle(bucket, index: index)),
                    y: .value("Hours", bucket.personalSeconds / 3_600)
                )
                .foregroundStyle(by: .value("Type", "Personal"))

                BarMark(
                    x: .value("Period", bucketTitle(bucket, index: index)),
                    y: .value("Hours", bucket.reviewSeconds / 3_600)
                )
                .foregroundStyle(by: .value("Type", "Review"))
            }

            if let selectedBucket,
               let index = report.buckets.firstIndex(where: { $0.id == selectedBucket.id }) {
                RuleMark(x: .value("Selected Period", bucketTitle(selectedBucket, index: index)))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartForegroundStyleScale([
            "Work": .blue,
            "Personal": .green,
            "Review": .orange
        ])
        .chartYScale(domain: 0...maximumHours)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
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
                                    updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )

                    if let selectedBucket, let tooltipX, let plotFrame = proxy.plotFrame {
                        ReportChartTooltip(bucket: selectedBucket, mode: mode)
                            .frame(width: tooltipWidth)
                            .offset(
                                x: min(max(tooltipX - tooltipWidth / 2, 0), max(0, geometry.size.width - tooltipWidth)),
                                y: geometry[plotFrame].minY + 8
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func clearSelection() {
        selectedBucketID = nil
        tooltipX = nil
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            clearSelection()
            return
        }

        let plotAreaFrame = geometry[plotFrame]
        guard plotAreaFrame.contains(location),
              let title = proxy.value(atX: location.x - plotAreaFrame.minX, as: String.self),
              let match = report.buckets.enumerated().first(where: { bucketTitle($0.element, index: $0.offset) == title }) else {
            clearSelection()
            return
        }

        selectedBucketID = match.element.id
        tooltipX = location.x
    }

    private func bucketTitle(_ bucket: ReportBucket, index: Int) -> String {
        switch mode {
        case .weeks:
            bucket.startDate.formatted(.dateTime.weekday(.abbreviated))
        case .months:
            "W\(index + 1)"
        }
    }
}

private struct ReportChartTooltip: View {
    var bucket: ReportBucket
    var mode: ReportMode

    private let formatter = TimeFormatting()

    private var title: String {
        if mode == .weeks {
            return bucket.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }

        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: bucket.endDate) ?? bucket.startDate
        return "\(bucket.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(lastDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))

            Divider()

            tooltipRow("Work", seconds: bucket.workSeconds, color: .blue)
            tooltipRow("Personal", seconds: bucket.personalSeconds, color: .green)
            tooltipRow("Review", seconds: bucket.reviewSeconds, color: .orange)
            tooltipRow("Total", seconds: bucket.workSeconds + bucket.personalSeconds + bucket.reviewSeconds, color: .primary)
        }
        .font(.caption)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    private func tooltipRow(_ label: String, seconds: TimeInterval, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
            Spacer()
            Text(formatter.compactDuration(seconds))
                .monospacedDigit()
        }
    }
}

private struct ReportBucketComparisonList: View {
    var currentBuckets: [TimeBucket]
    var previousBuckets: [TimeBucket]

    private let formatter = TimeFormatting()

    private var previousSecondsByName: [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: previousBuckets.map { ($0.name, $0.seconds) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if currentBuckets.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(currentBuckets) { bucket in
                HStack(spacing: 10) {
                    Text(bucket.name)
                        .lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatter.compactDuration(bucket.seconds))
                            .font(.subheadline.monospacedDigit())
                        Text(delta(bucket.seconds, previousSecondsByName[bucket.name] ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func delta(_ current: TimeInterval, _ previous: TimeInterval) -> String {
        let delta = current - previous
        guard delta != 0 else {
            return "no change"
        }

        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(formatter.compactDuration(abs(delta)))"
    }
}

private struct ReportMetricCard: View {
    var title: String
    var value: String
    var delta: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(delta)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
