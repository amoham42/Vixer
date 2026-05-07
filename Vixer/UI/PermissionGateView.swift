import SwiftUI

struct PermissionGateView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "speaker.slash.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Audio capture is required")
                .font(.headline)
            Text("Vixer needs permission to capture app audio so it can apply per-app volume.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            HStack(spacing: 8) {
                Button("Try Again") { onDismiss() }
                Button("Open Privacy Settings") {
                    let candidates = [
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy",
                        "x-apple.systempreferences:com.apple.preference.security"
                    ]
                    for s in candidates {
                        if let url = URL(string: s), NSWorkspace.shared.open(url) { break }
                    }
                }
            }
            .controlSize(.regular)
        }
        .padding(20)
        .frame(width: 320)
    }
}
