import SwiftUI

struct AppRowView: View {
    let entry: AppEntry
    @Binding var volume: Float
    @Binding var muted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { muted.toggle() }) {
                ZStack {
                    if let icon = entry.icon() {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .opacity(muted ? 0.45 : 1.0)
                    } else {
                        Image(systemName: "app")
                            .frame(width: 24, height: 24)
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
            .accessibilityLabel(muted ? "Unmute \(entry.name)" : "Mute \(entry.name)")

            Text(entry.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 100, alignment: .leading)

            Slider(value: $volume, in: 0...1)
                .controlSize(.small)
                .opacity(muted ? 0.4 : 1.0)
                .disabled(muted)

            Text("\(Int(volume * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 28)
        .padding(.horizontal, 12)
    }
}
