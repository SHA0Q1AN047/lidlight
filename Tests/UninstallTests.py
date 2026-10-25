"""Exercise uninstall without root privileges or touching installed files."""
from pathlib import Path
import os
import subprocess
import tempfile

script = Path('scripts/uninstall.sh').read_text()
# Redirect the exact charge recovery executable to a stub; never run installed helpers.
script = script.replace('/Library/PrivilegedHelperTools/lidlightd --restore-charging', 'restore_charge')
script = script.replace('[ -f /var/db/lidlight-charge.json ]', '[ "${HAS_CHARGE_STATE:-0}" = 1 ]')
script = script.replace('/Library/PrivilegedHelperTools/lidlightd --restore-led', 'restore_led')
script = script.replace('[ -f /var/db/lidlight-magsafe-owned ]', '[ "${HAS_LED_STATE:-0}" = 1 ]')
preamble = '''
id() { echo 0; }
restore_led() { return "${LED_RESTORE_STATUS:-0}"; }
restore_charge() { return "${CHARGE_RESTORE_STATUS:-0}"; }
stat() { echo 501; }
launchctl() { if [ "$1" = print ]; then return 0; fi; return "${STOP_STATUS:-0}"; }
sleep() { :; }
pgrep() { return "${RUNNING_STATUS:-1}"; }
pmset() {
    if [ "$1" = -a ]; then return "${RESTORE_STATUS:-0}"; fi
    echo "SleepDisabled ${SLEEP_STATE:-0}"
}
rm() { echo removed >> "$TEST_LOG"; }
pkgutil() { return 0; }
'''
with tempfile.TemporaryDirectory() as directory:
    log = Path(directory) / 'calls'
    for values, success in [({}, True), ({'STOP_STATUS': '1'}, False),
                            ({'RUNNING_STATUS': '0'}, False),
                            ({'RESTORE_STATUS': '1'}, False),
                            ({'SLEEP_STATE': '1'}, False),
                            ({'HAS_CHARGE_STATE': '1'}, True),
                            ({'HAS_CHARGE_STATE': '1', 'CHARGE_RESTORE_STATUS': '1'}, False),
                            ({'HAS_LED_STATE': '1'}, True),
                            ({'HAS_LED_STATE': '1', 'LED_RESTORE_STATUS': '1'}, False)]:
        log.write_text('')
        result = subprocess.run(['bash'], input=preamble + script, text=True,
                                capture_output=True, env=dict(os.environ, TEST_LOG=str(log), **values))
        assert (result.returncode == 0) == success, result.stderr
        assert ('Uninstalled' in result.stdout) == success
        assert bool(log.read_text()) == success, 'Failed safety checks must prevent deletion'
print('PASS: successful uninstall, stop failure, running service, restore failure, mismatched sleep state')
