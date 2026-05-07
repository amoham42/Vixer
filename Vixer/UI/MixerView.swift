import Observation
import SwiftUI

struct MixerExpansionState {
    private(set) var isExpanded = false

    mutating func toggle() {
        isExpanded.toggle()
    }

    mutating func reset() {
        isExpanded = false
    }
}

@MainActor
@Observable
final class MixerPresentationState {
    var resetToken = UUID()

    func resetForNewPresentation() {
        resetToken = UUID()
    }
}

struct MixerTypography {
    static let titleFontSize: CGFloat = 14
    static let titleFontWeight: Font.Weight = .semibold
    static let sectionLabelFontSize: CGFloat = 12
    static let sectionLabelWeight: Font.Weight = .semibold
    static let fontDesign: Font.Design = .rounded
}

struct MixerSpacing {
    /// Gap from the header divider to the first section label.
    static let headerToFirstSection: CGFloat = 4

    /// Gap from an in-content section divider to the next section label.
    static let sectionDividerToLabel: CGFloat = 4

    /// Shared optical top inset applied directly to section labels.
    static let sectionLabelTopPadding: CGFloat = 2
}

struct MixerAppList {
    static func collapsedApps(from entries: [AppEntry]) -> [AppEntry] {
        Array(entries.filter(\.isAudioActive).prefix(3))
    }

    static func expandedApps(from entries: [AppEntry]) -> [AppEntry] {
        entries
    }

    static func canExpand(_ entries: [AppEntry]) -> Bool {
        expandedApps(from: entries).count > collapsedApps(from: entries).count
    }
}

struct MixerPanelMetrics {
    static let width: CGFloat = 320
    static let collapsedHeight: CGFloat = 260
    static let maximumExpandedHeight: CGFloat = 420
    static let maximumAppListHeight: CGFloat = 300

    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 2
    static let rowStackVerticalPadding: CGFloat = 4

    private static let expandedBaseHeight: CGFloat = 118
    private static var rowVerticalPadding: CGFloat { rowStackVerticalPadding * 2 }

    static func contentSize(isExpanded: Bool, visibleAppCount: Int, canExpand: Bool) -> CGSize {
        guard isExpanded else {
            return CGSize(width: width, height: collapsedHeight)
        }

        let listHeight = min(maximumAppListHeight, appListHeight(for: visibleAppCount))
        let buttonHeight: CGFloat = canExpand ? 24 : 0
        let height = min(maximumExpandedHeight, expandedBaseHeight + listHeight + buttonHeight)
        return CGSize(width: width, height: height)
    }

    static func appListHeight(for visibleAppCount: Int) -> CGFloat {
        guard visibleAppCount > 0 else { return 34 }
        let rows = CGFloat(visibleAppCount)
        let spacings = CGFloat(max(visibleAppCount - 1, 0)) * rowSpacing
        return rowVerticalPadding + rows * rowHeight + spacings
    }
}

struct MixerView: View {
    @State private var discovery = AppDiscoveryService()
    @State private var store = VolumeStore()
    @State private var master = MasterVolumeService()
    @State private var expansionState = MixerExpansionState()

    let presentationState: MixerPresentationState
    var onSizeChange: (CGSize) -> Void

    init(
        presentationState: MixerPresentationState = MixerPresentationState(),
        onSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.presentationState = presentationState
        self.onSizeChange = onSizeChange
    }

    var body: some View {
        Group {
            if store.permissionDenied {
                PermissionGateView(onDismiss: { store.dismissPermissionGate() })
            } else {
                mixerContent
            }
        }
        .onAppear {
            // For tap creation we want the PID that's actually producing audio (often a
            // helper subprocess like com.google.Chrome.helper), not the main-app PID.
            // Fall back to the NSWorkspace PID only if no audio process matches the bundle.
            store.pidResolver = { [weak discovery] bundleID in
                if let pid = AppDiscoveryService.audioProducingPID(forBundlePrefix: bundleID) {
                    return pid
                }
                return discovery?.apps.first(where: { $0.bundleID == bundleID })?.pid
            }
            discovery.onTerminated = { [weak store] bundleID in
                store?.processTerminated(bundleID: bundleID)
            }
        }
        .onChange(of: presentationState.resetToken) {
            expansionState.reset()
        }
        .onChange(of: desiredContentSize) { _, newSize in
            onSizeChange(newSize)
        }
    }

