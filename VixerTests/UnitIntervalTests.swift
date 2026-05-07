import XCTest
@testable import Vixer

final class UnitIntervalTests: XCTestCase {
    func test_clampFloat_limitsValuesToClosedUnitInterval() {
        XCTAssertEqual(UnitInterval.clamp(-0.25 as Float), 0)
        XCTAssertEqual(UnitInterval.clamp(0.42 as Float), 0.42)
        XCTAssertEqual(UnitInterval.clamp(1.25 as Float), 1)
    }

    func test_clampCGFloat_limitsValuesToClosedUnitInterval() {
        XCTAssertEqual(UnitInterval.clamp(CGFloat(-0.25)), 0)
        XCTAssertEqual(UnitInterval.clamp(CGFloat(0.42)), 0.42)
        XCTAssertEqual(UnitInterval.clamp(CGFloat(1.25)), 1)
    }
}
