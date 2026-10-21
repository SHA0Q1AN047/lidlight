#!/bin/bash
# 卸载 Lidlight并恢复正常睡眠。用法：sudo ./uninstall.sh
# Uninstalls Lidlight and restores normal sleep. Usage: sudo ./uninstall.sh
set -euo pipefail

if [ "$(id -u)" != "0" ]; then
    echo "请用 sudo 运行 / Run with sudo: sudo $0" >&2
    exit 1
fi

CONSOLE_UID=$(stat -f %u /dev/console)

if [ "$CONSOLE_UID" != "0" ] && launchctl print "gui/$CONSOLE_UID/com.lidlight.menubar" >/dev/null 2>&1; then
    launchctl bootout "gui/$CONSOLE_UID/com.lidlight.menubar"
fi
if launchctl print system/com.lidlight.daemon >/dev/null 2>&1; then
    launchctl bootout system/com.lidlight.daemon
fi
# launchctl may return before the daemon finishes restoring sleep.
for attempt in {1..50}; do
    if ! pgrep -x lidlightd >/dev/null; then break; fi
    sleep 0.1
done
if pgrep -x lidlightd >/dev/null; then
    echo "后台服务仍在运行，停止卸载 / Service is still running; uninstall stopped" >&2
    exit 1
fi
# Restore only a charge gate owned by Lidlight, before deleting recovery tools.
if [ -f /var/db/lidlight-charge.json ]; then
    /Library/PrivilegedHelperTools/lidlightd --restore-charging
fi
# Restore and verify sleep before deleting the recovery tools.
pmset -a disablesleep 0
pmset -g | grep -q 'SleepDisabled[[:space:]]*0'

rm -f /Library/LaunchAgents/com.lidlight.menubar.plist \
      /Library/LaunchDaemons/com.lidlight.daemon.plist \
      /Library/PrivilegedHelperTools/lidlightd \
      /var/run/lidlight-runtime.json /var/run/lidlight-charge.json /var/db/lidlight-charge.json /var/db/lidlight /var/db/lidlight-options.json \
      /var/log/lidlight.log /var/log/lidlight.log.1
# 只删我们自己建的那个软链接。
if [ -L /usr/local/bin/lidlight ] &&
   [ "$(readlink /usr/local/bin/lidlight)" = /Applications/Lidlight.app/Contents/Resources/lidlight ]; then
    rm -f /usr/local/bin/lidlight
fi
rm -rf /Applications/Lidlight.app
if pkgutil --pkg-info com.lidlight.pkg >/dev/null 2>&1; then
    pkgutil --forget com.lidlight.pkg >/dev/null
fi

echo "已卸载，睡眠设置已恢复 / Uninstalled, sleep settings restored:"
pmset -g | grep SleepDisabled
