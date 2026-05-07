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

    @Test func renderStatesUseInjectedControlState() {
        let state = AudioTapControlState()
        state.set(volume: 0.35, muted: true)

        let firstRenderState = AudioTapRenderState(
            controlState: state,
            makeupGain: 1,
            renderer: nil
        )
        let secondRenderState = AudioTapRenderState(
            controlState: state,
            makeupGain: 1,
            renderer: nil
        )

        firstRenderState.controlState.set(volume: 0.7, muted: false)

        let firstSnapshot = firstRenderState.controlState.snapshot()
        let secondSnapshot = secondRenderState.controlState.snapshot()
        #expect(firstSnapshot.volume == 0.7)
        #expect(firstSnapshot.muted == false)
        #expect(secondSnapshot.volume == 0.7)
        #expect(secondSnapshot.muted == false)
    }

    @Test
    func concurrentUpdatesKeepSnapshotsValid() async {
        let state = AudioTapControlState()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<1_000 {
                group.addTask {
                    state.setVolume(Float(index % 150) / 100)
                    state.setMuted(index.isMultiple(of: 2))
                    let snapshot = state.snapshot()
                    #expect(snapshot.volume >= 0)
                    #expect(snapshot.volume <= 1)
                }
            }
        }
    }
}
