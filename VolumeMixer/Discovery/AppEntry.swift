import AppKit

struct AppEntry: Identifiable, Hashable {
    let pid: pid_t
    let bundleID: String
    let name: String

    var id: pid_t { pid }

    static func from(_ runningApp: NSRunningApplication) -> AppEntry? {
        guard let bundleID = runningApp.bundleIdentifier else { return nil }
        return AppEntry(
            pid: runningApp.processIdentifier,
            bundleID: bundleID,
            name: runningApp.localizedName ?? bundleID
        )
    }

    func icon() -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
