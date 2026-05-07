import XCTest
@testable import Vixer

final class AudioSampleProcessorTests: XCTestCase {
    func test_externalRendererSample_appliesFaceTimeMakeupGainOf100ToLowLevelCallAudio() {
        let output = AudioSampleProcessor.externalRendererSample(
            input: 0.001,
            volume: 0.5,
            muted: false,
            makeupGain: 100
        )

        XCTAssertEqual(output, tanh(0.05), accuracy: 0.000001)
    }

    func test_externalRendererSample_canUseUnityMakeupGainForRegularApps() {
        let output = AudioSampleProcessor.externalRendererSample(
            input: 0.5,
            volume: 0.5,
            muted: false,
            makeupGain: 1
        )

        XCTAssertEqual(output, tanh(0.25), accuracy: 0.000001)
    }

    func test_externalRendererSample_limitsLargeSamples() {
        let output = AudioSampleProcessor.externalRendererSample(
            input: 1.0,
            volume: 1.0,
            muted: false,
            makeupGain: 100
        )

        XCTAssertLessThanOrEqual(output, 1.0)
    }

    func test_externalRendererSample_returnsZeroWhenMuted() {
        let output = AudioSampleProcessor.externalRendererSample(
            input: 0.5,
            volume: 1.0,
            muted: true,
            makeupGain: 100
        )

        XCTAssertEqual(output, 0)
    }
}
