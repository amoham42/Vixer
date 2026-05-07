# Vixer

Vixer is a lightweight macOS menu-bar volume mixer. It adds per-app sliders and mute toggles alongside a master volume row, using native macOS/Core Audio APIs and no third-party runtime dependencies.

## Requirements

- macOS 14.2 or newer
- Xcode 15.2 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Install XcodeGen with Homebrew:

```sh
brew install xcodegen
```

## Build, run, and test

```sh
make build   # generate Vixer.xcodeproj and build Debug
make run     # build and launch Vixer
make test    # run unit tests
make clean   # remove generated build/project output
```

The generated Xcode project is intentionally not checked in; `make build`, `make run`, and `make test` regenerate it from `project.yml`.

## Bundle identifier

By default, local builds derive a bundle identifier from your macOS home-directory name:

```txt
app.<your-home-directory-name>.vixer
```

For example, a user with home directory `/Users/armanmohammadi` builds as:

```txt
app.armanmohammadi.vixer
```

You can override the app bundle identifier when building:

```sh
make build VIXER_BUNDLE_ID=app.example.vixer
```

The test bundle identifier defaults to `<VIXER_BUNDLE_ID>.tests` and can also be overridden:

```sh
make test VIXER_BUNDLE_ID=app.example.vixer VIXER_TEST_BUNDLE_ID=app.example.vixer.tests
```

Changing the bundle identifier makes macOS treat the app as a different application for privacy permissions, so you may need to grant audio capture permission again.

## Permissions

Vixer needs macOS audio capture permission. The first time you adjust an app below full volume or mute it, macOS may prompt for permission. Grant access when prompted.

If permission is denied, Vixer shows an “Open Privacy Settings” gate. You can also reset the permission for a local build with:

```sh
tccutil reset Microphone <bundle-id>
```

Example:

```sh
tccutil reset Microphone app.armanmohammadi.vixer
```

Then relaunch Vixer and grant permission when prompted.

## How it works

Per-app volume control on macOS is implemented with Core Audio Process Taps, available on macOS 14.2 and newer.

For each app whose volume is non-default, Vixer:

1. Resolves the audio-producing process.
2. Creates a private Core Audio process tap for that process.
3. Mutes the app’s normal output while tapped.
4. Routes captured audio through a private aggregate device.
5. Applies the requested gain/mute state inside the aggregate device IOProc.
6. Forwards the adjusted audio to the current default output device.

When the default output device changes, Vixer rebuilds the tap/aggregate route for the new output device.

## Limitations

- macOS 14.2 is required for Core Audio Process Taps.
- DRM-protected streams, such as FairPlay-protected Apple Music content, cannot be tapped.
- Some pro-audio apps using exclusive HAL output may bypass the tap.
- Installing or rebuilding a tap can cause a brief audio glitch.
- Changing bundle identifiers can require resetting or re-granting macOS privacy permissions.
