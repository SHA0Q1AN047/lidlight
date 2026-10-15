"""Exercise daemon options in --dry-run; never changes real power settings."""
from pathlib import Path
import subprocess
import time
import tempfile

binary = Path('build/root/Library/PrivilegedHelperTools/lidlightd').resolve()
prefix = 'com.lidlight.dryrun'

def state():
    result = subprocess.check_output(['/usr/bin/notifyutil', '-g', prefix + '.state'], text=True)
    return int(result.split()[-1])

def post(key, value=None):
    args = ['/usr/bin/notifyutil']
    if value is not None:
        args += ['-s', prefix + '.' + key, str(value)]
    subprocess.run(args + ['-p', prefix + '.' + key], check=True, capture_output=True)

def wait(expected, timeout=8):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if state() == expected:
            return
        time.sleep(.1)
    raise AssertionError(f'Expected mode {expected}; actual {state()}')

process = subprocess.Popen([str(binary), '--dry-run', '--simulate-power=ac'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
try:
    startup = []
    while True:
        line = process.stdout.readline()
        startup.append(line)
        if 'started' in line or '启动' in line:
            break
        if not line:
            raise AssertionError(f'Daemon exited before startup: {process.poll()} {startup}')
    post('set-off'); wait(2)
    post('option-deadline', int(time.time()) + 2); wait(1)
    wait(2)
    post('option-one-shot', 1); wait(1)
    post('option-one-shot', 1); wait(1)
    post('option-one-shot', 0); wait(2)
    post('option-deadline', int(time.time()) + 3600); wait(1)
    post('set-off'); wait(2)
    post('option-deadline', 2**63)
    time.sleep(.2)
    assert state() == 2, 'Invalid timer payload must not enable awake mode'
finally:
    process.terminate()
    output, _ = process.communicate(timeout=5)
assert '[dry-run] pmset -a disablesleep 1' in output
assert '[dry-run] pmset -a disablesleep 0' in output
assert process.returncode == 0, output

process = subprocess.Popen([str(binary), '--dry-run', '--simulate-power=battery', '--simulate-battery=12'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
try:
    startup = []
    while True:
        line = process.stdout.readline()
        startup.append(line)
        if 'started' in line or '启动' in line:
            break
        if not line:
            raise AssertionError(f'Daemon exited before startup: {process.poll()} {startup}')
    post('set-on'); wait(1)
    post('option-battery-limit', 20)
    time.sleep(.3)
    post('set-off'); wait(2)
finally:
    process.terminate()
    output, _ = process.communicate(timeout=5)
assert output.count('[dry-run] pmset -a disablesleep 0') >= 2, output
assert '20%' in output, output
print('PASS: real daemon timer expiry, one-shot restore, manual cancellation, invalid payload and battery threshold (dry-run only)')
