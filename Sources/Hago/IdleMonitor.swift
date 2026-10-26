import CoreGraphics
import Foundation
import IOKit.pwr_mgt

enum IdleMonitor {
    static func secondsSinceInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Video players and call apps hold this assertion, so watching or listening without touching
    /// the Mac still counts as being there.
    static func someoneIsWatching() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let values = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (values[kIOPMAssertPreventUserIdleDisplaySleep as String] ?? 0) > 0
    }
}
