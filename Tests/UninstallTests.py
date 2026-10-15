"""Exercise uninstall without root privileges or touching installed files."""
from pathlib import Path
import os
import subprocess
import tempfile

script = Path('scripts/uninstall.sh').read_text()
preamble = '''
id() { echo 0; }
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
                            ({'SLEEP_STATE': '1'}, False)]:
        log.write_text('')
        result = subprocess.run(['bash'], input=preamble + script, text=True,
                                capture_output=True, env=dict(os.environ, TEST_LOG=str(log), **values))
        assert (result.returncode == 0) == success, result.stderr
        assert ('Uninstalled' in result.stdout) == success
        assert bool(log.read_text()) == success, 'Failed safety checks must prevent deletion'
print('PASS: successful uninstall, stop failure, running service, restore failure, mismatched sleep state')
