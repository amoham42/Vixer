import os.lock

struct AudioTapControlSnapshot: Sendable, Equatable {
    let volume: Float
    let muted: Bool
}

final class AudioTapControlState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: AudioTapControlSnapshot(volume: 1.0, muted: false))

    func snapshot() -> AudioTapControlSnapshot {
        lock.withLock { $0 }
    }

    func setVolume(_ value: Float) {
        lock.withLock { snapshot in
            snapshot = AudioTapControlSnapshot(volume: UnitInterval.clamp(value), muted: snapshot.muted)
        }
    }

    func setMuted(_ value: Bool) {
        lock.withLock { snapshot in
            snapshot = AudioTapControlSnapshot(volume: snapshot.volume, muted: value)
        }
    }

    func set(volume: Float, muted: Bool) {
        lock.withLock { snapshot in
            snapshot = AudioTapControlSnapshot(volume: UnitInterval.clamp(volume), muted: muted)
        }
    }
}
