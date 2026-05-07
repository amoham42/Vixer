import Foundation
import Testing
@testable import Vixer

@MainActor
struct VolumeStoreTests {
    private func withDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
        let suiteName = "VolumeStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return try body(defaults)
    }

    @Test func unknownBundleIDReturnsDefaultPassthroughState() throws {
        try withDefaults { defaults in
            let store = VolumeStore(defaults: defaults)
            #expect(store.state(for: "com.test.unknown") == AppVolumeState())
        }
    }

    @Test func setVolumeStoresAndRetrievesValue() throws {
        try withDefaults { defaults in
            let store = VolumeStore(defaults: defaults)
            store.setVolume(0.5, for: "com.test.app")
            #expect(store.state(for: "com.test.app").volume == 0.5)
            #expect(store.state(for: "com.test.app").muted == false)
        }
    }

    @Test func setMutedPreservesVolume() throws {
        try withDefaults { defaults in
            let store = VolumeStore(defaults: defaults)
            store.setVolume(0.3, for: "com.test.app")
            store.setMuted(true, for: "com.test.app")
            #expect(store.state(for: "com.test.app").volume == 0.3)
            #expect(store.state(for: "com.test.app").muted == true)
        }
    }

    @Test func persistenceAcrossInstances() throws {
        try withDefaults { defaults in
            let store1 = VolumeStore(defaults: defaults)
            store1.setVolume(0.7, for: "com.test.app")
            store1.flushPendingWrites()

            let store2 = VolumeStore(defaults: defaults)
            #expect(abs(store2.state(for: "com.test.app").volume - 0.7) <= 0.0001)
        }
    }

    @Test func resetToPassthroughRemovesEntry() throws {
        try withDefaults { defaults in
            let store = VolumeStore(defaults: defaults)
            store.setVolume(0.5, for: "com.test.app")
            store.setVolume(1.0, for: "com.test.app")
            store.setMuted(false, for: "com.test.app")
            store.flushPendingWrites()

            let raw = try #require(defaults.data(forKey: "appVolumes"))
            let decoded = try JSONDecoder().decode([String: AppVolumeState].self, from: raw)
            #expect(decoded["com.test.app"] == nil)
        }
    }

    @Test func setEnabledOffPreservesStoredVolumes() throws {
        try withDefaults { defaults in
            let store = VolumeStore(defaults: defaults)
            store.setVolume(0.42, for: "com.test.app")

            store.setEnabled(false)

            #expect(store.isEnabled == false)
            #expect(abs(store.state(for: "com.test.app").volume - 0.42) <= 0.0001)
        }
    }

    @Test func disabledStoreDoesNotAttemptToResolvePIDsForNewTaps() throws {
        try withDefaults { defaults in
            let store = VolumeStore(defaults: defaults)
            store.setEnabled(false)
            store.pidResolver = { _ in
                Issue.record("Disabled mixer should not attempt to install new app taps")
                return 123
            }

            store.setVolume(0.5, for: "com.test.app")
        }
    }

    @Test func reEnablingMixerAttemptsToRestoreSavedNonPassthroughTaps() throws {
        try withDefaults { defaults in
            let store = VolumeStore(defaults: defaults)
            store.setEnabled(false)
            store.setVolume(0.5, for: "com.test.app")
            var resolvedBundleID: String?
            store.pidResolver = { bundleID in
                resolvedBundleID = bundleID
                return nil
            }

            store.setEnabled(true)

            #expect(resolvedBundleID == "com.test.app")
        }
    }
}
