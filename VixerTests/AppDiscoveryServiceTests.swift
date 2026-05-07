import XCTest
@testable import Vixer

final class AppDiscoveryServiceTests: XCTestCase {
    func test_visibleEntries_keepsOpenInactiveAppsForExpandedList() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.Silent", name: "Silent", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.Playing", name: "Playing", isAudioActive: true)
        ]

        let visible = AppDiscoveryService.visibleEntries(entries, ownBundleID: nil)

        XCTAssertEqual(visible.map(\.bundleID), ["com.test.Silent", "com.test.Playing"])
    }

    func test_apps_areSortedByAudioActivityThenLocalizedName() {
        let service = AppDiscoveryService()
        service.refresh()

        let firstInactiveIndex = service.apps.firstIndex { !$0.isAudioActive } ?? service.apps.endIndex
        XCTAssertTrue(service.apps[..<firstInactiveIndex].allSatisfy(\.isAudioActive))
        XCTAssertTrue(service.apps[firstInactiveIndex...].allSatisfy { !$0.isAudioActive })

        let activeNames = service.apps[..<firstInactiveIndex].map(\.name)
        let inactiveNames = service.apps[firstInactiveIndex...].map(\.name)
        XCTAssertEqual(activeNames, activeNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        XCTAssertEqual(inactiveNames, inactiveNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func test_collapsedEntries_mergesDuplicateBundleIDsAndPrefersAudioActiveRepresentative() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.App", name: "Test App", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.App", name: "Test App", isAudioActive: true),
            AppEntry(pid: 30, bundleID: "com.other.App", name: "Other App", isAudioActive: false)
        ]

        let collapsed = AppDiscoveryService.collapsedEntries(entries)

        XCTAssertEqual(collapsed.count, 2)
        let testApp = collapsed.first { $0.bundleID == "com.test.App" }
        XCTAssertEqual(testApp?.pid, 20)
        XCTAssertEqual(testApp?.isAudioActive, true)
    }

    func test_visibleEntries_excludesVixerItself() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.armanmohammadi.Vixer", name: "Vixer", isAudioActive: true),
            AppEntry(pid: 20, bundleID: "com.test.App", name: "Test App", isAudioActive: true)
        ]

        let visible = AppDiscoveryService.visibleEntries(entries, ownBundleID: "com.armanmohammadi.Vixer")

        XCTAssertEqual(visible.map(\.bundleID), ["com.test.App"])
    }

    func test_audioOwnerBundlePrefix_mapsFaceTimeToAVConferenceD() {
        XCTAssertEqual(
            AppDiscoveryService.audioOwnerBundlePrefix(for: "com.apple.FaceTime"),
            "com.apple.avconferenced"
        )
    }

    func test_audioTapMode_usesBoostedDeviceStreamForFaceTime() {
        XCTAssertEqual(
            AppDiscoveryService.audioTapMode(for: "com.apple.FaceTime"),
            .deviceStream(stream: 0, makeupGain: 100)
        )
    }

    func test_audioTapMode_usesStandardDeviceStreamForChrome() {
        XCTAssertEqual(
            AppDiscoveryService.audioTapMode(for: "com.google.Chrome"),
            .deviceStream(stream: 0, makeupGain: 1)
        )
    }

    func test_audioTapMode_usesStandardDeviceStreamForUnconfiguredRegularApps() {
        XCTAssertEqual(
            AppDiscoveryService.audioTapMode(for: "com.apple.Safari"),
            .deviceStream(stream: 0, makeupGain: 1)
        )
    }

    func test_isAudioOutputActive_usesOverrideOwnerBundleForFaceTime() {
        XCTAssertTrue(
            AppDiscoveryService.isAudioOutputActive(
                bundleID: "com.apple.FaceTime",
                pid: 123,
                runningOutputPIDs: [],
                runningOutputBundleIDs: ["com.apple.avconferenced"]
            )
        )
    }

    func test_isAudioOutputActive_rejectsProcessObjectsThatAreNotRunningOutput() {
        XCTAssertFalse(
            AppDiscoveryService.isAudioOutputActive(
                bundleID: "com.test.App",
                pid: 123,
                runningOutputPIDs: [],
                runningOutputBundleIDs: ["com.other.Audio"]
            )
        )
    }

    func test_terminatedBundleIDs_usesRunningAppsNotAudioVisibility() {
        let currentEntries = [
            AppEntry(pid: 10, bundleID: "com.test.SilentButStillRunning", name: "Silent", isAudioActive: false)
        ]

        let terminated = AppDiscoveryService.terminatedBundleIDs(
            previousRunningBundleIDs: ["com.test.SilentButStillRunning", "com.test.Quit"],
            currentEntries: currentEntries
        )

        XCTAssertEqual(terminated, ["com.test.Quit"])
    }
}
