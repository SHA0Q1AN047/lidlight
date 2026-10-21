# Charge limit implementation

The Power & display page shows battery charging only when an internal battery is present.
On Apple Silicon/macOS 26.4+, it opens the system Battery settings; it does not claim to read or change Apple's native charge-limit preference. Users select 80% there and use the system battery menu for a full charge.

On older Apple Silicon systems the daemon probes CHTE (ui32, 4 bytes, attributes D4), then CH0C (hex_, 1 byte, attributes D4). Unknown metadata, unknown values and Intel hardware are unsupported rather than guessed. The daemon writes only the charging gate, never adapter-disable keys. It reads the gate back before reporting a pause. Battery Toolkit's BSD notice is included in Resources and the packaged app.

The opt-in limit pauses at 80%, resumes at 75%, and releases its own pause on unplug. The full-once override ends at 100%, unplug after AC, daemon restart, or 24h. It does not force discharge from an existing level above 80%. Threshold control is sampled every five seconds; the limit is approximate. Before system sleep, an enabled ordinary limit pauses charging even below 80%, then reevaluates on wake. Full-once allows charging during sleep.

Ownership is journaled before writing a pause. Disable, orderly daemon shutdown and the uninstall recovery command restore only Lidlight-owned charging. A preexisting paused gate is not taken over. Uninstall aborts on a failed recovery and keeps the helper/config. SIGKILL cannot run shutdown cleanup: the journal enables recovery on restart or uninstall. No guarantee is made for charging while powered off or for conflicts with other charge controllers.

Validation: injected gate tests cover default off, hysteresis, full once, sleep/wake, unplug, restart/journal recovery, native handoff, missing readings, other-tool ownership, write failure, recovery failure and invalid commands. Uninstall uses mocked tools and verifies failed charging recovery blocks deletion. These tests do not establish physical charging behavior across Mac models. Real hardware charging writes have not been exercised in this change.
