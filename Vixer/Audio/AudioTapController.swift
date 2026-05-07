import CoreAudio
import Foundation
import OSLog

final class AudioTapController {
    enum TapMode: Equatable, Sendable {
        case deviceStream(stream: Int, makeupGain: Float)
    }

    private static let log = Logger(subsystem: "com.armanmohammadi.Vixer", category: "AudioTap")

    let pid: pid_t
    let bundleID: String
    let tapMode: TapMode

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var tapUID: String = ""
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var externalRenderer: TapOutputRenderer?
    private var defaultDeviceListenerInstalled = false
    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceAddress = AudioObjectPropertyAddress.global(kAudioHardwarePropertyDefaultOutputDevice)

    private let controlState = AudioTapControlState()
    private var ioProcLogged = false
    private var peakProbeRemaining = 100

    private var externalRendererMakeupGain: Float {
        switch tapMode {
        case .deviceStream(_, let makeupGain):
            return makeupGain
        }
    }

    /// Logged once per controller (from inside the realtime IOProc) so we can confirm the
    /// IOProc is actually being called. Subsequent calls are no-ops to keep the audio thread cheap.
    fileprivate func noteIOProcOnce(inputBuffers: Int, outputBuffers: Int) {
        if ioProcLogged { return }
        ioProcLogged = true
        let bid = bundleID
        DispatchQueue.global(qos: .utility).async {
            Self.log.info("IOProc fired bundleID=\(bid, privacy: .public) inBufs=\(inputBuffers, privacy: .public) outBufs=\(outputBuffers, privacy: .public)")
        }
    }

    fileprivate func noteInputPeakIfNeeded(_ peak: Float, gain: Float) {
        guard peakProbeRemaining > 0 else { return }
        peakProbeRemaining -= 1
        guard peak > 0.0001 || peakProbeRemaining == 0 else { return }
        peakProbeRemaining = 0
        let bid = bundleID
        DispatchQueue.global(qos: .utility).async {
            Self.log.info("Tap input peak bundleID=\(bid, privacy: .public) peak=\(peak, privacy: .public) gain=\(gain, privacy: .public)")
        }
    }

    init(pid: pid_t, bundleID: String, tapMode: TapMode = .deviceStream(stream: 0, makeupGain: 1)) throws {
        self.pid = pid
        self.bundleID = bundleID
        self.tapMode = tapMode
        Self.log.info("Installing tap pid=\(pid, privacy: .public) bundleID=\(bundleID, privacy: .public) mode=\(String(describing: tapMode), privacy: .public)")
        try createTapAndAggregateForCurrentOutput()
        installDefaultDeviceListener()
    }

    deinit { teardown() }

    func setVolume(_ value: Float) { controlState.setVolume(value) }
    func setMuted(_ value: Bool) { controlState.setMuted(value) }

    // MARK: - tap creation

    private func createTap(outputDeviceUID: String) throws {
        let processObjectID = try Self.audioObjectID(forPID: pid)
        let stream: Int
        switch tapMode {
        case .deviceStream(let configuredStream, _):
            stream = configuredStream
        }
        // Binding the tap to the output device stream captures process audio destined for
        // the current route. FaceTime/CallKit gets extra makeup gain; regular apps use unity gain.
        let description = CATapDescription(
            __processes: [NSNumber(value: processObjectID)],
            andDeviceUID: outputDeviceUID,
            withStream: stream
        )
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        description.name = "Vixer-\(bundleID)"

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw AudioTapError.tapCreationFailed(status: status) }
        tapID = newTapID
        tapUID = description.uuid.uuidString

        // Diagnostic: query the tap's stream format. If the tap was created but isn't actually
        // receiving audio (e.g. TCC denied at runtime), the format is zero-filled.
        var fmtAddr = AudioObjectPropertyAddress.global(kAudioTapPropertyFormat)
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let fmtStatus = AudioObjectGetPropertyData(newTapID, &fmtAddr, 0, nil, &asbdSize, &asbd)
        Self.log.info("Tap format for \(self.bundleID, privacy: .public): status=\(fmtStatus, privacy: .public) sr=\(asbd.mSampleRate, privacy: .public) ch=\(asbd.mChannelsPerFrame, privacy: .public) bits=\(asbd.mBitsPerChannel, privacy: .public) flags=\(asbd.mFormatFlags, privacy: .public)")

