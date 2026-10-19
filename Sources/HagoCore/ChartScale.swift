import Foundation

public enum ChartScale {
    public static let minimumHours = 8.0

    public static func maximumHours(for stackedTotals: [TimeInterval]) -> Double {
        let largestTotal = stackedTotals.max() ?? 0
        return max(minimumHours, ceil(largestTotal / 3_600))
    }
}
