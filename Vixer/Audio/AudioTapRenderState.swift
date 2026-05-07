import CoreAudio
import Foundation

/// IOProc-facing state shared across CoreAudio realtime callbacks and controller code.
/// Safe to mark Sendable because controls are protected by `AudioTapControlState`;
/// renderer access is limited to start/stop from controller lifecycle and realtime writes.
final class AudioTapRenderState: @unchecked Sendable {
    let controlState: AudioTapControlState

    private let makeupGain: Float
    private let renderer: TapOutputRenderer?

    init(
        controlState: AudioTapControlState,
        makeupGain: Float,
        renderer: TapOutputRenderer?
    ) {
        self.controlState = controlState
        self.makeupGain = makeupGain
        self.renderer = renderer
    }

    func startRenderer() throws {
        try renderer?.start()
    }

    func stopRenderer() {
        renderer?.stop()
    }

    func render(inputBuffers: UnsafePointer<AudioBufferList>, outputBuffers: UnsafeMutablePointer<AudioBufferList>) {
        let control = controlState.snapshot()
        let inABL = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBuffers))
        let outABL = UnsafeMutableAudioBufferListPointer(outputBuffers)
        let bufferCount = min(inABL.count, outABL.count)

        for i in 0..<bufferCount {
            let inBuf = inABL[i]
            let outBuf = outABL[i]
            guard let inData = inBuf.mData, let outData = outBuf.mData else { continue }

            let frames = Int(inBuf.mDataByteSize) / MemoryLayout<Float>.size
            let inP = inData.assumingMemoryBound(to: Float.self)
            let outP = outData.assumingMemoryBound(to: Float.self)

            for frame in 0..<frames {
                outP[frame] = AudioSampleProcessor.externalRendererSample(
                    input: inP[frame],
                    volume: control.volume,
                    muted: control.muted,
                    makeupGain: makeupGain
                )
            }

            renderer?.writeInterleaved(outP, sampleCount: frames)

            for frame in 0..<frames {
                outP[frame] = 0
            }
        }
    }
}
