import Foundation
import Observation

@Observable
final class VolumeStore {
    private let defaults: UserDefaults
    private let storageKey = "appVolumes"
    private let writeDebounce: TimeInterval = 0.25

    private var states: [String: AppVolumeState]
    private var writeTimer: DispatchSourceTimer?

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

    private func update(bundleID: String, _ transform: (AppVolumeState) -> AppVolumeState) {
        let new = transform(states[bundleID] ?? AppVolumeState())
        if new.isPassthrough {
            states.removeValue(forKey: bundleID)
        } else {
            states[bundleID] = new
        }
        scheduleWrite()
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
