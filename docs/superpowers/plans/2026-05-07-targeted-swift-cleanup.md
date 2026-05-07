# Targeted Swift Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve realtime audio safety, AppKit correctness, reactive panel sizing, and maintainability without changing Vixer's user-facing behavior.

**Architecture:** Keep the existing app structure, but introduce a focused render-state object for CoreAudio IOProc work and a pure panel-size helper for reactive SwiftUI/AppKit coordination. Main-actor observable services remain main-actor isolated; CoreAudio polling snapshots move off-main where practical.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreAudio, Observation, Swift Testing, XcodeGen.

---

## File Structure

- Create `Vixer/Audio/AudioTapRenderState.swift`
  - Owns IOProc-facing render state: `AudioTapControlState`, immutable makeup gain, optional renderer, and diagnostic counters.
  - Marked `@unchecked Sendable` with a justification comment because mutable shared state is internally synchronized or lifecycle-bound.
- Modify `Vixer/Audio/AudioTapControlState.swift`
  - Add `@unchecked Sendable` justification comment.
- Modify `Vixer/Audio/AudioTapController.swift`
  - Replace IOProc capture of `self` with capture of `AudioTapRenderState` plus immutable identifiers.
  - Route renderer start/stop/write through render state.
- Modify `Vixer/Discovery/AppDiscoveryService.swift`
  - Add `AudioTapTuning` constants.
  - Add `AudioOutputProcessSnapshot` and refresh path that accepts precomputed output-process snapshot.
  - Run polling CoreAudio snapshot collection off-main before applying on main actor.
- Modify `Vixer/Audio/MasterVolumeService.swift`
  - Optimistically update observable `volume`/`muted` after successful writes.
- Modify `Vixer/UI/MixerView.swift`
  - Add derived `desiredContentSize` and notify `onSizeChange` when it changes.
  - Keep expansion toggle behavior but remove sizing as a one-off side effect.
- Modify `Vixer/VixerApp.swift`
  - Fix outside-click coordinate comparison with `NSEvent.mouseLocation`.
- Modify `VixerTests/AudioTapControlStateTests.swift`
  - Add concurrent access coverage.
- Modify `VixerTests/MixerPanelMetricsTests.swift`
  - Add coverage for derived visible-count sizing scenarios.

---

### Task 1: Add concurrent control-state coverage and documentation

**Files:**
- Modify: `Vixer/Audio/AudioTapControlState.swift`
- Test: `VixerTests/AudioTapControlStateTests.swift`

- [ ] **Step 1: Write the concurrent access test**

Add this test to `VixerTests/AudioTapControlStateTests.swift` inside `AudioTapControlStateTests`:

```swift
    @Test
    func concurrentUpdatesKeepSnapshotsValid() async {
        let state = AudioTapControlState()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<1_000 {
                group.addTask {
                    state.setVolume(Float(index % 150) / 100)
                    state.setMuted(index.isMultiple(of: 2))
                    let snapshot = state.snapshot()
                    #expect(snapshot.volume >= 0)
                    #expect(snapshot.volume <= 1)
                }
            }
        }
    }
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/AudioTapControlStateTests
```

Expected: test compiles and passes. This is a characterization/stress test rather than a red/green behavior change.

- [ ] **Step 3: Add the `@unchecked Sendable` justification comment**

Change `Vixer/Audio/AudioTapControlState.swift` from:

```swift
final class AudioTapControlState: @unchecked Sendable {
```

to:

```swift
/// Thread-safe control state shared between UI/control code and CoreAudio's IOProc.
/// Safe to mark Sendable because all mutable state is protected by `OSAllocatedUnfairLock`.
final class AudioTapControlState: @unchecked Sendable {
```

- [ ] **Step 4: Re-run the focused test**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/AudioTapControlStateTests
```

Expected: `AudioTapControlStateTests` passes.

- [ ] **Step 5: Commit**

```bash
git add Vixer/Audio/AudioTapControlState.swift VixerTests/AudioTapControlStateTests.swift
git commit -m "test: cover concurrent audio tap control state"
```

---

### Task 2: Introduce IOProc render state

**Files:**
- Create: `Vixer/Audio/AudioTapRenderState.swift`
- Modify: `Vixer/Audio/AudioTapController.swift`

- [ ] **Step 1: Create `AudioTapRenderState`**

Create `Vixer/Audio/AudioTapRenderState.swift`:

```swift
import Foundation
import OSLog

