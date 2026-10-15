# Lidlight

A focused macOS menu bar app that keeps your MacBook awake with the lid closed.

![Lidlight panel](docs/lidlight-preview.png)

## Features

- Automatic, Stay awake and Allow sleep, with confirmation of actual system state.
- Timed sessions (30/60/120 minutes, custom minutes or an end date), restored by the daemon even if the panel is closed.
- One-shot sessions that end on unplug or next login; presentation mode keeps the display awake too.
- Wait for a process you own to finish, with PID-reuse protection and a seven-day safety limit.
- App, external-display and daily/weekday schedule rules, including overnight schedules.
- Manual Allow sleep pauses automation; choosing Automatic resumes it. Temporary sessions take priority over rules.
- AC-only protection and adjustable low-battery protection (10–50%) with five-point recovery hysteresis.
- Optional low-battery notifications and configurable global shortcut presets (Command–Option–L or Command–Option–Shift–L).
- Launch-at-login and restart-mode preferences.
- Pixel laptop expressions, optional menu-bar countdown, current reason and next-action explanations.
- Local activity history (40 events), power-setting conflict reporting and battery percentage-drop estimates.
- Display off, lock-and-run, emergency brightness restoration and administrator-authorized service recovery.
- Local clipboard diagnostics and safe quit/uninstall.

App/process/schedule/display rules require Lidlight to stay running. Timed deadlines and power safety run in the root service. No account, cloud sync, telemetry or automatic updater.

## Codex account quota

The optional Codex card shows remaining quota percentages and reset times. It uses the installed Codex CLI/app's documented `account/rateLimits/read` interface with your existing ChatGPT sign-in. It does not copy credentials, request an API key, create inference turns or send usage to a Lidlight server. Automatic checks run every five minutes; failures retain clearly labelled cached readings. This is Codex quota, not an exact remaining-token balance or all ChatGPT model limits. Requires a locally installed and signed-in Codex CLI or supported desktop app.

## Rules and safety

The selected manual mode is the base. App, display and schedule rules temporarily request awake mode; when all matching rules end, the base returns. Manual Allow sleep pauses these rules. Timed, one-shot, presentation and watched-process sessions take priority. Battery and AC-only protections always take precedence.

Presentation and one-shot sessions must end before starting a different session. Timer sessions can be extended. A process watch ends if its original PID exits or is reused; if Lidlight stops running, the daemon still enforces the seven-day deadline.

Screen off uses macOS display sleep and may lock according to system preferences. Lock-and-run explicitly locks. Backlight and lock features use private macOS interfaces and may vary across macOS releases. Battery estimates are percentage-point drops, not measured energy consumption. Conflict reporting cannot reliably identify the other App.

## Install

Requires macOS 12 or later, Apple silicon or Intel. Download `Lidlight.pkg` from this repository's Releases page, open it and follow the installer. An administrator password is required. The pixel laptop icon in the menu bar opens the panel.

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
swiftc Sources/Shared/PowerPolicy.swift Tests/PowerPolicyTests.swift -o /tmp/lidlight-policy-tests
/tmp/lidlight-policy-tests
swiftc Sources/menubar/Features.swift Sources/Shared/PowerPolicy.swift Tests/FeatureStateTests.swift -o /tmp/lidlight-feature-tests
/tmp/lidlight-feature-tests
# After building, exercises only the isolated dry-run notification namespace:
python3 Tests/DaemonFeatureTests.py
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
lidlight timer 60
lidlight cancel
lidlight once
lidlight presentation on
lidlight presentation off
```

These commands also work in Shortcuts using Run Shell Script, for example `/usr/local/bin/lidlight timer 60`. `lidlight until <Unix timestamp>` supports a specific end time within seven days.

## Uninstall

```sh
sudo /Applications/Lidlight.app/Contents/Resources/uninstall.sh
```

The root background service changes `pmset disablesleep`. Backlight control uses Apple's private DisplayServices API and may vary across hardware or macOS releases.


## About

Lidlight is the author's original macOS utility.
