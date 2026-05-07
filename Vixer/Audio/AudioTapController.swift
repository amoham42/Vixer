import CoreAudio
import Foundation
import OSLog

final class AudioTapController {
    enum TapMode: Equatable, Sendable {
        case deviceStream(stream: Int, makeupGain: Float)
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Vixer", category: "AudioTap")

    let pid: pid_t
    let bundleID: String
    let tapMode: TapMode

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var tapUID: String = ""
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var renderState: AudioTapRenderState?
    private let controlState = AudioTapControlState()
    private var defaultDeviceListenerInstalled = false
    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceAddress = AudioObjectPropertyAddress.global(kAudioHardwarePropertyDefaultOutputDevice)

    private var externalRendererMakeupGain: Float {
        switch tapMode {
        case .deviceStream(_, let makeupGain):
            return makeupGain
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

        let renderer: TapOutputRenderer?
        if fmtStatus == noErr {
            renderer = try TapOutputRenderer(
                sampleRate: asbd.mSampleRate,
                channelCount: asbd.mChannelsPerFrame
            )
        } else {
            renderer = nil
        }
        let newRenderState = AudioTapRenderState(
            controlState: controlState,
            makeupGain: externalRendererMakeupGain,
            renderer: renderer
        )
        try newRenderState.startRenderer()
        renderState = newRenderState
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
        let renderState = renderState
        // nil queue = run on CoreAudio's realtime audio thread. Passing main here would
        // dispatch the block to the UI runloop, which never fires at audio rate.
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateID,
            nil
        ) { _, inInputData, _, outOutputData, _ in
            renderState?.render(inputBuffers: inInputData, outputBuffers: outOutputData)
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
        renderState?.stopRenderer()
        renderState = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            tapUID = ""
        }
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
        renderState?.stopRenderer()
        renderState = nil
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

