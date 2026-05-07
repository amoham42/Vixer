import SwiftUI

@main
struct VolumeMixerApp: App {
    var body: some Scene {
        MenuBarExtra("Volume Mixer", systemImage: "speaker.wave.2.fill") {
            Text("Volume Mixer — bootstrap OK")
                .padding()
                .frame(width: 240)
        }
        .menuBarExtraStyle(.window)
    }
}
