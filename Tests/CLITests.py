"""Run the actual CLI with fake system tools; never change power settings."""
import os
from pathlib import Path
import subprocess
import tempfile

source = Path('Resources/lidlight').read_text()
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    tool = root / 'tool'
    tool.write_text('''#!/bin/sh
case "$(basename "$0")" in
notifyutil)
    if [ "$1" = -p ]; then exit "${POST_STATUS:-0}"; fi
    echo "state ${MODE:-invalid}"
    ;;
pgrep) exit "${SERVICE_STATUS:-0}" ;;
pmset)
    echo "$*" >> "$CALL_LOG"
    if [ "$2" = ps ]; then
        echo "Now drawing from 'AC Power'"
        echo '100%'
    else echo "SleepDisabled ${SLEEP_STATE:-1}"; exit "${PMSET_STATUS:-0}"; fi
    ;;
defaults) echo 1.6.0 ;;
sleep) : ;;
esac
''')
    tool.chmod(0o755)
    for name in ('notifyutil', 'pgrep', 'pmset', 'defaults', 'sleep'):
        (root / name).symlink_to(tool)
        source = source.replace('/usr/bin/' + name, str(root / name))
    cli = root / 'cli'
    cli.write_text(source)
    log = root / 'calls'

    def run(command='status', args=(), **values):
        log.write_text('')
        env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'],
                   CALL_LOG=str(log), **values)
        return subprocess.run(['sh', str(cli), command, *args], env=env,
                              capture_output=True, text=True, timeout=5)

    result = run()
    assert result.returncode == 0 and 'unknown' in result.stdout
    assert log.read_text().splitlines().count('-g ps') == 1
    assert 'Mode:   未知 unknown' in run(PMSET_STATUS='1').stdout
    assert 'Mode:   未知 unknown' in run(SLEEP_STATE='invalid').stdout
    assert '正常睡眠' in run(SLEEP_STATE='0').stdout
    for command, mode in [('auto', '0'), ('on', '1'), ('off', '2')]:
        assert run(command, MODE=mode).returncode == 0
    result = run('on', MODE='0')
    assert result.returncode == 1 and 'Timed out' in result.stderr
    result = run('on', POST_STATUS='1')
    assert result.returncode == 1 and 'Could not send' in result.stderr
    result = run('on', SERVICE_STATUS='1')
    assert result.returncode == 1 and 'not running' in result.stderr
    assert run('invalid').returncode == 2
    for command in ['timer', 'until', 'presentation']:
        assert run(command).returncode == 2
    for bad in ['-1', '0', '10081', '999999999999999999999999', 'oops']:
        assert run('timer', args=[bad]).returncode == 2
    assert run('timer', args=['30']).returncode == 0
    assert run('until', args=['999999999999999999']).returncode == 2
    assert run('presentation', args=['invalid']).returncode == 2
    assert run('once').returncode == 0
    assert run('cancel').returncode == 0
print('PASS: unknown state, single power snapshot, three modes, timeout, request failure, stopped service, usage')
