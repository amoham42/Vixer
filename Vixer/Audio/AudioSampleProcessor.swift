import Foundation

enum AudioSampleProcessor {
    /// Device-stream taps can expose route-specific levels. FaceTime/CallKit needs substantial
    /// makeup gain, while regular apps like Chrome should use unity gain to avoid distortion.
    static func externalRendererSample(input: Float, volume: Float, muted: Bool, makeupGain: Float) -> Float {
        guard !muted else { return 0 }
        let safeMakeupGain = max(0, makeupGain)
        let gained = input * UnitInterval.clamp(volume) * safeMakeupGain
        return softLimit(gained)
    }

    private static func softLimit(_ value: Float) -> Float {
        tanh(value)
    }
}
