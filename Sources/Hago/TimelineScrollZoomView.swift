import AppKit
import SwiftUI

struct TimelineScrollZoomView: NSViewRepresentable {
    var onScroll: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> TimelineScrollZoomNSView {
        let view = TimelineScrollZoomNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: TimelineScrollZoomNSView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: TimelineScrollZoomNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

@MainActor
final class TimelineScrollZoomNSView: NSView {
    var onScroll: ((CGFloat, CGPoint) -> Void)?
    private var scrollMonitor: Any?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }

        // A local monitor consumes wheel events over the bar without intercepting SwiftUI's hover and click handling.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                self?.handleScroll(event) ?? false
            }
            return handled ? nil : event
        }
    }

    func stopMonitoring() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              !isHiddenOrHasHiddenAncestor else { return false }
        let location = convert(event.locationInWindow, from: nil)
        guard visibleRect.contains(location), event.scrollingDeltaY != 0 else { return false }

        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        onScroll?(delta, location)
        return true
    }
}
