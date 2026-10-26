import SwiftUI
import HagoCore

/// A stretch of the ring filed as one kind, after grouping time into small slots.
struct RingArc: Equatable {
    var startedAt: Date
    var endedAt: Date
    var kind: ActivityKind
    var trackedSeconds: TimeInterval
}

/// The Hago day, 4am to 4am, drawn as a ring that starts at the top like the app icon.
/// Time still ahead is dotted; hovering a block hands it to `center`.
struct DayRing<Center: View>: View {
    let day: DateInterval
    let spans: [ActivityTimelineSpan]
    let now: Date?
    let lineWidth: CGFloat
    let showsHours: Bool
    let center: (RingArc?) -> Center

    @State private var hoveredStart: Date?

    init(
        day: DateInterval,
        spans: [ActivityTimelineSpan],
        now: Date? = nil,
        lineWidth: CGFloat,
        showsHours: Bool = false,
        @ViewBuilder center: @escaping (RingArc?) -> Center
    ) {
        self.day = day
        self.spans = spans
        self.now = now
        self.lineWidth = lineWidth
        self.showsHours = showsHours
        self.center = center
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let arcs = ringArcs(in: size)
            ZStack {
                Canvas { context, size in
                    draw(arcs, in: &context, size: size)
                }
                center(arcs.first { $0.startedAt == hoveredStart })
                    .frame(width: max(0, ringRadius(in: size) * 1.6))
            }
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredStart = hoveredArc(at: location, in: size, among: arcs)?.startedAt
                case .ended:
                    hoveredStart = nil
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var seconds: [ActivityKind: TimeInterval] = [:]
        for span in spans {
            seconds[span.kind, default: 0] += max(0, min(span.endedAt, day.end).timeIntervalSince(max(span.startedAt, day.start)))
        }
        let parts = [ActivityKind.work, .personal, .review].compactMap { kind -> String? in
            guard let value = seconds[kind], value >= 60 else { return nil }
            let duration = Duration.seconds(Int(value) / 60 * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
            return "\(kind == .review ? "not filed" : kind.displayName.lowercased()) \(duration)"
        }
        return parts.isEmpty ? "Day ring, nothing recorded yet" : "Day ring: " + parts.joined(separator: ", ")
    }

    /// Quick switches between apps would draw as a barcode at ring scale, so each slot of a few
    /// minutes takes the kind that filled most of it, and neighbouring slots of one kind join up.
    private func ringArcs(in size: CGSize) -> [RingArc] {
        let circumference = 2 * .pi * ringRadius(in: size)
        let slotCount = min(max(Int(circumference / 2.5), 48), 288)
        let slot = day.duration / Double(slotCount)
        var seconds = Array(repeating: [ActivityKind: TimeInterval](), count: slotCount)

        for span in spans {
            let start = max(span.startedAt, day.start).timeIntervalSince(day.start)
            let end = min(span.endedAt, day.end).timeIntervalSince(day.start)
            guard end > start else { continue }
            var index = Int(start / slot)
            while index < slotCount, Double(index) * slot < end {
                let overlap = min(end, Double(index + 1) * slot) - max(start, Double(index) * slot)
                seconds[index][span.kind, default: 0] += max(overlap, 0)
                index += 1
            }
        }

        var arcs: [RingArc] = []
        for (index, kinds) in seconds.enumerated() {
            guard let dominant = kinds.max(by: { $0.value < $1.value }),
                  kinds.values.reduce(0, +) >= slot * 0.25 else { continue }
            let startedAt = day.start.addingTimeInterval(Double(index) * slot)
            if var last = arcs.last, last.kind == dominant.key, last.endedAt == startedAt {
                last.endedAt = startedAt.addingTimeInterval(slot)
                last.trackedSeconds += dominant.value
                arcs[arcs.count - 1] = last
            } else {
                arcs.append(RingArc(startedAt: startedAt, endedAt: startedAt.addingTimeInterval(slot),
                                    kind: dominant.key, trackedSeconds: dominant.value))
            }
        }
        return arcs
    }

    private func ringRadius(in size: CGSize) -> CGFloat {
        (min(size.width, size.height) - lineWidth) / 2
    }

    private func fraction(of date: Date) -> Double {
        min(max(date.timeIntervalSince(day.start) / day.duration, 0), 1)
    }

    private var nowFraction: Double? {
        guard let now, day.contains(now) else { return nil }
        return fraction(of: now)
    }

    private func draw(_ arcs: [RingArc], in context: inout GraphicsContext, size: CGSize) {
        let radius = ringRadius(in: size)
        let origin = CGPoint(x: size.width / 2, y: size.height / 2)

        func point(_ fraction: Double, radius: CGFloat) -> CGPoint {
            let angle = fraction * 2 * .pi - .pi / 2
            return CGPoint(x: origin.x + cos(angle) * radius, y: origin.y + sin(angle) * radius)
        }

        func arc(_ start: Double, _ end: Double) -> Path {
            Path { path in
                path.addArc(
                    center: origin,
                    radius: radius,
                    startAngle: .radians(start * 2 * .pi - .pi / 2),
                    endAngle: .radians(end * 2 * .pi - .pi / 2),
                    clockwise: false
                )
            }
        }

        func dot(at point: CGPoint, radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }

        let elapsed = nowFraction ?? 1
        context.stroke(arc(0, elapsed), with: .color(HagoPalette.track), style: StrokeStyle(lineWidth: lineWidth))

        let dotStep = 1.0 / 48
        var dotFraction = (elapsed / dotStep).rounded(.up) * dotStep
        while dotFraction < 1 - dotStep / 2 {
            if dotFraction - elapsed > dotStep / 2 {
                context.fill(dot(at: point(dotFraction, radius: radius), radius: max(0.9, lineWidth * 0.17)),
                             with: .color(.primary.opacity(0.18)))
            }
            dotFraction += dotStep
        }

        for ringArc in arcs {
            let isDimmed = hoveredStart != nil && hoveredStart != ringArc.startedAt
            context.stroke(arc(fraction(of: ringArc.startedAt), fraction(of: ringArc.endedAt)),
                           with: .color(ringArc.kind.tint.opacity(isDimmed ? 0.3 : 1)),
                           style: StrokeStyle(lineWidth: lineWidth))
        }

        if showsHours {
            let labelRadius = radius - lineWidth / 2 - 14
            for hour in 0..<24 {
                let date = day.start.addingTimeInterval(TimeInterval(hour) * 3_600)
                let position = point(fraction(of: date), radius: labelRadius)
                if Calendar.current.component(.hour, from: date) % 6 == 0 {
                    context.draw(
                        Text(date, format: .dateTime.hour())
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary),
                        at: position
                    )
                } else {
                    context.fill(dot(at: position, radius: 1), with: .color(.primary.opacity(0.15)))
                }
            }
        }

        if let nowFraction {
            let marker = point(nowFraction, radius: radius)
            let markerRadius = lineWidth * 0.5 + max(1.5, lineWidth * 0.15)
            context.fill(dot(at: marker, radius: markerRadius), with: .color(.white))
            context.stroke(dot(at: marker, radius: markerRadius), with: .color(.black.opacity(0.18)), lineWidth: 0.5)
        }
    }

    private func hoveredArc(at location: CGPoint, in size: CGSize, among arcs: [RingArc]) -> RingArc? {
        let dx = location.x - size.width / 2
        let dy = location.y - size.height / 2
        guard abs(hypot(dx, dy) - ringRadius(in: size)) <= lineWidth / 2 + 6 else { return nil }

        var fraction = (atan2(dy, dx) + .pi / 2) / (2 * .pi)
        if fraction < 0 { fraction += 1 }
        let time = day.start.addingTimeInterval(fraction * day.duration)
        return arcs.first { $0.startedAt <= time && time < $0.endedAt }
    }
}

extension DayRing where Center == EmptyView {
    init(day: DateInterval, spans: [ActivityTimelineSpan], now: Date? = nil, lineWidth: CGFloat) {
        self.init(day: day, spans: spans, now: now, lineWidth: lineWidth) { _ in EmptyView() }
    }
}
