# Lidlight

A focused macOS menu bar app that keeps your MacBook awake with the lid closed.

![Lidlight panel](docs/lidlight-preview.png)

## Features

- **Automatic:** stay awake on AC power and allow normal sleep on battery.
- **Stay awake:** run on battery too, with low-battery protection at 10%.
- **Allow sleep:** restore normal sleep behavior.
- Optional lid-close backlight dimming without locking your session.
- A compact Details page with local, clipboard-only diagnostics.
- Safe quit: confirms that sleep is allowed before exiting.

No automatic updater, remote-service scans, or third-party dependencies.

## Install

Requires macOS 12 or later, Apple silicon or Intel. Download `Lidlight.pkg` from this repository's Releases page, open it and follow the installer. An administrator password is required. The sun or moon icon in the menu bar opens the panel.

This community build is **not Developer ID signed or Apple notarized**. macOS may block it. If you trust the source, review the notice in System Settings → Privacy & Security. A successful build does not replace testing lid-close, power switching and brightness recovery on your own hardware.

## Build

Requires the Xcode Command Line Tools with Swift and the macOS packaging tools.

```sh
bash scripts/build.sh
```

Output: `build/Lidlight.pkg`. Without Developer ID certificates, the app uses ad-hoc signing and the installer is unsigned. The build script supports `APP_IDENTITY`, `PKG_IDENTITY` and `NOTARY_PROFILE` for signing and notarization.

## Tests

```sh
python3 Tests/CLITests.py
python3 Tests/UninstallTests.py
bash scripts/test-quit.sh
swiftc Sources/menubar/Health.swift Tests/HealthTests.swift -o /tmp/lidlight-health-tests
/tmp/lidlight-health-tests
```

These tests do not modify power settings or uninstall the app.

## Command line

```sh
lidlight status
lidlight auto
lidlight check
lidlight screen-on
```

## Uninstall

```sh
sudo /Applications/Lidlight.app/Contents/Resources/uninstall.sh
```

The root background service changes `pmset disablesleep`. Backlight control uses Apple's private DisplayServices API and may vary across hardware or macOS releases.


## About

Lidlight is the author's original macOS utility.
