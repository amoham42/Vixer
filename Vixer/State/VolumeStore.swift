import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class VolumeStore {
    private static let log = Logger(subsystem: "app.vixer.Vixer", category: "VolumeStore")
    private let defaults: UserDefaults
    private let storageKey = "appVolumes"
    private let writeDebounce: TimeInterval = 0.25

    private var states: [String: AppVolumeState]
    private var controllers: [String: AudioTapController] = [:]
    private var failedBundles: Set<String> = []
    private var writeTask: Task<Void, Never>?

    private(set) var permissionDenied = false
    private(set) var isEnabled = true

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if enabled {
            for (bundleID, state) in states {
                syncController(for: bundleID, state: state)
            }
        } else {
            teardownAllControllers()
        }
    }

    /// User-invoked: clears the gate so the user can retry without quitting.
    func dismissPermissionGate() {
        permissionDenied = false
        // Also clear the per-bundle failure cache so a retry actually re-attempts.
        failedBundles.removeAll()
    }

    private static func isAuthorizationError(_ error: Error) -> Bool {
        let unauthorized: OSStatus = 0x756E6175 // 'unau' = kAudioHardwareUnauthorizedError.
        return (error as? AudioTapError)?.status == unauthorized
    }

    /// Resolves the current PID for a bundle ID. The store needs a PID to install a tap;
    /// `MixerView` injects this closure so the store stays free of NSWorkspace dependencies (testable).
    var pidResolver: (String) -> pid_t? = { _ in nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: AppVolumeState].self, from: data) {
            self.states = decoded
        } else {
            self.states = [:]
        }
    }

    isolated deinit {
        writeTask?.cancel()
        write()
    }

    func state(for bundleID: String) -> AppVolumeState {
        states[bundleID] ?? AppVolumeState()
    }

    func setVolume(_ volume: Float, for bundleID: String) {
        update(bundleID: bundleID) { $0.with(volume: volume) }
    }

    func setMuted(_ muted: Bool, for bundleID: String) {
        update(bundleID: bundleID) { $0.with(muted: muted) }
    }

    /// Called by `AppDiscoveryService` (or the view) when an app terminates so we can release its tap.
    /// Also clears the failure cache: a fresh launch deserves a fresh attempt.
    func processTerminated(bundleID: String) {
        controllers[bundleID]?.teardown()
        controllers.removeValue(forKey: bundleID)
        failedBundles.remove(bundleID)
    }

    private func teardownAllControllers() {
        for controller in controllers.values {
            controller.teardown()
        }
        controllers.removeAll()
    }

    private func update(bundleID: String, _ transform: (AppVolumeState) -> AppVolumeState) {
        let new = transform(states[bundleID] ?? AppVolumeState())
        if new.isPassthrough {
            states.removeValue(forKey: bundleID)
        } else {
            states[bundleID] = new
        }
        syncController(for: bundleID, state: new)
        scheduleWrite()
    }

    private func syncController(for bundleID: String, state: AppVolumeState) {
        guard isEnabled else { return }

        if state.isPassthrough {
            controllers[bundleID]?.teardown()
            controllers.removeValue(forKey: bundleID)
            return
        }
        if let controller = controllers[bundleID] {
            controller.setVolume(state.volume)
            controller.setMuted(state.muted)
            return
        }
        // If we already failed to install a tap for this bundle, don't retry on every slider tick.
        // The cache is cleared on app termination, on dismissPermissionGate, and (implicitly) on quit.
        if failedBundles.contains(bundleID) { return }
        guard let pid = pidResolver(bundleID) else {
            Self.log.info("No audio-producing PID for \(bundleID, privacy: .public); deferring tap install")
            return
        }
        Self.log.info("Resolved audio PID \(pid, privacy: .public) for \(bundleID, privacy: .public)")
        do {
            let controller = try AudioTapController(
                pid: pid,
                bundleID: bundleID,
                tapMode: AppDiscoveryService.audioTapMode(for: bundleID)
            )
            controller.setVolume(state.volume)
            controller.setMuted(state.muted)
            controllers[bundleID] = controller
            // A successful tap install proves permission is granted; clear any prior false-positive gate.
            permissionDenied = false
        } catch {
            Self.log.error("Failed to install tap for \(bundleID, privacy: .public): \(String(describing: error), privacy: .public)")
            failedBundles.insert(bundleID)
            if Self.isAuthorizationError(error) {
                permissionDenied = true
            }
        }
    }

    private func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(self.writeDebounce))
            } catch {
                return
            }
            self.write()
        }
    }

    func flushPendingWrites() {
        writeTask?.cancel()
        writeTask = nil
        write()
    }

    private func write() {
        if let data = try? JSONEncoder().encode(states) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
