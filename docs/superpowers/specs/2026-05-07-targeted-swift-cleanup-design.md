# Targeted Swift Cleanup Design

Date: 2026-05-07

## Goal

Resolve the remaining code quality issues identified after the Swift 6 modernization without expanding app behavior. The cleanup should preserve Vixer's current user-facing behavior while improving realtime audio safety, AppKit correctness, Swift concurrency boundaries, and maintainability.

## Scope

In scope:

- Make the CoreAudio IOProc capture a smaller realtime-safe render state instead of the full `AudioTapController`.
- Protect or remove mutable diagnostic state touched by the IOProc.
- Avoid unsynchronized IOProc access to controller-owned mutable objects such as `externalRenderer`.
- Fix status-panel outside-click detection by comparing screen coordinates to `NSPanel.frame`.
- Keep status-panel size synchronized when visible app rows change while the panel is open.
- Move CoreAudio process polling work off the main actor where practical, while keeping AppKit and observable state updates on the main actor.
- Add documentation around `@unchecked Sendable` usage.
- Replace magic audio tuning values with named constants.
- Optimistically update `MasterVolumeService` observable state after successful volume/mute writes.
- Add focused Swift Testing coverage for new pure/concurrency-safe helpers.

Out of scope:

- New user-facing features.
- Redesigning the mixer UI.
- Changing audio routing semantics.
- Changing deployment target from macOS 14.2.
- Adding third-party dependencies.

## Architecture

### Realtime audio render state

Introduce a small audio render-state type used by `AudioTapController.installIOProc()`.

Responsibilities:

- Hold `AudioTapControlState` for volume/mute snapshots.
- Hold immutable render tuning such as `makeupGain`.
- Own realtime-safe access to optional diagnostic counters.
- Provide a render/write method that the IOProc can call without reaching back into the full controller.

The IOProc should capture this render state and only stable immutable values needed for logging. This reduces the risk of accidental cross-thread access to controller lifecycle state.

### External renderer lifecycle

Keep external renderer ownership clear. The render state should either:

1. Own the renderer for the full IOProc lifetime, or
2. Access it through a small synchronized box.

The preferred implementation is to move renderer ownership into render state so `AudioTapController` starts/stops it through render-state methods. This keeps `externalRenderer` from being independently mutated while the IOProc may read it.

### Panel sizing

`MixerView` should derive its desired panel size from current expansion state and app list state. It should notify `AppDelegate` when that derived size changes, not only when the expansion button is clicked.

`AppDelegate` remains responsible for applying the size to the `NSPanel` and repositioning relative to the status item.

### Outside click detection

Global mouse events should use `NSEvent.mouseLocation` for screen coordinates and compare that to `panel.frame`.

### App discovery polling

`AppDiscoveryService` remains `@MainActor` because it owns observable UI state and uses `NSWorkspace`. CoreAudio process-list scanning can run off-main, with the resulting snapshot passed back to the main actor before updating `apps`.

### Master volume writes

`MasterVolumeService` should update `volume` or `muted` after a successful write so the UI does not depend entirely on listener callback timing. Listeners still remain the source of truth for external changes.

## Error Handling

- Existing CoreAudio errors should continue to be logged rather than surfaced as user-facing errors unless behavior already does so.
- Renderer start/stop failures should preserve existing behavior.
- If off-main CoreAudio polling fails, discovery should fall back to empty audio-output sets as it does today.

## Testing

Add or update Swift Testing tests for:

- Concurrent `AudioTapControlState` access remains clamped and valid.
- Panel metric sizing remains deterministic for expanded/collapsed app counts.
- Any extracted pure helper used to compute desired panel size.
- Existing tests should continue to pass unchanged unless code organization requires minor updates.

Full verification:

- `xcodegen generate`
- `xcodebuild build -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'`
- `xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination 'platform=macOS,arch=arm64'`

## Acceptance Criteria

- No user-facing feature changes.
- Project remains Swift 6 with complete strict concurrency.
- Deployment target remains macOS 14.2.
- The IOProc no longer captures the full `AudioTapController` for routine rendering.
- Outside-click detection uses screen coordinates.
- Panel size updates when app-list-derived content size changes.
- Tests pass with Swift Testing.