/// Realtime-facing state captured by CoreAudio's IOProc.
/// Safe to mark Sendable because mutable diagnostics are protected by a lock, control state is
/// internally synchronized, and renderer lifetime is controlled by the owning `AudioTapController`.
final class AudioTapRenderState: @unchecked Sendable {
    private struct Diagnostics: Sendable {
        var didLogIOProc = false
        var peakProbeRemaining = 100
    }

    private let diagnostics = OSAllocatedUnfairLock(initialState: Diagnostics())

    let controlState = AudioTapControlState()
    let makeupGain: Float
    private let bundleID: String
    private let log: Logger
    private let renderer: TapOutputRenderer?

    init(bundleID: String, makeupGain: Float, renderer: TapOutputRenderer?) {
        self.bundleID = bundleID
        self.makeupGain = makeupGain
        self.renderer = renderer
        self.log = Logger(subsystem: "app.vixer.Vixer", category: "AudioTap")
    }

    func startRenderer() throws {
        try renderer?.start()
    }

    func stopRenderer() {
        renderer?.stop()
    }

    func render(inputBuffers: UnsafePointer<AudioBufferList>, outputBuffers: UnsafeMutablePointer<AudioBufferList>) {
        let control = controlState.snapshot()
        let inABL = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBuffers))
        let outABL = UnsafeMutableAudioBufferListPointer(outputBuffers)
        let bufferCount = min(inABL.count, outABL.count)

        noteIOProcOnce(inputBuffers: inABL.count, outputBuffers: outABL.count)

        for index in 0..<bufferCount {
            let inputBuffer = inABL[index]
            let outputBuffer = outABL[index]
            guard let inputData = inputBuffer.mData, let outputData = outputBuffer.mData else { continue }

            let sampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let input = inputData.assumingMemoryBound(to: Float.self)
            let output = outputData.assumingMemoryBound(to: Float.self)
            var peak: Float = 0
            let shouldProbePeak = peakProbeIsActive

            for sampleIndex in 0..<sampleCount {
                let sample = input[sampleIndex]
                if shouldProbePeak {
                    peak = max(peak, abs(sample))
                }
                output[sampleIndex] = AudioSampleProcessor.externalRendererSample(
                    input: sample,
                    volume: control.volume,
                    muted: control.muted,
                    makeupGain: makeupGain
                )
            }

            renderer?.writeInterleaved(output, sampleCount: sampleCount)

            for sampleIndex in 0..<sampleCount {
                output[sampleIndex] = 0
            }

            if shouldProbePeak {
                noteInputPeakIfNeeded(peak, effectiveVolume: control.muted ? 0 : control.volume)
            }
        }
    }

    func resetDiagnostics() {
        diagnostics.withLock { state in
            state.didLogIOProc = false
            state.peakProbeRemaining = 100
        }
    }

    private var peakProbeIsActive: Bool {
        diagnostics.withLock { $0.peakProbeRemaining > 0 }
    }

    private func noteIOProcOnce(inputBuffers: Int, outputBuffers: Int) {
        let shouldLog = diagnostics.withLock { state in
            guard state.didLogIOProc == false else { return false }
            state.didLogIOProc = true
            return true
        }
        guard shouldLog else { return }

        let bundleID = bundleID
        let log = log
        DispatchQueue.global(qos: .utility).async {
            log.info("IOProc fired bundleID=\(bundleID, privacy: .public) inBufs=\(inputBuffers, privacy: .public) outBufs=\(outputBuffers, privacy: .public)")
        }
    }

    private func noteInputPeakIfNeeded(_ peak: Float, effectiveVolume: Float) {
        let shouldLog = diagnostics.withLock { state in
            guard state.peakProbeRemaining > 0 else { return false }
            state.peakProbeRemaining -= 1
            guard peak > 0.0001 || state.peakProbeRemaining == 0 else { return false }
            state.peakProbeRemaining = 0
            return true
        }
        guard shouldLog else { return }

        let bundleID = bundleID
        let log = log
        DispatchQueue.global(qos: .utility).async {
            log.info("Tap input peak bundleID=\(bundleID, privacy: .public) peak=\(peak, privacy: .public) gain=\(effectiveVolume, privacy: .public)")
        }
    }
}
```

- [ ] **Step 2: Run build to expose integration errors**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: may fail because `AudioTapRenderState` is not wired yet; if it fails only for unused file warnings, continue.

- [ ] **Step 3: Wire `AudioTapController` to use render state**

In `Vixer/Audio/AudioTapController.swift`:

1. Replace these stored properties:

```swift
    private var externalRenderer: TapOutputRenderer?
    private let controlState = AudioTapControlState()
    private var ioProcLogged = false
    private var peakProbeRemaining = 100
