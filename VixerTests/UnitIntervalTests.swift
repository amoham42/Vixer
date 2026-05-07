import CoreGraphics
import Testing
@testable import Vixer

struct UnitIntervalTests {
    @Test func clampFloatLimitsValuesToClosedUnitInterval() {
        #expect(UnitInterval.clamp(-0.25 as Float) == 0)
        #expect(UnitInterval.clamp(0.42 as Float) == 0.42)
        #expect(UnitInterval.clamp(1.25 as Float) == 1)
    }

    @Test func clampCGFloatLimitsValuesToClosedUnitInterval() {
        #expect(UnitInterval.clamp(CGFloat(-0.25)) == 0)
        #expect(UnitInterval.clamp(CGFloat(0.42)) == 0.42)
        #expect(UnitInterval.clamp(CGFloat(1.25)) == 1)
    }
}
