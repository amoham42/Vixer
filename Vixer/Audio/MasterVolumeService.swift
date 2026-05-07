import CoreAudio
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class MasterVolumeService {
    private static let log = Logger(subsystem: "com.armanmohammadi.Vixer", category: "MasterVolume")

    private(set) var volume: Float = 1.0
    private(set) var muted: Bool = false

    private var listenerBlocks: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var currentDeviceID: AudioObjectID = kAudioObjectUnknown

    init() {
        rebindToCurrentDefaultOutput()
        addDefaultDeviceListener()
    }

    isolated deinit {
        teardownListeners()
    }

    func setVolume(_ value: Float) {
        var v = UnitInterval.clamp(value)
        for ch in volumeChannels {
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
        var address = AudioObjectPropertyAddress.output(kAudioDevicePropertyMute)
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

    private var volumeChannels: [UInt32] {
        volumeRoute() == .master ? [kAudioObjectPropertyElementMain] : [1, 2]
    }

    private var primaryVolumeChannel: UInt32 { volumeChannels[0] }

    private func volumeRoute() -> VolumeRoute {
        var address = volumeAddress(channel: kAudioObjectPropertyElementMain)
        return AudioObjectHasProperty(currentDeviceID, &address) ? .master : .stereo
    }

    private func volumeAddress(channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress.output(kAudioDevicePropertyVolumeScalar, element: channel)
    }

    private func rebindToCurrentDefaultOutput() {
        teardownPerDeviceListeners()
        currentDeviceID = Self.defaultOutputDeviceID()
        readCurrentValues()
        addPerDeviceListeners()
    }

    private func readCurrentValues() {
        var address = volumeAddress(channel: primaryVolumeChannel)
        var v: Float = 1.0
        var size = UInt32(MemoryLayout<Float>.size)
        if AudioObjectGetPropertyData(currentDeviceID, &address, 0, nil, &size, &v) == noErr {
            volume = v
        }
        var muteAddress = AudioObjectPropertyAddress.output(kAudioDevicePropertyMute)
        var m: UInt32 = 0
        var msize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(currentDeviceID, &muteAddress, 0, nil, &msize, &m) == noErr {
            muted = m == 1
        }
    }

    private func addPerDeviceListeners() {
        for ch in volumeChannels {
            addListener(
                objectID: currentDeviceID,
                address: volumeAddress(channel: ch)
            ) { [weak self] in self?.readCurrentValues() }
        }

        addListener(
            objectID: currentDeviceID,
            address: AudioObjectPropertyAddress.output(kAudioDevicePropertyMute)
        ) { [weak self] in self?.readCurrentValues() }
    }

    private func addDefaultDeviceListener() {
        addListener(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: AudioObjectPropertyAddress.global(kAudioHardwarePropertyDefaultOutputDevice)
        ) { [weak self] in self?.rebindToCurrentDefaultOutput() }
    }

    private func addListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        handler: @escaping () -> Void
    ) {
        var addr = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in handler() }
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

    nonisolated static func defaultOutputDeviceID() -> AudioObjectID {
        var address = AudioObjectPropertyAddress.global(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &id
        )
        return id
    }

    nonisolated static func deviceUID(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress.global(kAudioDevicePropertyDeviceUID)
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? uid as String? : nil
    }
}
