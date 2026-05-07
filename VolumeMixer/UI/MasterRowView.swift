import SwiftUI

struct MasterRowView: View {
    let service: MasterVolumeService

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { service.setMuted(!service.muted) }) {
                Image(systemName: service.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(service.muted ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(service.muted ? "Unmute master" : "Mute master")

            Text("Master")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 100, alignment: .leading)

            Slider(
                value: Binding(
                    get: { service.volume },
                    set: { service.setVolume($0) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .opacity(service.muted ? 0.4 : 1.0)
            .disabled(service.muted)

            Text("\(Int(service.volume * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 28)
        .padding(.horizontal, 12)
    }
}
