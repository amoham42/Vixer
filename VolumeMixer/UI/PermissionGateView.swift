import SwiftUI

struct PermissionGateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "speaker.slash.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Audio capture is required")
                .font(.headline)
            Text("Volume Mixer needs permission to capture app audio so it can apply per-app volume.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.regular)
        }
        .padding(20)
        .frame(width: 320)
    }
}
