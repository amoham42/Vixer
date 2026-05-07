import XCTest
@testable import Vixer

final class VolumeSliderViewTests: XCTestCase {
    func test_valueForLocation_clampsNegativePositionToZero() {
        XCTAssertEqual(SliderValueMapper.value(for: -12, width: 100), 0)
    }

    func test_valueForLocation_clampsPastWidthToOne() {
        XCTAssertEqual(SliderValueMapper.value(for: 140, width: 100), 1)
    }

    func test_valueForLocation_mapsMidpointToHalf() {
        XCTAssertEqual(SliderValueMapper.value(for: 50, width: 100), 0.5, accuracy: 0.0001)
    }

    func test_valueForLocation_returnsZeroForNonPositiveWidth() {
        XCTAssertEqual(SliderValueMapper.value(for: 50, width: 0), 0)
    }

    func test_thumbCenterX_keepsThumbInsideTrackBounds() {
        XCTAssertEqual(SliderGeometry.thumbCenterX(for: -0.5, width: 100, thumbSize: 20), 10, accuracy: 0.0001)
        XCTAssertEqual(SliderGeometry.thumbCenterX(for: 0.5, width: 100, thumbSize: 20), 50, accuracy: 0.0001)
        XCTAssertEqual(SliderGeometry.thumbCenterX(for: 1.5, width: 100, thumbSize: 20), 90, accuracy: 0.0001)
    }

    func test_fillWidth_extendsToTrailingEdgeOfThumbAtMidpoint() {
        XCTAssertEqual(SliderGeometry.fillWidth(for: 0.5, width: 100, thumbSize: 20), 60, accuracy: 0.0001)
    }

    func test_fillWidth_clampsToTrackWidthAtFullVolume() {
        XCTAssertEqual(SliderGeometry.fillWidth(for: 1, width: 100, thumbSize: 20), 100, accuracy: 0.0001)
    }

    func test_percentageText_roundsDownToWholePercent() {
        XCTAssertEqual(SliderGeometry.percentageText(for: 0.426), "42%")
    }

    func test_percentageText_clampsToValidRange() {
        XCTAssertEqual(SliderGeometry.percentageText(for: -0.2), "0%")
        XCTAssertEqual(SliderGeometry.percentageText(for: 1.4), "100%")
    }

}
