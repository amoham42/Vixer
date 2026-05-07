import XCTest
@testable import Vixer

final class AppVolumeStateTests: XCTestCase {
    func test_default_isFullVolumeAndUnmuted() {
        let state = AppVolumeState()
        XCTAssertEqual(state.volume, 1.0)
        XCTAssertFalse(state.muted)
    }

    func test_isPassthrough_whenFullVolumeAndUnmuted() {
        XCTAssertTrue(AppVolumeState(volume: 1.0, muted: false).isPassthrough)
        XCTAssertFalse(AppVolumeState(volume: 0.5, muted: false).isPassthrough)
        XCTAssertFalse(AppVolumeState(volume: 1.0, muted: true).isPassthrough)
    }

    func test_codable_roundTrip() throws {
        let original = AppVolumeState(volume: 0.42, muted: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppVolumeState.self, from: data)
        XCTAssertEqual(decoded.volume, 0.42, accuracy: 0.0001)
        XCTAssertEqual(decoded.muted, true)
    }

    func test_volume_isClamped() {
        XCTAssertEqual(AppVolumeState(volume: 2.0, muted: false).volume, 1.0)
        XCTAssertEqual(AppVolumeState(volume: -0.5, muted: false).volume, 0.0)
    }
}