```

with:

```swift
    private var renderState: AudioTapRenderState?
```

2. Replace `setVolume` and `setMuted` with:

```swift
    func setVolume(_ value: Float) { renderState?.controlState.setVolume(value) }
    func setMuted(_ value: Bool) { renderState?.controlState.setMuted(value) }
```

3. In `createTap(outputDeviceUID:)`, replace renderer creation/start:

```swift
        if fmtStatus == noErr {
            externalRenderer = try TapOutputRenderer(
                sampleRate: asbd.mSampleRate,
                channelCount: asbd.mChannelsPerFrame
            )
            try externalRenderer?.start()
        }
```

with:

```swift
        if fmtStatus == noErr {
            let renderer = try TapOutputRenderer(
                sampleRate: asbd.mSampleRate,
                channelCount: asbd.mChannelsPerFrame
            )
            let renderState = AudioTapRenderState(
                bundleID: bundleID,
                makeupGain: externalRendererMakeupGain,
                renderer: renderer
            )
            try renderState.startRenderer()
            self.renderState = renderState
        }
```

4. Replace the IOProc block body with:

```swift
        let renderState = renderState
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateID,
            nil
        ) { _, inInputData, _, outOutputData, _ in
            guard let renderState else { return }
            renderState.render(inputBuffers: inInputData, outputBuffers: outOutputData)
        }
```

5. In `handleDefaultOutputChanged()`, replace:

```swift
        externalRenderer?.stop()
        externalRenderer = nil
```

with:

```swift
        renderState?.stopRenderer()
        renderState = nil
```

6. In `handleDefaultOutputChanged()`, remove:

```swift
        ioProcLogged = false
        peakProbeRemaining = 100
```

7. In `teardown()`, replace:

```swift
        externalRenderer?.stop()
        externalRenderer = nil
```

with:

```swift
        renderState?.stopRenderer()
        renderState = nil
```

8. Remove `noteIOProcOnce` and `noteInputPeakIfNeeded` from `AudioTapController` after confirming no references remain.

- [ ] **Step 4: Run build**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: build succeeds under Swift 6 strict concurrency.

- [ ] **Step 5: Run audio-related tests**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/AudioSampleProcessorTests -only-testing:VixerTests/AudioTapControlStateTests
```

Expected: selected tests pass.

- [ ] **Step 6: Commit**

```bash
git add Vixer/Audio/AudioTapRenderState.swift Vixer/Audio/AudioTapController.swift
git commit -m "refactor: isolate audio tap render state"
```

---

### Task 3: Move audio discovery polling snapshot off-main and name tuning constants

**Files:**
- Modify: `Vixer/Discovery/AppDiscoveryService.swift`
- Test: `VixerTests/AppDiscoveryServiceTests.swift`

- [ ] **Step 1: Add a test for tuning constants through existing public behavior**

Ensure `VixerTests/AppDiscoveryServiceTests.swift` contains these existing expectations or add them if missing:

```swift
    @Test
    func audioTapModeUsesBoostedDeviceStreamForFaceTime() {
        #expect(AppDiscoveryService.audioTapMode(for: "com.apple.FaceTime") == .deviceStream(stream: 0, makeupGain: 100))
    }

    @Test
    func audioTapModeUsesStandardDeviceStreamForChrome() {
        #expect(AppDiscoveryService.audioTapMode(for: "com.google.Chrome") == .deviceStream(stream: 0, makeupGain: 1))
    }
```

- [ ] **Step 2: Run the focused discovery tests**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/AppDiscoveryServiceTests
```

Expected: tests pass before refactor.

- [ ] **Step 3: Add snapshot and tuning types**

In `Vixer/Discovery/AppDiscoveryService.swift`, above `@MainActor @Observable final class AppDiscoveryService`, add:

```swift
struct AudioOutputProcessSnapshot: Sendable {
    let pids: Set<pid_t>
    let bundleIDs: Set<String>

    static let empty = AudioOutputProcessSnapshot(pids: [], bundleIDs: [])
}

