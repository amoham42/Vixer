# Vixer

A minimal macOS menu-bar volume mixer with per-app sliders, mute toggles, and a master row. macOS 14.2+, zero third-party dependencies.

## Build

Requires Xcode 15.2+ and `xcodegen` (`brew install xcodegen`).

```
make build   # generate .xcodeproj and build Debug
make run     # build and launch the app
make test    # run unit tests
```

By default, the generated bundle identifier is based on your home-directory name:

```
app.<your-home-directory-name>.vixer
```

For example, `/Users/armanmohammadi` builds as `app.armanmohammadi.vixer`. Override it when needed:

```
make build VIXER_BUNDLE_ID=app.example.vixer
```

## How it works

Per-app volume on macOS is implemented via Core Audio Process Taps (`AudioHardwareCreateProcessTap`, macOS 14.2+). For each app whose volume is non-default, a private process tap mutes the app's normal output, captures its audio, and re-routes it through a private aggregate device whose IOProc applies a gain factor before forwarding to the current default output.

## Permissions

On first attenuation, macOS prompts for audio capture permission. Grant it. If denied, the app shows an "Open Privacy Settings" gate.

## Limitations

- macOS 14.2 minimum.
- DRM-protected streams (Apple Music FairPlay, etc.) cannot be tapped — sliders for those apps have no effect.
- Some pro-audio apps using exclusive HAL output may bypass the tap.
- Brief (~50ms) audio glitch when a tap installs mid-playback.
