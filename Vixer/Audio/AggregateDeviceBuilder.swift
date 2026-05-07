import CoreAudio
import Foundation

enum AggregateDeviceBuilder {
    /// Creates a private aggregate device that pairs the given tap with the given output device.
    /// Returns the aggregate device's AudioObjectID.
    static func create(
        tapUID: String,
        outputDeviceUID: String,
        name: String
    ) throws -> AudioObjectID {
        // Tap is the MAIN sub-device — its clock drives the IO loop. With the output device as
        // main, Sequoia won't actually start IO (AudioDeviceStart returns noErr but IsRunning=0).
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: tapUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUID
                ]
            ]
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else {
            throw AudioTapError.aggregateDeviceCreationFailed(status: status)
        }
        return aggregateID
    }

    static func destroy(_ aggregateID: AudioObjectID) {
        guard aggregateID != kAudioObjectUnknown else { return }
        AudioHardwareDestroyAggregateDevice(aggregateID)
    }
}
