import SwiftUI

struct MasterRowView: View {
    let service: MasterVolumeService

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { service.setMuted(!service.muted) }) {
                ZStack {
                    if let icon = VixerIcon.templateImage() {
                        Image(nsImage: icon)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: MixerIconMetrics.masterGlyphSize.width, height: MixerIconMetrics.masterGlyphSize.height)
                            .foregroundStyle(service.muted ? .secondary : .primary)
                            .opacity(service.muted ? 0.55 : 1.0)
                    } else {
                        Image(systemName: "slider.horizontal.2.square")
                            .frame(width: MixerIconMetrics.masterGlyphSize.width, height: MixerIconMetrics.masterGlyphSize.height)
                            .foregroundStyle(service.muted ? .secondary : .primary)
                    }

                    if service.muted {
                        Image(systemName: "slash.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(1)
                            .background(.thinMaterial, in: Circle())
                            .offset(x: 7, y: 7)
                    }
                }
                .frame(width: MixerIconMetrics.masterFrameSize.width, height: MixerIconMetrics.masterFrameSize.height)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(service.muted ? "Unmute master" : "Mute master")

            VolumeSliderView(
                value: Binding(
                    get: { service.volume },
                    set: { service.setVolume($0) }
                ),
                isEnabled: !service.muted
            )
        }
        .frame(height: MixerPanelMetrics.rowHeight)
        .padding(.horizontal, 14)
    }
}
