import CoreAudio
import Foundation
import OSLog
import os.lock

/// IOProc-facing state shared across CoreAudio realtime callbacks and controller code.
/// Safe to mark Sendable because control and diagnostic mutation is protected by locks;
/// renderer access is limited to start/stop from controller lifecycle and realtime writes.
final class AudioTapRenderState: @unchecked Sendable {
    private struct Diagnostics: Sendable {
        var ioProcLogged = false
        var peakProbeRemaining = 100
    }

    let controlState = AudioTapControlState()

    private let makeupGain: Float
    private let bundleID: String
    private let logger: Logger
    private let renderer: TapOutputRenderer?
    private let diagnostics = OSAllocatedUnfairLock(initialState: Diagnostics())

    init(
        bundleID: String,
        makeupGain: Float,
        renderer: TapOutputRenderer?,
        logger: Logger = Logger(subsystem: "com.armanmohammadi.Vixer", category: "AudioTap")
    ) {
        self.bundleID = bundleID
        self.makeupGain = makeupGain
        self.renderer = renderer
        self.logger = logger
    }

    func startRenderer() throws {
        try renderer?.start()
    }

    func stopRenderer() {
        renderer?.stop()
    }

    func resetDiagnostics() {
        diagnostics.withLock { state in
            state = Diagnostics()
        }
    }

    func render(inputBuffers: UnsafePointer<AudioBufferList>, outputBuffers: UnsafeMutablePointer<AudioBufferList>) {
        let control = controlState.snapshot()
        let gain: Float = control.muted ? 0.0 : control.volume
        let inABL = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBuffers))
        let outABL = UnsafeMutableAudioBufferListPointer(outputBuffers)
        let bufferCount = min(inABL.count, outABL.count)

        noteIOProcOnce(inputBuffers: inABL.count, outputBuffers: outABL.count)

        for i in 0..<bufferCount {
            let inBuf = inABL[i]
            let outBuf = outABL[i]
            guard let inData = inBuf.mData, let outData = outBuf.mData else { continue }

            let frames = Int(inBuf.mDataByteSize) / MemoryLayout<Float>.size
            let inP = inData.assumingMemoryBound(to: Float.self)
            let outP = outData.assumingMemoryBound(to: Float.self)
            let shouldProbePeak = shouldProbePeak()
            var peak: Float = 0

            for frame in 0..<frames {
                let sample = inP[frame]
                if shouldProbePeak {
                    peak = max(peak, abs(sample))
                }
                outP[frame] = AudioSampleProcessor.externalRendererSample(
                    input: sample,
                    volume: control.volume,
                    muted: control.muted,
                    makeupGain: makeupGain
                )
            }

            renderer?.writeInterleaved(outP, sampleCount: frames)

            for frame in 0..<frames {
                outP[frame] = 0
            }

            if shouldProbePeak {
                noteInputPeakIfNeeded(peak, gain: gain)
            }
        }
    }

    private func shouldProbePeak() -> Bool {
        diagnostics.withLock { state in
            state.peakProbeRemaining > 0
        }
    }

    /// Logged once per render state (from inside the realtime IOProc) so we can confirm the
    /// IOProc is actually being called. Subsequent calls are no-ops to keep the audio thread cheap.
    private func noteIOProcOnce(inputBuffers: Int, outputBuffers: Int) {
        let shouldLog = diagnostics.withLock { state in
            guard !state.ioProcLogged else { return false }
            state.ioProcLogged = true
            return true
        }
        guard shouldLog else { return }

        let bid = bundleID
        let logger = logger
        DispatchQueue.global(qos: .utility).async {
            logger.info("IOProc fired bundleID=\(bid, privacy: .public) inBufs=\(inputBuffers, privacy: .public) outBufs=\(outputBuffers, privacy: .public)")
        }
    }

    private func noteInputPeakIfNeeded(_ peak: Float, gain: Float) {
        let shouldLog = diagnostics.withLock { state in
            guard state.peakProbeRemaining > 0 else { return false }
            state.peakProbeRemaining -= 1
            guard peak > 0.0001 || state.peakProbeRemaining == 0 else { return false }
            state.peakProbeRemaining = 0
            return true
        }
        guard shouldLog else { return }

        let bid = bundleID
        let logger = logger
        DispatchQueue.global(qos: .utility).async {
            logger.info("Tap input peak bundleID=\(bid, privacy: .public) peak=\(peak, privacy: .public) gain=\(gain, privacy: .public)")
        }
    }
}
