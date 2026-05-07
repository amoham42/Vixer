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

    var volume: Float = 1.0
    var muted: Bool = false

    init(pid: pid_t, bundleID: String) throws {
        self.pid = pid
        self.bundleID = bundleID
        try createTap()
        try buildAggregateAndStart()
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
            let inputBufferList = inInputData.pointee
            let outputBufferList = outOutputData.pointee
            let bufferCount = min(inputBufferList.mNumberBuffers, outputBufferList.mNumberBuffers)
            withUnsafePointer(to: inputBufferList) { inPtr in
                withUnsafePointer(to: outputBufferList) { outPtr in
                    let inBuffers = UnsafeBufferPointer(
                        start: UnsafeRawPointer(inPtr).assumingMemoryBound(to: AudioBufferList.self).pointee.mBuffersAddr,
                        count: Int(bufferCount)
                    )
                    let outBuffers = UnsafeBufferPointer(
                        start: UnsafeRawPointer(outPtr).assumingMemoryBound(to: AudioBufferList.self).pointee.mBuffersAddr,
                        count: Int(bufferCount)
                    )
                    for i in 0..<Int(bufferCount) {
                        let input = inBuffers[i]
                        let output = outBuffers[i]
                        guard let inData = input.mData, let outData = output.mData else { continue }
                        let frames = Int(input.mDataByteSize) / MemoryLayout<Float>.size
                        let inP = inData.assumingMemoryBound(to: Float.self)
                        let outP = outData.assumingMemoryBound(to: Float.self)
                        for f in 0..<frames {
                            outP[f] = inP[f] * gain
                        }
                    }
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

    func teardown() {
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

// Helper used by the IOProc to get a typed pointer to AudioBufferList.mBuffers (a "flexible array").
// The system declares it as a 1-element fixed array; we reinterpret as a pointer to the first element.
private extension AudioBufferList {
    var mBuffersAddr: UnsafePointer<AudioBuffer> {
        withUnsafePointer(to: self) { listPtr in
            UnsafeRawPointer(listPtr)
                .advanced(by: MemoryLayout<UInt32>.size)
                .assumingMemoryBound(to: AudioBuffer.self)
        }
    }
}
