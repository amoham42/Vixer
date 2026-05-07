import Testing
@testable import Vixer

struct AudioTapControlStateTests {
    @Test func defaultSnapshotUsesFullVolumeAndUnmuted() {
        let state = AudioTapControlState()

        let snapshot = state.snapshot()

        #expect(snapshot.volume == 1.0)
        #expect(snapshot.muted == false)
    }

    @Test func setVolumeClampsToUnitInterval() {
        let state = AudioTapControlState()

        state.setVolume(1.5)
        #expect(state.snapshot().volume == 1.0)

        state.setVolume(-0.25)
        #expect(state.snapshot().volume == 0.0)
    }

    @Test func setMutedUpdatesSnapshot() {
        let state = AudioTapControlState()

        state.setMuted(true)

        #expect(state.snapshot().muted == true)
    }

    @Test func setSnapshotUpdatesVolumeAndMutedTogether() {
        let state = AudioTapControlState()

        state.set(volume: 0.25, muted: true)

        let snapshot = state.snapshot()
        #expect(snapshot.volume == 0.25)
        #expect(snapshot.muted == true)
    }
}
