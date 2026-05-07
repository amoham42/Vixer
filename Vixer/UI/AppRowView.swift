import SwiftUI

struct AppRowView: View {
    let entry: AppEntry
    @Binding var volume: Float
    @Binding var muted: Bool
    var isMixerEnabled = true

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { muted.toggle() }) {
                ZStack {
                    if let icon = entry.icon() {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: MixerIconMetrics.appFrameSize.width, height: MixerIconMetrics.appFrameSize.height)
                            .opacity(muted ? 0.45 : 1.0)
                    } else {
                        Image(systemName: "app")
                            .frame(width: MixerIconMetrics.appFrameSize.width, height: MixerIconMetrics.appFrameSize.height)
                    }
                    if muted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(2)
                            .background(.thinMaterial, in: Circle())
                            .offset(x: 6, y: 6)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isMixerEnabled)
            .accessibilityLabel(muted ? "Unmute \(entry.name)" : "Mute \(entry.name)")

            VolumeSliderView(value: $volume, isEnabled: isMixerEnabled && !muted)
        }
        .frame(height: MixerPanelMetrics.rowHeight)
        .padding(.horizontal, 14)
        .opacity(isMixerEnabled ? 1.0 : 0.55)
    }
}
