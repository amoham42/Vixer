# Swift Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Vixer to the newest installed Swift toolchain practices: Swift 6 language mode, strict concurrency, modern Observation, Swift Testing, and preserved macOS 14.2 deployment support.

**Architecture:** Keep UI/state ownership unchanged, but make UI-facing observable classes main-actor isolated. Isolate realtime audio control data behind a small synchronous lock-backed value snapshot so Swift 6 concurrency errors are fixed without making CoreAudio callbacks actor-isolated.

**Tech Stack:** Xcode 26.2, Apple Swift 6.2.3, macOS SDK 26.2, SwiftUI, Observation, Swift Testing, CoreAudio, OSAllocatedUnfairLock, XcodeGen. No third-party libraries.

---

## File Structure

- Modify `project.yml`: set Swift language mode 6, enable strict concurrency, keep macOS deployment target 14.2.
- Create `Vixer/Audio/AudioTapControlState.swift`: small lock-backed state holder for `volume` and `muted`.
- Modify `Vixer/Audio/AudioTapController.swift`: use `AudioTapControlState`, replace app-level main dispatch with main-actor hop.
- Modify `Vixer/State/VolumeStore.swift`: mark as `@MainActor @Observable`, replace write timer with main-actor-safe debounced task.
- Modify `Vixer/Audio/MasterVolumeService.swift`: mark as `@MainActor @Observable`, replace redundant main dispatch in callbacks.
- Modify `Vixer/Discovery/AppDiscoveryService.swift`: mark as `@MainActor @Observable`, use a main-actor-compatible polling task instead of `DispatchSourceTimer` on `.main`.
- Modify `Vixer/UI/MixerView.swift`: convert `MixerPresentationState` to `@MainActor @Observable`; remove `@ObservedObject`.
- Modify `Vixer/UI/MasterRowView.swift`: bind to a main-actor observable service.
- Modify `Vixer/UI/VolumeSliderView.swift`: modern string API and dynamic font style.
- Modify every file under `VixerTests/`: migrate unit tests from XCTest to Swift Testing.

---

### Task 1: Toolchain Settings

**Files:**
- Modify: `project.yml:8-10`

- [ ] **Step 1: Verify the installed newest Swift toolchain**

Run:

```bash
xcrun swift --version
xcodebuild -version
xcodebuild -showsdks | rg 'macOS|iOS|tvOS|watchOS|visionOS'
```

Expected: Swift reports Apple Swift 6.2.3 and Xcode reports 26.2.

- [ ] **Step 2: Update project settings**

Change `project.yml` base settings to:

```yaml
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    SWIFT_APPROACHABLE_CONCURRENCY: YES
    MACOSX_DEPLOYMENT_TARGET: "14.2"
```

Do not change `MACOSX_DEPLOYMENT_TARGET` or `LSMinimumSystemVersion` away from 14.2.

- [ ] **Step 3: Regenerate and verify current strict-concurrency failure**

Run:

```bash
xcodegen generate
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected before later tasks: build fails with concurrency errors. Keep the output as the red baseline.

- [ ] **Step 4: Commit settings after later green verification**

After Task 6 passes, commit this together with the code changes:

```bash
git add project.yml Vixer.xcodeproj
git commit -m "chore: enable Swift 6 strict concurrency"
```

---

### Task 2: Thread-Safe Audio Tap Control State

**Files:**
- Create: `Vixer/Audio/AudioTapControlState.swift`
- Modify: `Vixer/Audio/AudioTapController.swift:25-71,148-180`
- Test: `VixerTests/AudioTapControlStateTests.swift`

- [ ] **Step 1: Write the failing Swift Testing test**

Create `VixerTests/AudioTapControlStateTests.swift`:

```swift
import Testing
@testable import Vixer

struct AudioTapControlStateTests {
    @Test func defaultSnapshotUsesFullVolumeAndUnmuted() {
        let state = AudioTapControlState()

        let snapshot = state.snapshot()

        #expect(snapshot.volume == 1.0)
        #expect(snapshot.muted == false)
    }

