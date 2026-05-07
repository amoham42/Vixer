import Foundation

struct AppVolumeState: Codable, Equatable {
    let volume: Float
    let muted: Bool

    init(volume: Float = 1.0, muted: Bool = false) {
        self.volume = max(0.0, min(1.0, volume))
        self.muted = muted
    }

    var isPassthrough: Bool { volume == 1.0 && !muted }

    func with(volume: Float) -> AppVolumeState { .init(volume: volume, muted: muted) }
    func with(muted: Bool) -> AppVolumeState { .init(volume: volume, muted: muted) }
}
