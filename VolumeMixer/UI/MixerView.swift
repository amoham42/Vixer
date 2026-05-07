import SwiftUI

struct MixerView: View {
    @State private var discovery = AppDiscoveryService()
    @State private var store = VolumeStore()
    @State private var master = MasterVolumeService()

    var body: some View {
        Group {
            if store.permissionDenied {
                PermissionGateView()
            } else {
                mixerContent
            }
        }
        .onAppear {
            store.pidResolver = { [weak discovery] bundleID in
                discovery?.apps.first(where: { $0.bundleID == bundleID })?.pid
            }
        }
    }

    private var mixerContent: some View {
        VStack(spacing: 0) {
            MasterRowView(service: master)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(discovery.apps) { entry in
                        AppRowView(
                            entry: entry,
                            volume: bindingVolume(for: entry.bundleID),
                            muted: bindingMuted(for: entry.bundleID)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 460)
        }
        .frame(width: 320)
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