    private var mixerContent: some View {
        VStack(alignment: .leading, spacing: MixerSpacing.headerToFirstSection) {
            mixerHeader

            VStack(spacing: MixerSpacing.sectionDividerToLabel) {
                sectionLabel("Master Volume")

                MasterRowView(service: master)

                Divider()
                    .opacity(1.0)
                    .padding(.horizontal, 14)

                sectionLabel("Apps")

                if expansionState.isExpanded {
                    ScrollView {
                        appRows(for: expandedApps)
                    }
                    .frame(height: expandedListHeight)
                } else if collapsedApps.isEmpty {
                    Text("No active app audio")
                        .font(.system(size: 12, weight: .medium, design: MixerTypography.fontDesign))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                } else {
                    appRows(for: collapsedApps)
                }

                if canExpand {
                    Button(action: toggleExpansion) {
                        expansionButtonIcon
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expansionState.isExpanded ? "Show fewer apps" : "Show more apps")
                }
            }
        }
        .frame(width: 304)
        .padding(.bottom, 8)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: MixerTypography.sectionLabelFontSize, weight: MixerTypography.sectionLabelWeight, design: MixerTypography.fontDesign))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, MixerSpacing.sectionLabelTopPadding)
    }

    private var expansionButtonIcon: some View {
        let isExpanded = expansionState.isExpanded
        let assetName = isExpanded ? VixerIcon.showLessAssetName : VixerIcon.showMoreAssetName
        let iconSize = isExpanded ? MixerIconMetrics.showLessIconSize : MixerIconMetrics.showMoreIconSize

        return Group {
            if let icon = VixerIcon.templateImage(named: assetName, size: iconSize) {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: isExpanded ? "rectangle" : "list.bullet.rectangle")
                    .font(.system(size: iconSize.height, weight: .semibold))
            }
        }
        .frame(width: iconSize.width, height: iconSize.height)
        .frame(width: MixerIconMetrics.expansionIconFrameSize.width, height: MixerIconMetrics.expansionIconFrameSize.height)
    }

    private var mixerHeader: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                Text("Vixer")
                    .font(.system(size: MixerTypography.titleFontSize, weight: MixerTypography.titleFontWeight, design: MixerTypography.fontDesign))
                    .foregroundStyle(.primary)

                Spacer(minLength: 16)

                Toggle("", isOn: mixerEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .accessibilityLabel("Turn Vixer on or off")
            }

            Divider()
                .opacity(1.0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var mixerEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled },
            set: { store.setEnabled($0) }
        )
    }

    private var collapsedApps: [AppEntry] {
        MixerAppList.collapsedApps(from: discovery.apps)
    }

    private var expandedApps: [AppEntry] {
        MixerAppList.expandedApps(from: discovery.apps)
    }

    private var canExpand: Bool {
        MixerAppList.canExpand(discovery.apps)
    }

    private var expandedListHeight: CGFloat {
        min(MixerPanelMetrics.maximumAppListHeight, MixerPanelMetrics.appListHeight(for: expandedApps.count))
    }

    private var desiredContentSize: CGSize {
        MixerPanelMetrics.contentSize(
            isExpanded: expansionState.isExpanded,
            visibleAppCount: expansionState.isExpanded ? expandedApps.count : collapsedApps.count,
            canExpand: canExpand
        )
    }

    private func toggleExpansion() {
        expansionState.toggle()
    }

    @ViewBuilder
    private func appRows(for entries: [AppEntry]) -> some View {
        LazyVStack(spacing: MixerPanelMetrics.rowSpacing) {
            ForEach(entries) { entry in
                AppRowView(
                    entry: entry,
                    volume: bindingVolume(for: entry.bundleID),
                    muted: bindingMuted(for: entry.bundleID),
                    isMixerEnabled: store.isEnabled
                )
            }
        }
        .padding(.vertical, MixerPanelMetrics.rowStackVerticalPadding)
    }

    private func bindingVolume(for bundleID: String) -> Binding<Float> {
        Binding(
            get: { store.state(for: bundleID).volume },
            set: { store.setVolume($0, for: bundleID) }
        )
    }

    private func bindingMuted(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { store.state(for: bundleID).muted },
            set: { store.setMuted($0, for: bundleID) }
        )
    }
}