    @Test func setVolumeClampsToUnitInterval() {
        let state = AudioTapControlState()

        state.setVolume(1.5)
        #expect(state.snapshot().volume == 1.0)

        state.setVolume(-0.25)
        #expect(state.snapshot().volume == 0.0)
    }

    @Test func setMutedUpdatesSnapshot() {
        let state = AudioTapControlState()

        state.setMuted(true)

        #expect(state.snapshot().muted == true)
    }

    @Test func setSnapshotUpdatesVolumeAndMutedTogether() {
        let state = AudioTapControlState()

        state.set(volume: 0.25, muted: true)

        let snapshot = state.snapshot()
        #expect(snapshot.volume == 0.25)
        #expect(snapshot.muted == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodegen generate
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/AudioTapControlStateTests
```

Expected: FAIL because `AudioTapControlState` does not exist.

- [ ] **Step 3: Implement minimal lock-backed state**

Create `Vixer/Audio/AudioTapControlState.swift`:

```swift
import Foundation
import os.lock

struct AudioTapControlSnapshot: Sendable, Equatable {
    let volume: Float
    let muted: Bool
}

final class AudioTapControlState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: AudioTapControlSnapshot(volume: 1.0, muted: false))

    func snapshot() -> AudioTapControlSnapshot {
        lock.withLock { $0 }
    }

    func setVolume(_ value: Float) {
        lock.withLock { snapshot in
            snapshot = AudioTapControlSnapshot(volume: UnitInterval.clamp(value), muted: snapshot.muted)
        }
    }

    func setMuted(_ value: Bool) {
        lock.withLock { snapshot in
            snapshot = AudioTapControlSnapshot(volume: snapshot.volume, muted: value)
        }
    }

    func set(volume: Float, muted: Bool) {
        lock.withLock { snapshot in
            snapshot = AudioTapControlSnapshot(volume: UnitInterval.clamp(volume), muted: muted)
        }
    }
}
```

This is the one intentional `@unchecked Sendable`: the reference type is safe because all mutable state is held inside `OSAllocatedUnfairLock`.

- [ ] **Step 4: Update `AudioTapController` to use snapshots**

Replace stored mutable audio control properties with:

```swift
private let controlState = AudioTapControlState()
```

Replace setters with:

```swift
func setVolume(_ value: Float) { controlState.setVolume(value) }
func setMuted(_ value: Bool) { controlState.setMuted(value) }
```

Inside the IOProc closure, read once per callback:

```swift
let control = self.controlState.snapshot()
let gain: Float = control.muted ? 0.0 : control.volume
```

Pass `control.volume` and `control.muted` into `AudioSampleProcessor.externalRendererSample(...)`.

- [ ] **Step 5: Verify green**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -only-testing:VixerTests/AudioTapControlStateTests
```

Expected: PASS.

---

### Task 3: Modern Observation and Main Actor Isolation

**Files:**
- Modify: `Vixer/UI/MixerView.swift`
- Modify: `Vixer/State/VolumeStore.swift`
- Modify: `Vixer/Audio/MasterVolumeService.swift`
- Modify: `Vixer/Discovery/AppDiscoveryService.swift`
- Modify: `Vixer/UI/MasterRowView.swift`
- Modify: `Vixer/VixerApp.swift`

- [ ] **Step 1: Run strict build to identify current red errors**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: FAIL with Swift 6 concurrency/observation errors.

- [ ] **Step 2: Convert `MixerPresentationState`**

In `Vixer/UI/MixerView.swift`, add Observation import and replace the class with:

```swift
import Observation
import SwiftUI

@MainActor
@Observable
final class MixerPresentationState {
    var resetToken = UUID()

    func resetForNewPresentation() {
        resetToken = UUID()
    }
}
```

Replace:

```swift
@ObservedObject var presentationState = MixerPresentationState()
```

with:

```swift
let presentationState: MixerPresentationState
```

Add an explicit initializer if needed:

```swift
init(
    presentationState: MixerPresentationState = MixerPresentationState(),
    onSizeChange: @escaping (CGSize) -> Void = { _ in }
) {
    self.presentationState = presentationState
    self.onSizeChange = onSizeChange
}
```

- [ ] **Step 3: Main-actor isolate observable services**

