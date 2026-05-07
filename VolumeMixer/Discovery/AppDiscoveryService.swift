import AppKit
import Observation

@Observable
final class AppDiscoveryService {
    private(set) var apps: [AppEntry] = []
    private var observers: [NSObjectProtocol] = []

    /// Called with the bundleID of an app that disappeared from `apps` since the last refresh.
    /// `MixerView` wires this to `VolumeStore.processTerminated(bundleID:)`.
    var onTerminated: (String) -> Void = { _ in }

    init() {
        refresh()
        observe()
    }

    deinit {
        for token in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func refresh() {
        let previous = Set(apps.map(\.bundleID))
        let entries = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(AppEntry.from(_:))
        apps = entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let current = Set(apps.map(\.bundleID))
        for gone in previous.subtracting(current) {
            onTerminated(gone)
        }
    }

    private func observe() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
            observers.append(token)
        }
    }
}
