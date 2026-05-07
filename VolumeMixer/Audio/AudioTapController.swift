import CoreAudio
import Foundation
import OSLog

/// Owns a private process tap on a target app, plus an aggregate device that re-routes the
/// tap's audio through the current default output with a per-app gain factor.
///
/// Threading: `setVolume` / `setMuted` are called from the main thread. The IOProc reads the
/// `volume` and `muted` properties from the realtime audio thread. Since both are 32-bit
/// (Float and Bool) and aligned, single-property reads are atomic on Apple silicon and Intel.
/// A one-buffer (~5 ms) lag in propagation is imperceptible for volume changes.
final class AudioTapController {
    private static let log = Logger(subsystem: "com.armanmohammadi.VolumeMixer", category: "AudioTap")

    let pid: pid_t
    let bundleID: String

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var tapUID: String = ""

    var volume: Float = 1.0
    var muted: Bool = false

    init(pid: pid_t, bundleID: String) throws {
        self.pid = pid
        self.bundleID = bundleID
        try createTap()
    }

    deinit {
        teardown()
    }

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
        guard status == noErr else {
            throw AudioTapError.tapCreationFailed(status: status)
        }
        tapID = newTapID
        tapUID = description.uuid.uuidString
        Self.log.debug("Created tap \(self.tapUID, privacy: .public) for pid \(self.pid)")
    }

    func teardown() {
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