private enum AudioTapTuning {
    static let defaultStream = 0
    static let defaultMakeupGain: Float = 1
    static let faceTimeCallMakeupGain: Float = 100
}
```

- [ ] **Step 4: Add refresh overload that accepts a snapshot**

Replace the start of `refresh()`:

```swift
    func refresh() {
        let previousRunningBundleIDs = runningBundleIDs
        let runningOutput = Self.runningAudioOutputProcesses()
```

with:

```swift
    func refresh() {
        refresh(runningOutput: Self.runningAudioOutputProcesses())
    }

    private func refresh(runningOutput: AudioOutputProcessSnapshot) {
        let previousRunningBundleIDs = runningBundleIDs
```

Keep the remainder of the original method body inside the new private overload.

- [ ] **Step 5: Update polling task to collect snapshot off-main**

Replace `startAudioActivePolling()` with:

```swift
    private func startAudioActivePolling() {
        pollTask?.cancel()
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }

                let runningOutput = await Task.detached(priority: .utility) {
                    Self.runningAudioOutputProcesses()
                }.value

                self?.refresh(runningOutput: runningOutput)
            }
        }
    }
```

- [ ] **Step 6: Update `runningAudioOutputProcesses` return type**

Change:

```swift
    nonisolated private static func runningAudioOutputProcesses() -> (pids: Set<pid_t>, bundleIDs: Set<String>) {
        guard let processIDs = audioProcessObjectIDs(logFailures: true) else { return ([], []) }
```

to:

```swift
    nonisolated private static func runningAudioOutputProcesses() -> AudioOutputProcessSnapshot {
        guard let processIDs = audioProcessObjectIDs(logFailures: true) else { return .empty }
```

and change the return at the end from:

```swift
        return (pids, bundleIDs)
```

to:

```swift
        return AudioOutputProcessSnapshot(pids: pids, bundleIDs: bundleIDs)
```

- [ ] **Step 7: Replace magic tuning values**

Replace `audioOwnershipOverrides` with:

```swift
    nonisolated private static let audioOwnershipOverrides: [String: AudioOwnershipOverride] = [
        "com.apple.FaceTime": AudioOwnershipOverride(
            ownerBundlePrefix: "com.apple.avconferenced",
            tapMode: .deviceStream(stream: AudioTapTuning.defaultStream, makeupGain: AudioTapTuning.faceTimeCallMakeupGain)
        ),
        "com.google.Chrome": AudioOwnershipOverride(
            ownerBundlePrefix: "com.google.Chrome",
            tapMode: .deviceStream(stream: AudioTapTuning.defaultStream, makeupGain: AudioTapTuning.defaultMakeupGain)
        )
    ]
```

Replace `audioTapMode(for:)` fallback with:

```swift
        audioOwnershipOverrides[bundleID]?.tapMode ?? .deviceStream(
            stream: AudioTapTuning.defaultStream,
            makeupGain: AudioTapTuning.defaultMakeupGain
        )
```

- [ ] **Step 8: Run focused discovery tests**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/AppDiscoveryServiceTests
```

Expected: discovery tests pass.

- [ ] **Step 9: Commit**

```bash
git add Vixer/Discovery/AppDiscoveryService.swift VixerTests/AppDiscoveryServiceTests.swift
git commit -m "refactor: snapshot audio discovery polling"
```

---

### Task 4: Make panel sizing reactive and fix outside-click coordinates

**Files:**
- Modify: `Vixer/UI/MixerView.swift`
- Modify: `Vixer/VixerApp.swift`
- Test: `VixerTests/MixerPanelMetricsTests.swift`

- [ ] **Step 1: Add panel sizing metric tests**

Add these tests to `VixerTests/MixerPanelMetricsTests.swift` inside `MixerPanelMetricsTests`:

```swift
    @Test
    func expandedContentSizeChangesWithVisibleAppCount() {
        let oneApp = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 1, canExpand: true)
        let fourApps = MixerPanelMetrics.contentSize(isExpanded: true, visibleAppCount: 4, canExpand: true)

        #expect(fourApps.height > oneApp.height)
        #expect(fourApps.width == oneApp.width)
    }

    @Test
    func collapsedContentSizeIgnoresVisibleAppCount() {
        let oneApp = MixerPanelMetrics.contentSize(isExpanded: false, visibleAppCount: 1, canExpand: true)
        let manyApps = MixerPanelMetrics.contentSize(isExpanded: false, visibleAppCount: 20, canExpand: true)

        #expect(oneApp == manyApps)
    }
```

- [ ] **Step 2: Run focused metrics tests**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/MixerPanelMetricsTests
```

Expected: tests pass before code refactor.

- [ ] **Step 3: Add derived desired content size to `MixerView`**

In `Vixer/UI/MixerView.swift`, add this computed property near `expandedListHeight`:

```swift
    private var desiredContentSize: CGSize {
        MixerPanelMetrics.contentSize(
            isExpanded: expansionState.isExpanded,
            visibleAppCount: expansionState.isExpanded ? expandedApps.count : collapsedApps.count,
            canExpand: canExpand
        )
    }
```

- [ ] **Step 4: Notify on derived content size changes**

Add this modifier after the existing `.onChange(of: presentationState.resetToken)` modifier:

```swift
        .onChange(of: desiredContentSize) { _, newSize in
            onSizeChange(newSize)
        }
```

- [ ] **Step 5: Simplify expansion toggle**

Replace `toggleExpansion()` with:

```swift
    private func toggleExpansion() {
        _ = expansionState.toggle()
        onSizeChange(desiredContentSize)
    }
```

- [ ] **Step 6: Fix outside-click coordinate comparison**

In `Vixer/VixerApp.swift`, replace:

```swift
                if !panel.frame.contains(event.locationInWindow) {
                    self.closeStatusPanel()
                }
```

with:

```swift
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.closeStatusPanel()
                }
```

If `event` becomes unused, change the closure parameter from `event in` to `_ in`.

- [ ] **Step 7: Run build and focused tests**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/MixerPanelMetricsTests
```

Expected: build succeeds and metrics tests pass.

- [ ] **Step 8: Commit**

```bash
git add Vixer/UI/MixerView.swift Vixer/VixerApp.swift VixerTests/MixerPanelMetricsTests.swift
git commit -m "fix: keep mixer panel sizing reactive"
```

---

### Task 5: Optimistically update master volume observable state

**Files:**
- Modify: `Vixer/Audio/MasterVolumeService.swift`

- [ ] **Step 1: Update `setVolume` implementation**

Replace `setVolume(_:)` with:

```swift
    func setVolume(_ value: Float) {
        let clamped = UnitInterval.clamp(value)
        var didSetAnyChannel = false

        for ch in volumeChannels {
            var v = clamped
            var address = volumeAddress(channel: ch)
            let status = AudioObjectSetPropertyData(
                currentDeviceID, &address, 0, nil,
                UInt32(MemoryLayout<Float>.size), &v
            )
            if status == noErr {
                didSetAnyChannel = true
            } else {
                Self.log.error("setVolume ch=\(ch) failed status=\(status)")
            }
        }

        if didSetAnyChannel {
            volume = clamped
        }
    }
```

- [ ] **Step 2: Update `setMuted` implementation**

Replace `setMuted(_:)` with:

```swift
    func setMuted(_ value: Bool) {
        var m: UInt32 = value ? 1 : 0
        var address = AudioObjectPropertyAddress.output(kAudioDevicePropertyMute)
        let status = AudioObjectSetPropertyData(
            currentDeviceID, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &m
        )
        if status == noErr {
            muted = value
        } else {
            Self.log.error("setMuted failed status=\(status)")
        }
    }
```

- [ ] **Step 3: Run build**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Vixer/Audio/MasterVolumeService.swift
git commit -m "fix: update master volume state after writes"
```

---

### Task 6: Final verification and cleanup review

**Files:**
- Review all modified files.

- [ ] **Step 1: Generate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: `Created project at .../Vixer.xcodeproj`.

- [ ] **Step 2: Run full build**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run full test suite**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: Swift Testing reports all tests passed.

- [ ] **Step 4: Verify build settings remain correct**

Run:

```bash
xcodebuild -project Vixer.xcodeproj -scheme Vixer -showBuildSettings 2>/dev/null | rg "SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY|MACOSX_DEPLOYMENT_TARGET|SDKROOT"
```

Expected includes:

```text
MACOSX_DEPLOYMENT_TARGET = 14.2
SDKROOT = /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_VERSION = 6.0
```

- [ ] **Step 5: Search for cleanup regressions**

Run:

```bash
rg -n "import XCTest|XCTestCase|XCTAssert|@Published|ObservableObject|@ObservedObject|foregroundColor|\.cornerRadius\(|event\.locationInWindow" Vixer VixerTests --glob '!Assets.xcassets/**' || true
git diff --check
```

Expected: no matches for legacy patterns that were removed; `git diff --check` exits successfully.

- [ ] **Step 6: Commit any final fixes if needed**

If Step 5 reveals necessary fixes, edit the relevant files, rerun Steps 1-5, then commit:

```bash
git add Vixer VixerTests
git commit -m "chore: finalize targeted swift cleanup"
```

If there are no changes after the previous task commits, do not create an empty commit.