        if fmtStatus == noErr {
            externalRenderer = try TapOutputRenderer(
                sampleRate: asbd.mSampleRate,
                channelCount: asbd.mChannelsPerFrame
            )
            try externalRenderer?.start()
        }
    }

    // MARK: - aggregate + IOProc

    private func createTapAndAggregateForCurrentOutput() throws {
        let outputID = MasterVolumeService.defaultOutputDeviceID()
        guard let outputUID = MasterVolumeService.deviceUID(outputID) else {
            throw AudioTapError.aggregateDeviceCreationFailed(status: -1)
        }
        try createTap(outputDeviceUID: outputUID)
        Self.log.info("Tap created tapID=\(self.tapID, privacy: .public) for \(self.bundleID, privacy: .public) outputUID=\(outputUID, privacy: .public)")
        try buildAggregateAndStart(outputDeviceUID: outputUID)
        Self.log.info("Aggregate started aggregateID=\(self.aggregateID, privacy: .public) for \(self.bundleID, privacy: .public)")
    }

    private func buildAggregateAndStart(outputDeviceUID: String) throws {
        aggregateID = try AggregateDeviceBuilder.create(
            tapUID: tapUID,
            outputDeviceUID: outputDeviceUID,
            name: "Vixer-Agg-\(bundleID)"
        )
        try installIOProc()
        try startIO()
    }

    private func installIOProc() throws {
        var procID: AudioDeviceIOProcID?
        // nil queue = run on CoreAudio's realtime audio thread. Passing main here would
        // dispatch the block to the UI runloop, which never fires at audio rate.
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateID,
            nil
        ) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self = self else { return }
            let control = self.controlState.snapshot()
            let gain: Float = control.muted ? 0.0 : control.volume
            let inABL  = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let outABL = UnsafeMutableAudioBufferListPointer(outOutputData)
            let n = min(inABL.count, outABL.count)
            self.noteIOProcOnce(inputBuffers: inABL.count, outputBuffers: outABL.count)
            for i in 0..<n {
                let inBuf = inABL[i]
                let outBuf = outABL[i]
                guard let inData = inBuf.mData, let outData = outBuf.mData else { continue }
                let frames = Int(inBuf.mDataByteSize) / MemoryLayout<Float>.size
                let inP = inData.assumingMemoryBound(to: Float.self)
                let outP = outData.assumingMemoryBound(to: Float.self)
                var peak: Float = 0
                for f in 0..<frames {
                    let sample = inP[f]
                    if self.peakProbeRemaining > 0 {
                        peak = max(peak, abs(sample))
                    }
                    outP[f] = AudioSampleProcessor.externalRendererSample(
                        input: sample,
                        volume: control.volume,
                        muted: control.muted,
                        makeupGain: self.externalRendererMakeupGain
                    )
                }
                self.externalRenderer?.writeInterleaved(outP, sampleCount: frames)
                for f in 0..<frames {
                    outP[f] = 0
                }
                if self.peakProbeRemaining > 0 {
                    self.noteInputPeakIfNeeded(peak, gain: gain)
                }
            }
        }
        guard status == noErr, procID != nil else {
            throw AudioTapError.ioProcCreationFailed(status: status)
        }
        ioProcID = procID
    }

    private func startIO() throws {
        guard let procID = ioProcID else { return }
        let status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            throw AudioTapError.ioProcCreationFailed(status: status)
        }
        Self.probeIsRunning(aggregateID: aggregateID, label: "immediate", bundleID: bundleID)
        let bid = bundleID
        let aid = aggregateID
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            Self.probeIsRunning(aggregateID: aid, label: "+500ms", bundleID: bid)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
            Self.probeIsRunning(aggregateID: aid, label: "+2s", bundleID: bid)
        }
    }

    private static func probeIsRunning(aggregateID: AudioObjectID, label: String, bundleID: String) {
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress.global(kAudioDevicePropertyDeviceIsRunning)
        let s = AudioObjectGetPropertyData(aggregateID, &addr, 0, nil, &size, &isRunning)
        log.info("IsRunning [\(label, privacy: .public)] for \(bundleID, privacy: .public): status=\(s, privacy: .public) running=\(isRunning, privacy: .public)")
    }

    private func stopIO() {
        guard let procID = ioProcID else { return }
        AudioDeviceStop(aggregateID, procID)
        AudioDeviceDestroyIOProcID(aggregateID, procID)
        ioProcID = nil
    }

    private func installDefaultDeviceListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDefaultOutputChanged()
        }
        self.defaultDeviceBlock = block
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress, .main, block
        )
        if status == noErr { defaultDeviceListenerInstalled = true }
    }

    private func handleDefaultOutputChanged() {
        Self.log.debug("Default output changed; rebuilding aggregate for \(self.bundleID, privacy: .public)")
        stopIO()
        AggregateDeviceBuilder.destroy(aggregateID)
        aggregateID = kAudioObjectUnknown
        externalRenderer?.stop()
        externalRenderer = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            tapUID = ""
        }
        ioProcLogged = false
        peakProbeRemaining = 100
        do {
            try createTapAndAggregateForCurrentOutput()
        } catch {
            Self.log.error("Rebuild failed: \(String(describing: error), privacy: .public)")
        }
    }

    func teardown() {
        if defaultDeviceListenerInstalled, let block = defaultDeviceBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultDeviceAddress, .main, block
            )
            defaultDeviceListenerInstalled = false
            defaultDeviceBlock = nil
        }
        stopIO()
        externalRenderer?.stop()
        externalRenderer = nil
        AggregateDeviceBuilder.destroy(aggregateID)
        aggregateID = kAudioObjectUnknown
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    // MARK: - PID translation

    static func audioObjectID(forPID pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress.global(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var input = pid
        var output = AudioObjectID(kAudioObjectUnknown)
        var outputSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &input,
            &outputSize,
            &output
        )
        guard status == noErr else {
            throw AudioTapError.pidTranslationFailed(status: status, pid: pid)
        }
        return output
    }
}

enum AudioTapError: Error {
    case pidTranslationFailed(status: OSStatus, pid: pid_t)
    case tapCreationFailed(status: OSStatus)
    case aggregateDeviceCreationFailed(status: OSStatus)
    case ioProcCreationFailed(status: OSStatus)
    case rendererCreationFailed(status: OSStatus)
    case rendererStartFailed(status: OSStatus)

    var status: OSStatus {
        switch self {
        case .pidTranslationFailed(let status, _),
             .tapCreationFailed(let status),
             .aggregateDeviceCreationFailed(let status),
             .ioProcCreationFailed(let status),
             .rendererCreationFailed(let status),
             .rendererStartFailed(let status):
            return status
        }
    }
}

