# MagSafe Codex activity light

Opt-in controls in the dashboard: Codex running blinks amber/off at two seconds per phase, idle is green. Codex activity overrides idle-off and scheduled night mode; completion returns to off during either darkness mode, otherwise green. Default schedule 23:00–07:00 local time; equal endpoints disable the interval. All switches default off.

Independent implementation using the documented ACLC protocol values (0 system, 1 off, 3 green, 4 amber), described at https://github.com/kamenlevi/MagHue#how-it-works . No MagHue source copied. Compatible Apple Silicon MagSafe 3 only; probe metadata/read-back rather than assuming all models work. USB-C charging has no visible MagSafe LED. Charge keys are untouched.

Local Codex sessions only: tail JSONL task_started/task_complete/turn_aborted events, aggregate concurrent files, poll every five seconds on a utility queue. Missing/unreadable/truncated/overlarge evidence or stale active tasks are unknown and release the LED rather than showing false idle. Discovers recently modified logs across all date folders every 30 seconds, including resumed old threads; remote/cloud tasks without local logs are not observed. Task logs are an internal Codex format and may change. No prompts, tokens, or credentials are transmitted.

Root daemon accepts only 0–3 mode requests, journals ownership before writing ACLC, verifies values, avoids taking over external overrides, restores on shutdown/sleep/uninstall, and releases control after a 15-second heartbeat lease. App must remain running. Sleep hands control back to macOS, so night darkness is not guaranteed while the computer sleeps. Night mode persists through closed-lid operation while Lidlight keeps the Mac awake. On restoration failure reconnect the cable/restart the Mac; recovery journal remains.

Validation: MagSafeTests covers schedule boundaries, unknown activity, amber/off blinking, green/off, external ownership and restart recovery. CodexActivityTests covers start, completion, simultaneous sessions and cancellation. Universal app/daemon build. Actual LED behavior requires a connected supported MagSafe cable and physical observation; read-back alone is not optical verification. This change is not published or installed automatically.

## 1.9.10 reliability correction

The initial implementation toggled phase on both timer ticks and five-second heartbeat commands, creating extra blink edges. Phase now derives from monotonic elapsed time, and identical commands only renew the lease. A single unexpected firmware value is retried; three consecutive conflicts stop control and preserve a visible error until disabled/re-enabled. Deterministic clock tests verify cadence and recovery without touching hardware.

The installed 1.9.9 service reported failed restoration while ACLC still reported green. Comparison with the documented AppleSMC client in MagHue (Sources/MagHueCore/SMC.swift) identified a connection-type difference; LED access now uses type 0 with no user-client open/close selector calls. This is a candidate hardware compatibility correction, not yet optically validated. A successful write response is required; system handoff (0) accepts an acknowledged command because firmware may immediately report its chosen color. Explicit colors allow up to 150 ms for read-back to settle.