Add `@MainActor` immediately above each `@Observable`:

```swift
@MainActor
@Observable
final class VolumeStore { ... }
```

```swift
@MainActor
@Observable
final class MasterVolumeService { ... }
```

```swift
@MainActor
@Observable
final class AppDiscoveryService { ... }
```

- [ ] **Step 4: Replace main-dispatch callbacks**

In `MasterVolumeService.addListener`, replace:

```swift
let block: AudioObjectPropertyListenerBlock = { _, _ in
    DispatchQueue.main.async { handler() }
}
```

with:

```swift
let block: AudioObjectPropertyListenerBlock = { _, _ in
    Task { @MainActor in handler() }
}
```

In `AudioTapController.installDefaultDeviceListener`, replace:

```swift
let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
    DispatchQueue.main.async { self?.handleDefaultOutputChanged() }
}
```

with:

```swift
let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
    Task { @MainActor in self?.handleDefaultOutputChanged() }
}
```

Then mark controller lifecycle methods that rebuild CoreAudio objects as main-actor isolated where needed:

```swift
@MainActor
private func handleDefaultOutputChanged() { ... }
```

```swift
@MainActor
func teardown() { ... }
```

Only add `@MainActor` to methods called from UI/control lifecycle, not the IOProc callback helpers.

- [ ] **Step 5: Replace `VolumeStore` write timer with a task**

Replace:

```swift
private var writeTimer: DispatchSourceTimer?
```

with:

```swift
private var writeTask: Task<Void, Never>?
```

Replace `scheduleWrite()` with:

```swift
private func scheduleWrite() {
    writeTask?.cancel()
    writeTask = Task { [weak self] in
        do {
            try await Task.sleep(for: .seconds(writeDebounce))
        } catch {
            return
        }
        await self?.write()
    }
}
```

Replace deinit/flush cancellation with `writeTask?.cancel()` and `writeTask = nil`.

- [ ] **Step 6: Replace discovery poll timer with a task**

Replace:

```swift
private var pollTimer: DispatchSourceTimer?
```

with:

```swift
private var pollTask: Task<Void, Never>?
```

Replace `startAudioActivePolling()` with:

```swift
private func startAudioActivePolling() {
    pollTask?.cancel()
    pollTask = Task { [weak self] in
        while Task.isCancelled == false {
            do {
                try await Task.sleep(for: .seconds(pollInterval))
            } catch {
                return
            }
            await self?.refresh()
        }
    }
}
```

Replace deinit cancellation with `pollTask?.cancel()`.

- [ ] **Step 7: Verify strict build progresses**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: either PASS or a smaller set of specific Swift 6 errors to fix before continuing.

---

### Task 4: Migrate XCTest Unit Tests to Swift Testing

**Files:**
- Modify: `VixerTests/AppDiscoveryServiceTests.swift`
- Modify: `VixerTests/AppVolumeStateTests.swift`
- Modify: `VixerTests/AudioSampleProcessorTests.swift`
- Modify: `VixerTests/FloatRingBufferTests.swift`
- Modify: `VixerTests/MixerPanelMetricsTests.swift`
- Modify: `VixerTests/UnitIntervalTests.swift`
- Modify: `VixerTests/VixerIconTests.swift`
- Modify: `VixerTests/VolumeSliderViewTests.swift`
- Modify: `VixerTests/VolumeStoreTests.swift`

- [ ] **Step 1: Convert imports and suite declarations**

For every test file, replace:

```swift
import XCTest
@testable import Vixer

final class SomeTests: XCTestCase {
```

with:

```swift
import Testing
@testable import Vixer

@MainActor
struct SomeTests {
```

Use `@MainActor` on suites that instantiate main-actor application types such as `VolumeStore`, `AppDiscoveryService`, `MasterVolumeService`, or UI-adjacent helpers. Pure value suites may omit it, but using it consistently for this app test target is acceptable.

- [ ] **Step 2: Convert setup/teardown in `VolumeStoreTests`**

Replace XCTest setup/teardown with init/deinit:

```swift
@MainActor
struct VolumeStoreTests {
    private let defaults: UserDefaults
    private let suiteName: String

    init() throws {
        suiteName = "VolumeStoreTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
```

