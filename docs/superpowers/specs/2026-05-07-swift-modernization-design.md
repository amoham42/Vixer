# Swift Modernization Design

## Goal

Modernize Vixer to the newest installed Apple Swift toolchain while preserving macOS 14.2 runtime support and keeping the app's current menu-bar volume mixer behavior unchanged.

## Toolchain and dependencies

The installed development environment is Xcode 26.2 with Apple Swift 6.2.3 and macOS SDK 26.2. Vixer has no third-party dependencies. The project should use Swift language mode 6 with strict concurrency checking while leaving `MACOSX_DEPLOYMENT_TARGET` and `LSMinimumSystemVersion` at 14.2.

## Observation and UI state

UI-facing mutable reference models should use modern Observation. `VolumeStore`, `MasterVolumeService`, `AppDiscoveryService`, and `MixerPresentationState` will be `@MainActor @Observable` unless a type has a clear non-main-thread responsibility. The legacy `ObservableObject`, `@Published`, and `@ObservedObject` usage in `MixerView` will be removed. View ownership will stay the same: `MixerView` owns discovery, store, master service, and expansion state, while `AppDelegate` owns the presentation reset state.

## Concurrency and audio thread safety

Swift 6 strict-concurrency errors will be fixed at the root rather than suppressed. Main-thread state changes will be actor-isolated with `@MainActor` or explicit `Task { @MainActor in ... }` hops. GCD remains acceptable for low-level CoreAudio callbacks, timers, and realtime-adjacent code where Swift actors are not suitable.

`AudioTapController` currently shares `volume` and `muted` between UI/control code and a CoreAudio IOProc. That state will be moved into a small thread-safe control object using `OSAllocatedUnfairLock`, available on macOS 13+, so reads and writes are synchronized without making the realtime callback actor-isolated. The lock will store a value-type snapshot so the IOProc can read one coherent state per buffer.

## Tests

Unit tests will migrate from XCTest to Swift Testing. Existing test coverage and behavior will be preserved. New tests will be added first for the audio control-state snapshot so the new synchronization boundary has direct test coverage.

## SwiftUI and accessibility cleanup

Minor SwiftUI hygiene items will be fixed where they do not change the compact panel design: replacing legacy string replacement APIs with modern Swift equivalents and making slider text use a dynamic text style with the existing compact rounded design. The custom slider will keep its accessibility adjustable action and value reporting.

## Verification

Final verification requires:

1. `xcodegen generate`
2. `xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'`
3. `xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'`
4. Confirm generated build invocations use Swift language mode 6 and macOS SDK 26.2 while targeting macOS 14.2.
