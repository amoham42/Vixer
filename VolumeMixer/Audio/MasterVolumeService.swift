import CoreAudio
import Foundation
import Observation
import OSLog

@Observable
final class MasterVolumeService {
    private static let log = Logger(subsystem: "com.armanmohammadi.VolumeMixer", category: "MasterVolume")

    private(set) var volume: Float = 1.0
    private(set) var muted: Bool = false

    private var listenerBlocks: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private var currentDeviceID: AudioObjectID = kAudioObjectUnknown

    init() {
        rebindToCurrentDefaultOutput()
        addDefaultDeviceListener()
    }

    deinit {
        teardownListeners()
    }

    func setVolume(_ value: Float) {
        var v = max(0.0, min(1.0, value))
        var address = volumeAddress(channel: preferredChannel())
        let status = AudioObjectSetPropertyData(
            currentDeviceID, &address, 0, nil,
            UInt32(MemoryLayout<Float>.size), &v
        )
        if status != noErr {
            Self.log.error("setVolume failed status=\(status)")
        }
    }

    func setMuted(_ value: Bool) {
        var m: UInt32 = value ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            currentDeviceID, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &m
        )
        if status != noErr {
            Self.log.error("setMuted failed status=\(status)")
        }
    }

    // MARK: - private

    private func preferredChannel() -> UInt32 {
        var address = volumeAddress(channel: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(currentDeviceID, &address) { return kAudioObjectPropertyElementMain }
        return 1 // fall back to channel 1 (left)
    }

    private func volumeAddress(channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
    }

    private func rebindToCurrentDefaultOutput() {
        teardownPerDeviceListeners()
        currentDeviceID = Self.defaultOutputDeviceID()
        readCurrentValues()
        addPerDeviceListeners()
    }

    private func readCurrentValues() {
        // volume
        var address = volumeAddress(channel: preferredChannel())
        var v: Float = 1.0
        var size = UInt32(MemoryLayout<Float>.size)
        if AudioObjectGetPropertyData(currentDeviceID, &address, 0, nil, &size, &v) == noErr {
            volume = v
        }
        // mute
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var m: UInt32 = 0
        var msize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(currentDeviceID, &muteAddress, 0, nil, &msize, &m) == noErr {
            muted = m == 1
        }
    }

    private func addPerDeviceListeners() {
        addListener(
            objectID: currentDeviceID,
            address: volumeAddress(channel: preferredChannel())
        ) { [weak self] in self?.readCurrentValues() }

        addListener(
            objectID: currentDeviceID,
            address: AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
        ) { [weak self] in self?.readCurrentValues() }
    }

    private func addDefaultDeviceListener() {
        addListener(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        ) { [weak self] in self?.rebindToCurrentDefaultOutput() }
    }

    private func addListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        handler: @escaping () -> Void
    ) {
        var addr = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { handler() }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &addr, .main, block)
        if status == noErr {
            listenerBlocks.append((objectID, addr))
        } else {
            Self.log.error("addPropertyListener failed status=\(status)")
        }
    }

    private func teardownListeners() {
        for (id, addr) in listenerBlocks {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(id, &a, .main) { _, _ in }
        }
        listenerBlocks.removeAll()
    }

    private func teardownPerDeviceListeners() {
        listenerBlocks.removeAll { entry in
            entry.0 == currentDeviceID
        }
    }

    static func defaultOutputDeviceID() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &id
        )
        return id
    }

    static func deviceUID(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { ptr -> OSStatus in
            ptr.withMemoryRebound(to: UInt8.self, capacity: Int(size)) { raw in
                AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw)
            }
        }
        return status == noErr ? uid as String? : nil
    }
}