- [ ] **Step 3: Convert test methods**

For every method named:

```swift
func test_nameOfBehavior() {
```

convert to:

```swift
@Test func nameOfBehavior() {
```

Drop the `test_` prefix and use lower camel case.

- [ ] **Step 4: Convert assertions**

Use these exact mappings:

```swift
XCTAssertEqual(a, b)              -> #expect(a == b)
XCTAssertEqual(a, b, accuracy: x) -> #expect(abs(a - b) <= x)
XCTAssertNil(value)               -> #expect(value == nil)
XCTAssertTrue(value)              -> #expect(value == true)
XCTAssertFalse(value)             -> #expect(value == false)
XCTFail("message")               -> Issue.record("message")
```

Replace force unwraps in tests with `#require`:

```swift
let raw = try #require(defaults.data(forKey: "appVolumes"))
let decoded = try JSONDecoder().decode([String: AppVolumeState].self, from: raw)
```

- [ ] **Step 5: Run migrated tests**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: all tests pass with Swift Testing discovery. If XCTest framework remains linked by the generated test bundle but no XCTest tests exist, that is acceptable as long as no test source imports XCTest.

---

### Task 5: SwiftUI and API Hygiene Cleanup

**Files:**
- Modify: `Vixer/UI/VolumeSliderView.swift`
- Modify: `Vixer/UI/MixerView.swift`

- [ ] **Step 1: Update slider accessibility string API**

Replace:

```swift
.accessibilityValue(SliderGeometry.percentageText(for: value).replacingOccurrences(of: "%", with: " percent"))
```

with:

```swift
.accessibilityValue(SliderGeometry.percentageText(for: value).replacing("%", with: " percent"))
```

- [ ] **Step 2: Make slider percent text use a dynamic text style**

Replace:

```swift
.font(.system(size: 10, weight: .semibold, design: .rounded))
```

with:

```swift
.font(.caption2.weight(.semibold).width(.standard))
```

If `.width(.standard)` is unavailable for the deployment target, use:

```swift
.font(.caption2.weight(.semibold))
```

- [ ] **Step 3: Check for obsolete SwiftUI patterns**

Run:

```bash
rg -n "ObservableObject|@Published|@ObservedObject|@StateObject|@EnvironmentObject|foregroundColor|cornerRadius|Task\.sleep\(nanoseconds:|replacingOccurrences\(" Vixer
```

Expected: no matches for the legacy observation APIs or old string replacement in app code. Existing `RoundedRectangle(cornerRadius:)` constructor usage is allowed because the rule only forbids the deprecated `.cornerRadius()` modifier.

---

### Task 6: Final Verification and Commits

**Files:**
- All modified files

- [ ] **Step 1: Regenerate project**

Run:

```bash
xcodegen generate
```

Expected: project generation succeeds.

- [ ] **Step 2: Verify strict Swift 6 build**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify tests**

Run:

```bash
xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'
```

Expected: all tests pass.

- [ ] **Step 4: Verify toolchain and deployment target in build output**

Run:

```bash
xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64' -showBuildTimingSummary | tee /tmp/vixer-swift6-build.log
rg -- '-swift-version 6|MacOSX26\.2\.sdk|arm64-apple-macos14\.2|MACOSX_DEPLOYMENT_TARGET = 14\.2' /tmp/vixer-swift6-build.log
```

Expected: output confirms Swift 6 mode, SDK 26.2, and macOS 14.2 deployment target.

- [ ] **Step 5: Check git diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: no whitespace errors; diff only contains planned modernization changes.

- [ ] **Step 6: Commit implementation**

Run:

```bash
git add project.yml Vixer.xcodeproj Vixer VixerTests docs/superpowers/plans/2026-05-07-swift-modernization.md
git commit -m "chore: modernize project for Swift 6"
```

---

## Self-Review

- Spec coverage: toolchain, Observation, concurrency, tests, SwiftUI cleanup, and verification each have tasks.
- Placeholder scan: no TBD/TODO/fill-in placeholders are present.
- Type consistency: `AudioTapControlState`, `AudioTapControlSnapshot`, and converted test names are used consistently.
