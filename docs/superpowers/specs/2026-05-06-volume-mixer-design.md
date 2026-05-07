# Volume Mixer — Design

**Date:** 2026-05-06
**Status:** Approved (pending written-spec review)
**Platform:** macOS 14.2+ (Sonoma)
**Languages:** Swift, SwiftUI

## 1. Goal

A minimal, menu-bar-resident volume mixer for macOS. Per-app volume sliders (Windows-style), a master slider, mute toggles, and persistence keyed by bundle ID. No virtual audio driver. No system extension. Single signed `.app`.

## 2. Approach

Use Apple's Core Audio Process Tap API (`AudioHardwareCreateProcessTap`, available since macOS 14.2). For each app whose volume is non-default, create a private process tap that mutes the app's normal output, route the captured audio through a private aggregate device that pairs the tap with the current default output, and apply a gain factor in an IOProc before sending to the speakers.

This approach was chosen over a virtual-driver approach because it is sandbox-friendly (in the sense of "no kernel/system extension"), requires only a TCC permission prompt, and matches the "minimal" requirement.

## 3. Components

### 3.1 AppDiscoveryService
- Watches `NSWorkspace.shared.runningApplications` via KVO and the workspace notification center (`didLaunchApplicationNotification`, `didTerminateApplicationNotification`).
- Filters to `activationPolicy == .regular` to exclude daemons / agents.
- Publishes an `@Observable` array `[AppEntry]` where `AppEntry = (pid: pid_t, bundleID: String, name: String, icon: NSImage)`.
- Sorted by app name (case-insensitive, locale-aware).

### 3.2 VolumeStore
- `@Observable` source of truth.
- Holds `[String: AppVolumeState]` keyed by bundle ID, where `AppVolumeState = { volume: Float (0…1), muted: Bool }`.
- Holds `masterVolume: Float (0…1)` and `masterMuted: Bool`.
- Persisted to `UserDefaults` under keys `appVolumes` (JSON-encoded dictionary) and `masterVolume` / `masterMuted`. Writes are debounced 250 ms.
- Owns a `[String: AudioTapController]` map. On `setVolume(bundleID:_:)` or `setMuted(bundleID:_:)`:
  - If state ≠ `(volume: 1.0, muted: false)` and no controller exists → create one.
  - If state == `(volume: 1.0, muted: false)` and a controller exists → tear it down.
  - Otherwise → forward the new value to the existing controller.
- Master volume changes are forwarded directly to `MasterVolumeService`.

### 3.3 AudioTapController
One instance per app currently being attenuated. Owns:
- A `CATapDescription` configured with `processes = [pid]`, `isPrivate = true`, `muteBehavior = .mutedWhenTapped`, stereo mixdown (`CATapDescription(stereoMixdownOfProcesses:)`). All taps are stereo regardless of source channel count.
- A tap object id from `AudioHardwareCreateProcessTap(description)`.
- A private aggregate device id from `AudioHardwareCreateAggregateDevice(...)` whose description dictionary sets:
  - `kAudioAggregateDeviceIsPrivateKey: true`
  - `kAudioAggregateDeviceTapListKey: [{ kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: false }]`
  - sub-device list = `[currentDefaultOutputDeviceUID]`
  - `kAudioAggregateDeviceTapAutoStartKey: true`
- An IOProc id from `AudioDeviceCreateIOProcIDWithBlock` on the aggregate device.

