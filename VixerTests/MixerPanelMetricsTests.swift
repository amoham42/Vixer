import XCTest
@testable import Vixer

final class MixerPanelMetricsTests: XCTestCase {
    func test_appList_collapsedShowsOnlyCurrentlyActiveAudioApps() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.Silent", name: "Silent", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.Playing", name: "Playing", isAudioActive: true)
        ]

        XCTAssertEqual(MixerAppList.collapsedApps(from: entries).map(\.bundleID), ["com.test.Playing"])
    }

    func test_appList_expandedShowsOpenAppsIncludingInactiveAudioCandidates() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.Silent", name: "Silent", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.Playing", name: "Playing", isAudioActive: true)
        ]

        XCTAssertEqual(MixerAppList.expandedApps(from: entries).map(\.bundleID), ["com.test.Silent", "com.test.Playing"])
    }

    func test_appList_canExpandWhenThereAreOpenAppsBeyondActiveCollapsedRows() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.Silent", name: "Silent", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.Playing", name: "Playing", isAudioActive: true)
        ]

        XCTAssertTrue(MixerAppList.canExpand(entries))
    }

    func test_expansionState_resetsToCollapsedWhenPanelReopens() {
        var state = MixerExpansionState()
        _ = state.toggle()

        state.reset()

        XCTAssertFalse(state.isExpanded)
    }

    func test_expandedSize_tightensHeightToVisibleAppCountWhenListDoesNotNeedScrolling() {
        let twoApps = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 2, canExpand: true)
        let eightApps = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 8, canExpand: true)

        XCTAssertLessThan(twoApps.height, eightApps.height)
        XCTAssertEqual(eightApps.height, 404, accuracy: 0.0001)
    }

    func test_expandedSize_capsScrollableListWhenThereAreManyApps() {
        let manyApps = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 30, canExpand: true)

        XCTAssertEqual(manyApps.height, 420, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(manyApps.height, MixerPanelMetrics.maximumExpandedHeight)
    }

    func test_collapsedSize_usesCompactDefaultHeight() {
        XCTAssertEqual(MixerPanelMetrics.contentSize(isExpanded: false, visibleAppCount: 3, canExpand: true).height, 260)
    }

    func test_typography_matchesCompactControlCenterSectionStyle() {
        XCTAssertLessThan(MixerTypography.titleFontSize, 24)
        XCTAssertLessThanOrEqual(MixerTypography.sectionLabelFontSize, MixerTypography.titleFontSize)
        XCTAssertEqual(MixerTypography.sectionLabelWeight, .semibold)
        XCTAssertTrue(MixerTypography.usesControlCenterRoundedFont)
    }

    func test_sectionSpacing_usesEqualUpperPaddingForMasterAndAppsLabels() {
        XCTAssertEqual(MixerSpacing.headerToFirstSection, MixerSpacing.sectionDividerToLabel)
        XCTAssertEqual(MixerSpacing.sectionLabelTopPadding, 2)
    }
}
