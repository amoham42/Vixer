import Testing
@testable import Vixer

@MainActor
struct MixerPanelMetricsTests {
    @Test func appListCollapsedShowsOnlyCurrentlyActiveAudioApps() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.Silent", name: "Silent", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.Playing", name: "Playing", isAudioActive: true)
        ]

        #expect(MixerAppList.collapsedApps(from: entries).map(\.bundleID) == ["com.test.Playing"])
    }

    @Test func appListExpandedShowsOpenAppsIncludingInactiveAudioCandidates() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.Silent", name: "Silent", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.Playing", name: "Playing", isAudioActive: true)
        ]

        #expect(MixerAppList.expandedApps(from: entries).map(\.bundleID) == ["com.test.Silent", "com.test.Playing"])
    }

    @Test func appListCanExpandWhenThereAreOpenAppsBeyondActiveCollapsedRows() {
        let entries = [
            AppEntry(pid: 10, bundleID: "com.test.Silent", name: "Silent", isAudioActive: false),
            AppEntry(pid: 20, bundleID: "com.test.Playing", name: "Playing", isAudioActive: true)
        ]

        #expect(MixerAppList.canExpand(entries))
    }

    @Test func expansionStateResetsToCollapsedWhenPanelReopens() {
        var state = MixerExpansionState()
        _ = state.toggle()

        state.reset()

        #expect(state.isExpanded == false)
    }

    @Test
    func expandedContentSizeChangesWithVisibleAppCount() {
        let oneApp = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 1, canExpand: true)
        let fourApps = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 4, canExpand: true)

        #expect(fourApps.height > oneApp.height)
        #expect(fourApps.width == oneApp.width)
    }

    @Test
    func collapsedContentSizeIgnoresVisibleAppCount() {
        let oneApp = MixerPanelMetrics.contentSize(isExpanded: false, visibleAppCount: 1, canExpand: true)
        let manyApps = MixerPanelMetrics.contentSize(isExpanded: false, visibleAppCount: 20, canExpand: true)

        #expect(oneApp == manyApps)
    }

    @Test func expandedSizeTightensHeightToVisibleAppCountWhenListDoesNotNeedScrolling() {
        let twoApps = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 2, canExpand: true)
        let eightApps = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 8, canExpand: true)

        #expect(twoApps.height < eightApps.height)
        #expect(abs(eightApps.height - 404) <= 0.0001)
    }

    @Test func expandedSizeCapsScrollableListWhenThereAreManyApps() {
        let manyApps = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 30, canExpand: true)

        #expect(abs(manyApps.height - 420) <= 0.0001)
        #expect(manyApps.height <= MixerPanelMetrics.maximumExpandedHeight)
    }

    @Test func collapsedSizeUsesCompactDefaultHeight() {
        #expect(MixerPanelMetrics.contentSize(isExpanded: false, visibleAppCount: 3, canExpand: true).height == 260)
    }

    @Test func typographyMatchesCompactControlCenterSectionStyle() {
        #expect(MixerTypography.titleFontSize < 24)
        #expect(MixerTypography.sectionLabelFontSize <= MixerTypography.titleFontSize)
        #expect(MixerTypography.sectionLabelWeight == .semibold)
        #expect(MixerTypography.usesControlCenterRoundedFont)
    }

    @Test func sectionSpacingUsesEqualUpperPaddingForMasterAndAppsLabels() {
        #expect(MixerSpacing.headerToFirstSection == MixerSpacing.sectionDividerToLabel)
        #expect(MixerSpacing.sectionLabelTopPadding == 2)
    }
}
