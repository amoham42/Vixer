import Darwin
import Testing
@testable import Vixer

struct AudioSampleProcessorTests {
    @Test func externalRendererSampleAppliesFaceTimeMakeupGainOf100ToLowLevelCallAudio() {
        let output = AudioSampleProcessor.externalRendererSample(
            input: 0.001,
            volume: 0.5,
            muted: false,
            makeupGain: 100
        )

        #expect(abs(output - tanh(0.05)) <= 0.000001)
    }

    @Test func externalRendererSampleCanUseUnityMakeupGainForRegularApps() {
        let output = AudioSampleProcessor.externalRendererSample(
            input: 0.5,
            volume: 0.5,
            muted: false,
            makeupGain: 1
        )

        #expect(abs(output - tanh(0.25)) <= 0.000001)
    }

    @Test func externalRendererSampleLimitsLargeSamples() {
        let output = AudioSampleProcessor.externalRendererSample(
            input: 1.0,
            volume: 1.0,
            muted: false,
            makeupGain: 100
        )

        #expect(output <= 1.0)
    }

    @Test func externalRendererSampleReturnsZeroWhenMuted() {
        let output = AudioSampleProcessor.externalRendererSample(
            input: 0.5,
            volume: 1.0,
            muted: true,
            makeupGain: 100
        )

        #expect(output == 0)
    }
}
