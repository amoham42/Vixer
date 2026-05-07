import AppKit

struct AppEntry: Identifiable, Hashable {
    let pid: pid_t
    let bundleID: String
    let name: String
    let isAudioActive: Bool

    var id: String { bundleID }

    static func from(_ runningApp: NSRunningApplication, isAudioActive: Bool = false) -> AppEntry? {
        guard let bundleID = runningApp.bundleIdentifier else { return nil }
        return AppEntry(
            pid: runningApp.processIdentifier,
            bundleID: bundleID,
            name: runningApp.localizedName ?? bundleID,
            isAudioActive: isAudioActive
        )
    }

    func icon() -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
