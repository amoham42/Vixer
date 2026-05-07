import Testing
@testable import Vixer

@MainActor
struct AppDiscoveryServiceTests {
    @Test func visibleEntriesKeepsOpenInactiveAppsForExpandedList() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.Silent", name: "Silent", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.Playing", name: "Playing", isAudioActive: true)
        ]

        let visible = AppDiscoveryService.visibleEntries(entries, ownBundleID: nil)

        #expect(visible.map(\.bundleID) == ["com.test.Silent", "com.test.Playing"])
    }

    @Test func appsAreSortedByAudioActivityThenLocalizedName() {
        let service = AppDiscoveryService()
        service.refresh()

        let firstInactiveIndex = service.apps.firstIndex { $0.isAudioActive == false } ?? service.apps.endIndex
        let activeAppsAreAllActive = service.apps[..<firstInactiveIndex].allSatisfy { $0.isAudioActive }
        let inactiveAppsAreAllInactive = service.apps[firstInactiveIndex...].allSatisfy { $0.isAudioActive == false }
        #expect(activeAppsAreAllActive)
        #expect(inactiveAppsAreAllInactive)

        let activeNames = service.apps[..<firstInactiveIndex].map(\.name)
        let inactiveNames = service.apps[firstInactiveIndex...].map(\.name)
        #expect(activeNames == activeNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(inactiveNames == inactiveNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test func collapsedEntriesMergesDuplicateBundleIDsAndPrefersAudioActiveRepresentative() throws {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.App", name: "Test App", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.App", name: "Test App", isAudioActive: true),
            AppEntry(pid: 30, bundleID: "com.other.App", name: "Other App", isAudioActive: false)
        ]

        let collapsed = AppDiscoveryService.collapsedEntries(entries)

        #expect(collapsed.count == 2)
        let testApp = try #require(collapsed.first { $0.bundleID == "com.test.App" })
        #expect(testApp.pid == 20)
        #expect(testApp.isAudioActive == true)
    }

    @Test func visibleEntriesExcludesVixerItself() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.armanmohammadi.Vixer", name: "Vixer", isAudioActive: true),
            AppEntry(pid: 20, bundleID: "com.test.App", name: "Test App", isAudioActive: true)
        ]

        let visible = AppDiscoveryService.visibleEntries(entries, ownBundleID: "com.armanmohammadi.Vixer")

        #expect(visible.map(\.bundleID) == ["com.test.App"])
    }

    @Test func audioOwnerBundlePrefixMapsFaceTimeToAVConferenceD() {
        #expect(AppDiscoveryService.audioOwnerBundlePrefix(for: "com.apple.FaceTime") == "com.apple.avconferenced")
    }

    @Test func audioTapModeUsesBoostedDeviceStreamForFaceTime() {
        #expect(AppDiscoveryService.audioTapMode(for: "com.apple.FaceTime") == .deviceStream(stream: 0, makeupGain: 100))
    }

    @Test func audioTapModeUsesStandardDeviceStreamForChrome() {
        #expect(AppDiscoveryService.audioTapMode(for: "com.google.Chrome") == .deviceStream(stream: 0, makeupGain: 1))
    }

    @Test func audioTapModeUsesStandardDeviceStreamForUnconfiguredRegularApps() {
        #expect(AppDiscoveryService.audioTapMode(for: "com.apple.Safari") == .deviceStream(stream: 0, makeupGain: 1))
    }

    @Test func isAudioOutputActiveUsesOverrideOwnerBundleForFaceTime() {
        #expect(AppDiscoveryService.isAudioOutputActive(
            bundleID: "com.apple.FaceTime",
            pid: 123,
            runningOutputPIDs: [],
            runningOutputBundleIDs: ["com.apple.avconferenced"]
        ))
    }

    @Test func isAudioOutputActiveRejectsProcessObjectsThatAreNotRunningOutput() {
        #expect(AppDiscoveryService.isAudioOutputActive(
            bundleID: "com.test.App",
            pid: 123,
            runningOutputPIDs: [],
            runningOutputBundleIDs: ["com.other.Audio"]
        ) == false)
    }

    @Test func terminatedBundleIDsUsesRunningAppsNotAudioVisibility() {
        let currentEntries = [
            AppEntry(pid: 10, bundleID: "com.test.SilentButStillRunning", name: "Silent", isAudioActive: false)
        ]

        let terminated = AppDiscoveryService.terminatedBundleIDs(
            previousRunningBundleIDs: ["com.test.SilentButStillRunning", "com.test.Quit"],
            currentEntries: currentEntries
        )

        #expect(terminated == ["com.test.Quit"])
    }
}
