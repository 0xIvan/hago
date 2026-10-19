import Testing
@testable import HagoCore

@Suite
struct ChartScaleTests {
    @Test
    func chartUsesEightHoursWhenDataIsLower() {
        #expect(ChartScale.maximumHours(for: [0, 3_600, 7.5 * 3_600]) == 8)
    }

    @Test
    func chartExpandsToFitDataAboveEightHours() {
        #expect(ChartScale.maximumHours(for: [8.25 * 3_600]) == 9)
    }
}
