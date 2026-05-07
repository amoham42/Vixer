import CoreAudio
import Foundation
import OSLog

final class AudioTapController {
    private static let log = Logger(subsystem: "com.armanmohammadi.VolumeMixer", category: "AudioTap")

    let pid: pid_t
    let bundleID: String

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var tapUID: String = ""
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var defaultDeviceListenerInstalled = false
    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var volume: Float = 1.0
    var muted: Bool = false

    init(pid: pid_t, bundleID: String) throws {
        self.pid = pid
        self.bundleID = bundleID
        try createTap()
        try buildAggregateAndStart()
        installDefaultDeviceListener()
    }

    deinit { teardown() }

    func setVolume(_ value: Float) { volume = max(0.0, min(1.0, value)) }
    func setMuted(_ value: Bool) { muted = value }

    // MARK: - tap creation

    private func createTap() throws {
        let processObjectID = try Self.audioObjectID(forPID: pid)
        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        description.name = "VolumeMixer-\(bundleID)"

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw AudioTapError.tapCreationFailed(status: status) }
        tapID = newTapID
        tapUID = description.uuid.uuidString
    }

    // MARK: - aggregate + IOProc

    private func buildAggregateAndStart() throws {
        let outputID = MasterVolumeService.defaultOutputDeviceID()
        guard let outputUID = MasterVolumeService.deviceUID(outputID) else {
            throw AudioTapError.aggregateDeviceCreationFailed(status: -1)
        }
        aggregateID = try AggregateDeviceBuilder.create(
            tapUID: tapUID,
            outputDeviceUID: outputUID,
            name: "VolumeMixer-Agg-\(bundleID)"
        )
        try installIOProc()
        try startIO()
    }

    private func installIOProc() throws {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateID,
            DispatchQueue.main // documentation-only; the block runs on the realtime audio thread
        ) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self = self else { return }
            let gain: Float = self.muted ? 0.0 : self.volume
            let inABL  = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let outABL = UnsafeMutableAudioBufferListPointer(outOutputData)
            let n = min(inABL.count, outABL.count)
            for i in 0..<n {
                let inBuf = inABL[i]
                let outBuf = outABL[i]
                guard let inData = inBuf.mData, let outData = outBuf.mData else { continue }
                let frames = Int(inBuf.mDataByteSize) / MemoryLayout<Float>.size
                let inP = inData.assumingMemoryBound(to: Float.self)
                let outP = outData.assumingMemoryBound(to: Float.self)
                for f in 0..<frames {
                    outP[f] = inP[f] * gain
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
    }

    private func stopIO() {
        guard let procID = ioProcID else { return }
        AudioDeviceStop(aggregateID, procID)
        AudioDeviceDestroyIOProcID(aggregateID, procID)
        ioProcID = nil
    }

    private func installDefaultDeviceListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.handleDefaultOutputChanged() }
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
        do {
            try buildAggregateAndStart()
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
        AggregateDeviceBuilder.destroy(aggregateID)
        aggregateID = kAudioObjectUnknown
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    // MARK: - PID translation

    static func audioObjectID(forPID pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
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
}

