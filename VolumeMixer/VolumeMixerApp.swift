import SwiftUI

@main
struct VolumeMixerApp: App {
    var body: some Scene {
        MenuBarExtra("Volume Mixer", systemImage: "speaker.wave.2.fill") {
            MixerView()
        }
        .menuBarExtraStyle(.window)
    }
}
