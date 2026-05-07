import Foundation
import Testing
@testable import Vixer

struct AppVolumeStateTests {
    @Test func defaultIsFullVolumeAndUnmuted() {
        let state = AppVolumeState()
        #expect(state.volume == 1.0)
        #expect(state.muted == false)
    }

    @Test func isPassthroughWhenFullVolumeAndUnmuted() {
        #expect(AppVolumeState(volume: 1.0, muted: false).isPassthrough)
        #expect(AppVolumeState(volume: 0.5, muted: false).isPassthrough == false)
        #expect(AppVolumeState(volume: 1.0, muted: true).isPassthrough == false)
    }

    @Test func codableRoundTrip() throws {
        let original = AppVolumeState(volume: 0.42, muted: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppVolumeState.self, from: data)
        #expect(abs(decoded.volume - 0.42) <= 0.0001)
        #expect(decoded.muted == true)
    }

    @Test func volumeIsClamped() {
        #expect(AppVolumeState(volume: 2.0, muted: false).volume == 1.0)
        #expect(AppVolumeState(volume: -0.5, muted: false).volume == 0.0)
    }
}
