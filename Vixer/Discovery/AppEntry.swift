import AppKit

struct AppEntry: Identifiable {
    let pid: pid_t
    let bundleID: String
    let name: String
    let isAudioActive: Bool

    var id: String { bundleID }

    func icon() -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