The IOProc reads each input buffer (the tap's audio), multiplies every sample by `volume * (muted ? 0 : 1)`, and writes to the matching output buffer. `volume` and `muted` are read from atomic properties so the audio thread never blocks.

The controller listens for `kAudioHardwarePropertyDefaultOutputDevice` changes. On change: stop IOProc, destroy aggregate device, recreate aggregate device with new sub-device, recreate IOProc, start. The tap itself is not recreated.

Teardown order on dispose: stop IOProc → destroy IOProc id → destroy aggregate device → destroy tap.

### 3.4 MasterVolumeService
Thin wrapper around the default output device.
- `volume` getter/setter via `kAudioDevicePropertyVolumeScalar`. Prefers the master channel (channel 0) if the device exposes one; otherwise sets channels 1 and 2 to the same value.
- `muted` getter/setter via `kAudioDevicePropertyMute`.
- Property listeners on both so external changes (F11/F12, Sound prefs, Bluetooth headphone volume buttons) update the UI.
- Property listener on `kAudioHardwarePropertyDefaultOutputDevice` to re-bind when the user switches output device.

### 3.5 MixerView (SwiftUI)
Pure view layer. Reads `VolumeStore` and `AppDiscoveryService` via `@Environment` or `@Bindable`.

Layout:
```
┌─────────────────────────────────────┐
│  ◐ Master                  ▭▭▭▭▭▭▭ │
├─────────────────────────────────────┤
│  🟢 Spotify              ▭▭▭▭▭□□□  │
│  🔵 Safari               ▭▭▭▭▭▭▭▭  │
│  🟠 Discord (muted)      ░░░░░░░░  │
│  🎬 Final Cut Pro        ▭▭▭▭▭▭▭▭  │
└─────────────────────────────────────┘
```

- Width: fixed 320 pt.
- Row height: 28 pt.
- Header row: master (always present, always first).
- Divider between master and app list.
- App list: scrollable when total height exceeds 500 pt.
- Each app row: `[icon button (24×24)] [name (truncated, mid-truncation)] [horizontal slider] [percent label (right-aligned, fixed width to fit "100%")]`.
- Click icon → toggles mute. When muted: icon receives a slash overlay (SF Symbol composition `speaker.slash.fill` rendered atop the app icon at 60% opacity) and slider track dims to 30% opacity.
- Apps not currently producing audio: name color steps down one tier (`secondaryLabelColor`).

### 3.6 MenuBarApp
- `@main struct VolumeMixerApp: App` using `MenuBarExtra("Volume Mixer", systemImage: "speaker.wave.2") { MixerView() }.menuBarExtraStyle(.window)`.
- No regular window. The app does not appear in the Dock (`LSUIElement = true` in Info.plist).

## 4. Data Flow

```
NSWorkspace ──notification──► AppDiscoveryService ──@Observable──► MixerView
                                                                       │
                                            user drags slider          │
                                                       │               │
                                                       ▼               │
                                              VolumeStore.setVolume────┘
                                                       │
                          ┌────────────────────────────┴────────────────┐
                          │                                             │
                          ▼                                             ▼
                  master? ──► MasterVolumeService             AudioTapController
                                       │                            │
                                       ▼                            ▼
                              CoreAudio (default                IOProc applies
                              output device)                   gain → output
```

## 5. Persistence

- UserDefaults key `appVolumes`: JSON-encoded `[String: AppVolumeState]`.
- Writes debounced 250 ms via a single `DispatchSourceTimer`. Reads happen once at launch.
- Master volume is **not** persisted — the system already owns the master volume scalar, so on launch the UI reads the live value from the default output device. Persistence applies only to per-app `appVolumes`. (Earlier draft mentioned `masterVolume` / `masterMuted` UserDefaults keys; those are removed.)

## 6. Permissions and Packaging

- `Info.plist`:
  - `NSAudioCaptureUsageDescription` = "Volume Mixer captures app audio output to apply per-app volume."
  - `LSUIElement` = `true` (menu-bar-only app, no Dock icon).
  - `LSMinimumSystemVersion` = `14.2`.
- Entitlements (`VolumeMixer.entitlements`):
  - `com.apple.security.app-sandbox` = `false`.
  - `com.apple.security.device.audio-input` = `true`.
- Hardened runtime: enabled.
- Code signing: ad-hoc (`-`) for personal use; ready for Developer ID signing if distributed.
- macOS deployment target: 14.2.
- Project format: Xcode `.xcodeproj`, single target.

## 7. Error Handling

- Audio capture permission denied → `MixerView` shows "Audio access denied" with a button that opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`.
- `AudioHardwareCreateProcessTap` returns non-zero status → log to OSLog, surface a one-time toast; the app stays usable for unaffected apps.
- Aggregate device creation fails (e.g., user pulls Bluetooth headphones mid-create) → tear down tap, retry once after 500 ms with the new default output. If still fails, mark that app as unattenuable (slider becomes a no-op until next launch attempt).
- DRM-protected streams (Apple Music FairPlay, etc.) cannot be tapped — slider has no effect on them. We do not detect this proactively; the user discovers it the same way they would on any third-party tool. Documented in README.

## 8. Testing

**Unit (XCTest):**
- `VolumeStore`: setVolume / setMuted state transitions, lazy controller creation/teardown, persistence round-trip.
- `AppDiscoveryService`: filtering of non-regular apps; launch/terminate notifications produce expected `[AppEntry]` deltas (using a fake `NSWorkspace`).

**Integration (manual checklist):**
- Play audio in Spotify; drag Spotify slider to 50% → audible attenuation.
- Mute Spotify via icon → silent; unmute → restored.
- Switch output device (built-in → AirPods) while a tap is active → audio continues with attenuation preserved.
- Quit and relaunch mixer → previous per-app volumes restored.
- Master slider changes → reflected in macOS Sound prefs and vice versa.
- Deny audio capture permission on first launch → empty state with Settings button.

## 9. Out of Scope

- Input / mic device control.
- Per-output-device routing.
- Hotkeys / global shortcuts.
- Equalizer or DSP effects.
- iOS / iPadOS support.
- Backwards compatibility below macOS 14.2.

## 10. File Layout

```
volume-mixer/
├── VolumeMixer.xcodeproj/
├── VolumeMixer/
│   ├── VolumeMixerApp.swift
│   ├── Info.plist
│   ├── VolumeMixer.entitlements
│   ├── Audio/
│   │   ├── AudioTapController.swift
│   │   ├── AggregateDeviceBuilder.swift
│   │   └── MasterVolumeService.swift
│   ├── Discovery/
│   │   ├── AppDiscoveryService.swift
│   │   └── AppEntry.swift
│   ├── State/
│   │   ├── VolumeStore.swift
│   │   └── AppVolumeState.swift
│   └── UI/
│       ├── MixerView.swift
│       ├── AppRowView.swift
│       └── MasterRowView.swift
├── VolumeMixerTests/
│   ├── VolumeStoreTests.swift
│   └── AppDiscoveryServiceTests.swift
└── docs/
    └── superpowers/specs/2026-05-06-volume-mixer-design.md
```

## 11. Known Limitations

- macOS 14.2 minimum.
- DRM-protected audio streams cannot be tapped — sliders for those apps have no effect.
- First launch triggers a TCC audio-capture prompt.
- Brief (~50 ms) audio glitch when a tap installs mid-playback.
- Apps using exclusive-mode HAL output (rare; some pro audio software) may bypass the tap.
