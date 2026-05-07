import Testing
@testable import Vixer

struct VolumeSliderViewTests {
    @Test func valueForLocationClampsNegativePositionToZero() {
        #expect(SliderValueMapper.value(for: -12, width: 100) == 0)
    }

    @Test func valueForLocationClampsPastWidthToOne() {
        #expect(SliderValueMapper.value(for: 140, width: 100) == 1)
    }

    @Test func valueForLocationMapsMidpointToHalf() {
        #expect(abs(SliderValueMapper.value(for: 50, width: 100) - 0.5) <= 0.0001)
    }

    @Test func valueForLocationReturnsZeroForNonPositiveWidth() {
        #expect(SliderValueMapper.value(for: 50, width: 0) == 0)
    }

    @Test func thumbCenterXKeepsThumbInsideTrackBounds() {
        #expect(abs(SliderGeometry.thumbCenterX(for: -0.5, width: 100, thumbSize: 20) - 10) <= 0.0001)
        #expect(abs(SliderGeometry.thumbCenterX(for: 0.5, width: 100, thumbSize: 20) - 50) <= 0.0001)
        #expect(abs(SliderGeometry.thumbCenterX(for: 1.5, width: 100, thumbSize: 20) - 90) <= 0.0001)
    }

    @Test func fillWidthExtendsToTrailingEdgeOfThumbAtMidpoint() {
        #expect(abs(SliderGeometry.fillWidth(for: 0.5, width: 100, thumbSize: 20) - 60) <= 0.0001)
    }

    @Test func fillWidthClampsToTrackWidthAtFullVolume() {
        #expect(abs(SliderGeometry.fillWidth(for: 1, width: 100, thumbSize: 20) - 100) <= 0.0001)
    }

    @Test func percentageTextRoundsDownToWholePercent() {
        #expect(SliderGeometry.percentageText(for: 0.426) == "42%")
    }

    @Test func percentageTextClampsToValidRange() {
        #expect(SliderGeometry.percentageText(for: -0.2) == "0%")
        #expect(SliderGeometry.percentageText(for: 1.4) == "100%")
    }
}
