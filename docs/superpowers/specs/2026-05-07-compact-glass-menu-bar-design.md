# Compact Glass Menu-Bar UI — Design

**Date:** 2026-05-07  
**Status:** Approved design, pending written-spec review  
**Platform:** macOS 14.2+  
**Scope:** Visual/UI behavior only. Existing audio capture, app discovery, FaceTime handling, duplicate collapse, and persistence behavior remain unchanged.

## 1. Goal

Restyle Volume Mixer so it feels like a polished macOS menu-bar utility: compact, translucent, glossy, and visually close to the macOS Control Center slider treatment without copying the full Control Center layout.

The app should be menu-bar-only. Clicking the status item opens a frosted-glass popover with compact per-app sliders. The percent text currently shown beside each slider should be removed.

## 2. Chosen Direction

Use the approved **Compact glossy mixer** direction:

- Keep the dense row layout so many apps fit in the popover.
- Use a translucent/glossy background behind the mixer content.
- Replace default SwiftUI sliders with a custom macOS-style pill slider.
- Remove right-side percentage labels.
- Launch as a menu-bar utility only; do not auto-open a separate fallback window.

This direction balances polish and utility. It borrows the slider and material language from macOS Control Center while keeping Volume Mixer’s dedicated per-app mixer shape.

## 3. User Experience

### 3.1 Launch behavior

On launch, Volume Mixer appears in the menu bar only. It does not open a normal window automatically. Clicking the menu-bar speaker icon toggles the mixer popover.

The app should not appear as a controllable app inside its own mixer list. Existing self-exclusion behavior remains.

### 3.2 Popover behavior

The menu-bar popover remains the main surface for the app. It should be compact enough for quick interactions and tall enough to show several apps before scrolling.

Expected structure:

```text
┌──────────────────────────────────┐
│  Volume Mixer                    │
│                                  │
│  [output icon]  [ glossy slider ]│
│                                  │
│  [app icon]     [ glossy slider ]│
│  [app icon]     [ glossy slider ]│
│  [app icon]     [ glossy slider ]│
│  ... scroll when needed ...      │
└──────────────────────────────────┘
```

No percentage labels are shown in rows.

### 3.3 Muting

The existing icon-click mute behavior remains:

- Clicking the app icon toggles mute.
- Muted rows become visually dimmed.
- The mute overlay remains visible on the app icon.
- A muted slider is disabled or non-interactive, matching current behavior.

## 4. Visual Design

### 4.1 Container

The mixer content uses a translucent material background with a subtle glossy look:

- Rounded popover content, approximately 20–24 pt corner radius where applicable.
- Soft translucent material, preferably SwiftUI/AppKit material APIs (`.regularMaterial`, `.ultraThinMaterial`, or an `NSVisualEffectView` wrapper if needed).
- Subtle inner border or stroke to create the glass-panel edge.
- Reduced hard dividers; spacing and material separation should do most of the work.

The target is “macOS glassy and see-through,” not a full recreation of Apple Control Center.

### 4.2 Rows

Rows stay compact, similar to the current mixer:

- App icon: roughly 24 pt.
- Row height: roughly 34–40 pt, adjusted for the custom slider.
- App names may be hidden in the compact final row if the slider/icon design needs more space, but the preferred first implementation keeps names if it still feels clean.
- Audio-active indicator can remain if it does not clutter the row.

Since percentage labels are removed, the slider gets more horizontal space.

### 4.3 Slider

Use a reusable custom slider view instead of the default SwiftUI `Slider`.

Visual target:

- Rounded white pill track, similar to macOS Control Center.
- Optional blue filled segment for the current volume portion.
- Circular white knob with subtle shadow.
- Leading icon may remain separate from the track rather than embedded inside it, to preserve app identity and mute click behavior.
- Dimmed opacity when muted/disabled.

Interaction requirements:

- Dragging updates the bound `Float` volume in `0...1`.
- Clicking/tapping the track jumps to the corresponding value.
- Values are clamped to `0...1`.
- The control should be usable inside a menu-bar popover without requiring keyboard focus.

## 5. Architecture and Components

### 5.1 `VolumeMixerApp`

Update app launch behavior:

- Keep the existing `NSStatusItem` and `NSPopover` implementation unless a `MenuBarExtra` migration becomes clearly simpler.
- Remove automatic `showFallbackWindow()` call from normal launch.
- Prefer accessory/menu-bar behavior so the app does not act like a normal window-first application.
- Keep the fallback-window code only if useful for debugging, but it should not be invoked automatically.

### 5.2 `MixerView`

Owns the visual container:

- Wrap current content in a glass background.
- Adjust popover width/height if needed for the new row spacing.
- Keep existing data flow with `AppDiscoveryService`, `VolumeStore`, and `MasterVolumeService`.
- Keep permission gate behavior unchanged.

### 5.3 `AppRowView`

Update row presentation:

- Remove the right-side percentage `Text`.
- Replace default `Slider` with the custom slider component.
- Preserve app icon button and mute behavior.
- Preserve audio-active indicator if visually clean.

### 5.4 `MasterRowView`

Apply the same custom slider styling to the master/output volume row so the whole popover feels consistent.

### 5.5 `VolumeSliderView`

Add a reusable custom SwiftUI slider component:

```swift
struct VolumeSliderView: View {
    @Binding var value: Float
    var isEnabled: Bool
}
```

Potential supporting testable helper:

```swift
struct SliderValueMapper {
    static func value(for locationX: CGFloat, width: CGFloat) -> Float
}
```

Keeping pointer-to-value math in a helper makes clamping behavior easy to unit test without UI automation.

## 6. Data Flow

No audio or persistence data flow changes are required.

```text
User drags custom slider
        │
        ▼
Binding<Float> updates
        │
        ▼
VolumeStore / MasterVolumeService existing setters
        │
        ▼
Existing CoreAudio tap/master-volume behavior
```

## 7. Error Handling

No new audio error states are introduced.

UI-specific handling:

- If material effects are unavailable or look wrong in a specific runtime context, fall back to a semi-transparent dark rounded background.
- If a row is muted, keep interaction disabled for the slider and rely on the icon to unmute.
- If the popover content exceeds available height, preserve scrolling.

## 8. Testing

### 8.1 Unit tests

Add focused tests for non-visual logic:

- Slider value mapping clamps negative positions to `0`.
- Slider value mapping clamps positions beyond width to `1`.
- Slider value mapping maps midpoint to approximately `0.5`.

Existing tests must continue passing.

### 8.2 Manual verification

Manual checklist after implementation:

1. Launch app; no normal window opens automatically.
2. Menu-bar speaker icon opens the mixer popover.
3. Popover has translucent/glossy background.
4. App rows no longer show percentage text.
5. Custom sliders respond to click and drag.
6. Muting by app icon still works.
7. Per-app audio control still works for Chrome.
8. FaceTime control still works with the previously implemented `avconferenced`/renderer path.
9. Long app lists scroll correctly.
10. Volume Mixer itself does not appear in its own app list.

## 9. Out of Scope

- Integrating into Apple’s built-in Control Center or Sound menu.
- Recreating the entire Control Center UI.
- Changing audio tap architecture.
- Adding EQ, routing, hotkeys, or device switching.
- Adding hover-only percentage labels; the selected design removes percentage labels entirely.

## 10. Open Decisions Resolved

- Visual direction: **Compact glossy mixer**.
- Percent labels: **removed**.
- App behavior: **menu-bar-only by default**.
- Built-in Control Center integration: **out of scope** because public macOS APIs do not support injecting custom controls into Apple’s Control Center.