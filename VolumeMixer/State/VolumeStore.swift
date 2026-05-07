import Foundation
import Observation
import OSLog

@Observable
final class VolumeStore {
    private static let log = Logger(subsystem: "com.armanmohammadi.VolumeMixer", category: "VolumeStore")
    private let defaults: UserDefaults
    private let storageKey = "appVolumes"
    private let writeDebounce: TimeInterval = 0.25

    private var states: [String: AppVolumeState]
    private var controllers: [String: AudioTapController] = [:]
    private var writeTimer: DispatchSourceTimer?

    private(set) var permissionDenied = false

    /// Sets the flag if at least one tap install has failed with a permission-related status.
    /// Called by syncController.
    fileprivate func notePermissionFailure() {
        permissionDenied = true
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
    func processTerminated(bundleID: String) {
        controllers[bundleID]?.teardown()
        controllers.removeValue(forKey: bundleID)
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
        guard let pid = pidResolver(bundleID) else {
            Self.log.debug("No PID for \(bundleID, privacy: .public); deferring tap install")
            return
        }
        do {
            let controller = try AudioTapController(pid: pid, bundleID: bundleID)
            controller.setVolume(state.volume)
            controller.setMuted(state.muted)
            controllers[bundleID] = controller
        } catch {
            Self.log.error("Failed to install tap for \(bundleID, privacy: .public): \(String(describing: error), privacy: .public)")
            // status -50 (kAudio_BadParamError) and -4 (-kAudioHardwareNotRunningError) are seen
            // when audio capture is not authorized. Treat any failure here as a permission flag —
            // the worst case is we show the gate even when the real cause is something else,
            // and the gate has a "Open Privacy Settings" button which is also useful in that case.
            notePermissionFailure()
        }
    }

    private func scheduleWrite() {
        writeTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + writeDebounce)
        timer.setEventHandler { [weak self] in self?.write() }
        timer.resume()
        writeTimer = timer
    }

    func flushPendingWrites() {
        writeTimer?.cancel()
        writeTimer = nil
        write()
    }

    private func write() {
        if let data = try? JSONEncoder().encode(states) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
