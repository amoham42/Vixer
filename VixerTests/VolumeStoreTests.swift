import XCTest
@testable import Vixer

final class VolumeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "VolumeStoreTests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_unknownBundleID_returnsDefaultPassthroughState() {
        let store = VolumeStore(defaults: defaults)
        XCTAssertEqual(store.state(for: "com.test.unknown"), AppVolumeState())
    }

    func test_setVolume_storesAndRetrievesValue() {
        let store = VolumeStore(defaults: defaults)
        store.setVolume(0.5, for: "com.test.app")
        XCTAssertEqual(store.state(for: "com.test.app").volume, 0.5)
        XCTAssertFalse(store.state(for: "com.test.app").muted)
    }

    func test_setMuted_preservesVolume() {
        let store = VolumeStore(defaults: defaults)
        store.setVolume(0.3, for: "com.test.app")
        store.setMuted(true, for: "com.test.app")
        XCTAssertEqual(store.state(for: "com.test.app").volume, 0.3)
        XCTAssertTrue(store.state(for: "com.test.app").muted)
    }

    func test_persistence_acrossInstances() {
        let store1 = VolumeStore(defaults: defaults)
        store1.setVolume(0.7, for: "com.test.app")
        store1.flushPendingWrites()

        let store2 = VolumeStore(defaults: defaults)
        XCTAssertEqual(store2.state(for: "com.test.app").volume, 0.7, accuracy: 0.0001)
    }

    func test_resetToPassthrough_removesEntry() {
        let store = VolumeStore(defaults: defaults)
        store.setVolume(0.5, for: "com.test.app")
        store.setVolume(1.0, for: "com.test.app")
        store.setMuted(false, for: "com.test.app")
        store.flushPendingWrites()

        let raw = defaults.data(forKey: "appVolumes")!
        let decoded = try! JSONDecoder().decode([String: AppVolumeState].self, from: raw)
        XCTAssertNil(decoded["com.test.app"], "passthrough state should not persist")
    }

    func test_setEnabledOffPreservesStoredVolumes() {
        let store = VolumeStore(defaults: defaults)
        store.setVolume(0.42, for: "com.test.app")

        store.setEnabled(false)

        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.state(for: "com.test.app").volume, 0.42, accuracy: 0.0001)
    }

    func test_disabledStoreDoesNotAttemptToResolvePIDsForNewTaps() {
        let store = VolumeStore(defaults: defaults)
        store.setEnabled(false)
        store.pidResolver = { _ in
            XCTFail("Disabled mixer should not attempt to install new app taps")
            return 123
        }

        store.setVolume(0.5, for: "com.test.app")
    }

    func test_reEnablingMixerAttemptsToRestoreSavedNonPassthroughTaps() {
        let store = VolumeStore(defaults: defaults)
        store.setEnabled(false)
        store.setVolume(0.5, for: "com.test.app")
        var resolvedBundleID: String?
        store.pidResolver = { bundleID in
            resolvedBundleID = bundleID
            return nil
        }

        store.setEnabled(true)

        XCTAssertEqual(resolvedBundleID, "com.test.app")
    }
}
