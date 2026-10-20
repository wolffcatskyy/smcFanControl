#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Administrator installation required' >&2; exit 1; }
[[ $(sysctl -n machdep.cpu.vendor) == GenuineIntel ]] || { echo 'Intel Mac required' >&2; exit 1; }
src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Build-directory and packaged-app layouts are both supported.
bin="$src"
[[ -x "$bin/smcfan-ce-daemon" ]] || bin="$src/build"
for executable in smcfan-ce-daemon smcfanctl smcfan-ce-watchdog; do
    [[ -f "$bin/$executable" && ! -L "$bin/$executable" ]] || { echo "Missing native binary: $executable" >&2; exit 1; }
done
# A live migration must be deliberate: do not overwrite the working mp6 service.
for label in dev.wolffcatskyy.smcfan-ce-max com.crystalidea.macsfancontrol.smcwrite com.smcfancontrol.bootdaemon com.smcfancontrol.boot-fan; do
    if launchctl print "system/$label" >/dev/null 2>&1; then
        echo "Existing controller $label is active. Stop it through its documented migration/rollback procedure before installing this candidate." >&2
        exit 1
    fi
done
if pgrep -x smcFanControl >/dev/null || pgrep -f '^/Applications/Macs Fan Control.app/Contents/MacOS/Macs Fan Control$' >/dev/null; then
    echo 'Quit the legacy fan app before installing the new controller.' >&2
    exit 1
fi
base='/Library/Application Support/smcFanControlCE'
[[ ! -L "$base" ]] || exit 1
mkdir -p "$base"
chown root:wheel "$base"
chmod 700 "$base"
# Stop watchdog first so planned maintenance is not treated as a failure.
for label in dev.wolffcatskyy.smcfan-ce-watchdog dev.wolffcatskyy.smcfan-ce; do
    if launchctl print "system/$label" >/dev/null 2>&1; then launchctl bootout "system/$label"; fi
done
for executable in smcfan-ce-daemon smcfanctl smcfan-ce-watchdog; do
    install -o root -g wheel -m 755 "$bin/$executable" "$base/$executable"
done
mkdir -p /usr/local/bin
# The CLI lives outside the private configuration directory.
install -o root -g wheel -m 755 "$bin/smcfanctl" /usr/local/bin/smcfanctl
for label in dev.wolffcatskyy.smcfan-ce dev.wolffcatskyy.smcfan-ce-watchdog; do
    install -o root -g wheel -m 644 "$src/$label.plist" "/Library/LaunchDaemons/$label.plist"
    launchctl bootstrap system "/Library/LaunchDaemons/$label.plist"
    if [[ "$label" == dev.wolffcatskyy.smcfan-ce ]]; then
        ready=0
        for _ in {1..30}; do
            if /usr/local/bin/smcfanctl STATUS >/dev/null 2>&1; then ready=1; break; fi
            sleep 0.1
        done
        [[ "$ready" == 1 ]] || { echo 'Controller did not become ready' >&2; exit 1; }
    fi
done
/usr/local/bin/smcfanctl STATUS
printf '%s\n' 'Controller and independent watchdog installed for boot. Default policy leaves fans unmanaged until an administrator selects a mode.'
