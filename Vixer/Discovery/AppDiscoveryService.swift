import AppKit
import CoreAudio
import Observation
import OSLog

@Observable
final class AppDiscoveryService {
    private static let log = Logger(subsystem: "com.armanmohammadi.Vixer", category: "Discovery")

    private(set) var apps: [AppEntry] = []
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: DispatchSourceTimer?
    private var runningBundleIDs = Set<String>()
    private let pollInterval: TimeInterval = 2.0

    /// Called with the bundleID of an app that disappeared from `apps` since the last refresh.
    /// `MixerView` wires this to `VolumeStore.processTerminated(bundleID:)`.
    var onTerminated: (String) -> Void = { _ in }

    init() {
        refresh()
        observe()
        startAudioActivePolling()
    }

    deinit {
        pollTimer?.cancel()
        for token in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func refresh() {
        let previousRunningBundleIDs = runningBundleIDs
        let runningOutput = Self.runningAudioOutputProcesses()
        let runningRegular = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        let entries = runningRegular.compactMap { app -> AppEntry? in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return AppEntry(
                pid: app.processIdentifier,
                bundleID: bundleID,
                name: app.localizedName ?? bundleID,
                isAudioActive: Self.isAudioOutputActive(
                    bundleID: bundleID,
                    pid: app.processIdentifier,
                    runningOutputPIDs: runningOutput.pids,
                    runningOutputBundleIDs: runningOutput.bundleIDs
                )
            )
        }
        apps = Self.visibleEntries(entries, ownBundleID: Bundle.main.bundleIdentifier).sorted { lhs, rhs in
            if lhs.isAudioActive != rhs.isAudioActive { return lhs.isAudioActive }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        Self.log.info("Refresh: regular=\(runningRegular.count, privacy: .public) running-output=\(runningOutput.pids.count, privacy: .public) shown=\(self.apps.count, privacy: .public)")
        for gone in Self.terminatedBundleIDs(previousRunningBundleIDs: previousRunningBundleIDs, currentEntries: entries) {
            onTerminated(gone)
        }
        runningBundleIDs = Set(entries.map(\.bundleID))
    }

    static func visibleEntries(_ entries: [AppEntry], ownBundleID: String?) -> [AppEntry] {
        collapsedEntries(entries).filter { entry in
            entry.bundleID != ownBundleID
        }
    }

    static func terminatedBundleIDs(previousRunningBundleIDs: Set<String>, currentEntries: [AppEntry]) -> Set<String> {
        previousRunningBundleIDs.subtracting(Set(currentEntries.map(\.bundleID)))
    }

    static func isAudioOutputActive(
        bundleID: String,
        pid: pid_t,
        runningOutputPIDs: Set<pid_t>,
        runningOutputBundleIDs: Set<String>
    ) -> Bool {
        if runningOutputPIDs.contains(pid) { return true }

        let ownerPrefix = audioOwnerBundlePrefix(for: bundleID)
        return runningOutputBundleIDs.contains { runningBundleID in
            runningBundleID.hasPrefix(ownerPrefix)
        }
    }

    static func collapsedEntries(_ entries: [AppEntry]) -> [AppEntry] {
        var collapsed: [String: AppEntry] = [:]
        var order: [String] = []

        for entry in entries {
            if let existing = collapsed[entry.bundleID] {
                collapsed[entry.bundleID] = preferredEntry(existing, over: entry) ? existing : entry
            } else {
                collapsed[entry.bundleID] = entry
                order.append(entry.bundleID)
            }
        }

        return order.compactMap { collapsed[$0] }
    }

    private static func preferredEntry(_ lhs: AppEntry, over rhs: AppEntry) -> Bool {
        if lhs.isAudioActive != rhs.isAudioActive { return lhs.isAudioActive }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedDescending
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

    /// Audio-activeness changes dynamically (apps start/stop streams without launching/quitting),
    /// so workspace notifications aren't enough — we also poll CoreAudio's process list.
    private func startAudioActivePolling() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        pollTimer = timer
    }

    /// Apps whose audio is owned by a different system process. The slider for the key bundle
    /// will tap the value bundle's audio.
    ///
    /// Warning: tapping a shared daemon affects every app that routes through it. FaceTime call
    /// audio is owned by avconferenced, which also handles Continuity Calls and other call audio.
    private struct AudioOwnershipOverride {
        let ownerBundlePrefix: String
        let tapMode: AudioTapController.TapMode
    }

    private static let audioOwnershipOverrides: [String: AudioOwnershipOverride] = [
        "com.apple.FaceTime": AudioOwnershipOverride(
            ownerBundlePrefix: "com.apple.avconferenced",
            tapMode: .deviceStream(stream: 0, makeupGain: 100)
        ),
        "com.google.Chrome": AudioOwnershipOverride(
            ownerBundlePrefix: "com.google.Chrome",
            tapMode: .deviceStream(stream: 0, makeupGain: 1)
        )
    ]

    static func audioOwnerBundlePrefix(for bundleID: String) -> String {
        audioOwnershipOverrides[bundleID]?.ownerBundlePrefix ?? bundleID
    }

    static func audioTapMode(for bundleID: String) -> AudioTapController.TapMode {
        audioOwnershipOverrides[bundleID]?.tapMode ?? .deviceStream(stream: 0, makeupGain: 1)
    }

    /// Resolves a user-facing bundle ID (e.g. "com.google.Chrome") to the PID of the
    /// CoreAudio process object that's actually producing audio. For Chrome/Slack/Teams/etc.
    /// the audio is in a `.helper` subprocess, not the main app PID. Prefers a process where
    /// `runningOutput=1`; if none match, falls back to any process whose bundle starts with
    /// the requested prefix; if still none, returns nil.
    static func audioProducingPID(forBundlePrefix bundleID: String) -> pid_t? {
        let searchPrefix = audioOwnerBundlePrefix(for: bundleID)
        guard let processIDs = audioProcessObjectIDs() else { return nil }

        var firstMatch: pid_t? = nil
        var runningMatch: pid_t? = nil
        for processID in processIDs {
            guard let pid = processPID(for: processID),
                  let bundle = processBundleID(for: processID),
                  bundle.hasPrefix(searchPrefix) else { continue }

            if firstMatch == nil { firstMatch = pid }
            if processIsRunningOutput(processID) {
                runningMatch = pid
                break
            }
        }
        return runningMatch ?? firstMatch
    }

    /// Returns only CoreAudio process objects that are really producing output now
    /// (`kAudioProcessPropertyIsRunningOutput == 1`). A process object can exist for
    /// an app/helper even while it is silent; those should not create mixer rows.
    private static func runningAudioOutputProcesses() -> (pids: Set<pid_t>, bundleIDs: Set<String>) {
        guard let processIDs = audioProcessObjectIDs(logFailures: true) else { return ([], []) }

        var pids = Set<pid_t>()
        var bundleIDs = Set<String>()
        for processID in processIDs where processIsRunningOutput(processID) {
            if let pid = processPID(for: processID) {
                pids.insert(pid)
            }
            if let bundleID = processBundleID(for: processID), !bundleID.isEmpty {
                bundleIDs.insert(bundleID)
            }
        }
        return (pids, bundleIDs)
    }

    private static func audioProcessObjectIDs(logFailures: Bool = false) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress.global(kAudioHardwarePropertyProcessObjectList)
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else {
            if logFailures {
                log.info("ProcessObjectList size query failed: status=\(status, privacy: .public) size=\(dataSize, privacy: .public)")
            }
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &processIDs
        )
        guard status == noErr else {
            if logFailures {
                log.info("ProcessObjectList fetch failed: status=\(status, privacy: .public)")
            }
            return nil
        }
        return processIDs
    }

    private static func processPID(for processID: AudioObjectID) -> pid_t? {
        var pid: pid_t = 0
        var pidSize = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress.global(kAudioProcessPropertyPID)
        guard AudioObjectGetPropertyData(processID, &address, 0, nil, &pidSize, &pid) == noErr,
              pid > 0 else { return nil }
        return pid
    }

    private static func processBundleID(for processID: AudioObjectID) -> String? {
        var bundleCF: CFString?
        var bundleSize = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress.global(kAudioProcessPropertyBundleID)
        let status = withUnsafeMutablePointer(to: &bundleCF) { pointer in
            AudioObjectGetPropertyData(processID, &address, 0, nil, &bundleSize, pointer)
        }
        guard status == noErr, let bundleCF else { return nil }
        return bundleCF as String
    }

    static func processIsRunningOutput(_ processID: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress.global(kAudioProcessPropertyIsRunningOutput)
        return AudioObjectGetPropertyData(processID, &address, 0, nil, &runningSize, &running) == noErr && running == 1
    }
}
