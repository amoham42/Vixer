import CoreAudio
import Foundation
import Observation
import OSLog

@Observable
final class MasterVolumeService {
    private static let log = Logger(subsystem: "com.armanmohammadi.VolumeMixer", category: "MasterVolume")

    private(set) var volume: Float = 1.0
    private(set) var muted: Bool = false

    private var listenerBlocks: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
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
        let channels: [UInt32]
        switch volumeRoute() {
        case .master: channels = [kAudioObjectPropertyElementMain]
        case .stereo: channels = [1, 2]
        }
        for ch in channels {
            var address = volumeAddress(channel: ch)
            let status = AudioObjectSetPropertyData(
                currentDeviceID, &address, 0, nil,
                UInt32(MemoryLayout<Float>.size), &v
            )
            if status != noErr {
                Self.log.error("setVolume ch=\(ch) failed status=\(status)")
            }
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

    private enum VolumeRoute { case master, stereo }

    private func volumeRoute() -> VolumeRoute {
        var address = volumeAddress(channel: kAudioObjectPropertyElementMain)
        return AudioObjectHasProperty(currentDeviceID, &address) ? .master : .stereo
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
        let readChannel: UInt32
        switch volumeRoute() {
        case .master: readChannel = kAudioObjectPropertyElementMain
        case .stereo: readChannel = 1
        }
        var address = volumeAddress(channel: readChannel)
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
        let volumeChannels: [UInt32]
        switch volumeRoute() {
        case .master: volumeChannels = [kAudioObjectPropertyElementMain]
        case .stereo: volumeChannels = [1, 2]
        }
        for ch in volumeChannels {
            addListener(
                objectID: currentDeviceID,
                address: volumeAddress(channel: ch)
            ) { [weak self] in self?.readCurrentValues() }
        }

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
            listenerBlocks.append((objectID, addr, block))
        } else {
            Self.log.error("addPropertyListener failed status=\(status)")
        }
    }

    private func teardownListeners() {
        for (id, addr, block) in listenerBlocks {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(id, &a, .main, block)
        }
        listenerBlocks.removeAll()
    }

    private func teardownPerDeviceListeners() {
        let toRemove = listenerBlocks.filter { $0.0 == currentDeviceID }
        for (id, addr, block) in toRemove {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(id, &a, .main, block)
        }
        listenerBlocks.removeAll { $0.0 == currentDeviceID }
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
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid)
        return status == noErr ? uid as String? : nil
    }
}
