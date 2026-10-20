#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Explicit physical mp6 pilot; preserves its previously measured 2141 RPM profile.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this test with sudo on mp6.' >&2; exit 1; }
[[ $(sysctl -n hw.model) == MacPro6,1 ]] || exit 1
src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
base='/Library/Application Support/smcFanControlCE'
old_label=dev.wolffcatskyy.smcfan-ce-max
old_plist="/Library/LaunchDaemons/$old_label.plist"
launchctl print "system/$old_label" >/dev/null
before=$(/usr/local/sbin/smcfan-ce-max --status)
printf '%s\n' "$before"
[[ "$before" == *'target=2141 forced=1'* ]] || { echo 'Expected existing 2141 RPM forced profile; refusing migration.' >&2; exit 1; }
current=$(printf '%s\n' "$before" | sed -E 's/.*current=([0-9]+).*/\1/')
[[ "$current" -ge 2050 && "$current" -le 2250 ]] || { echo 'Existing physical fan speed needs review.' >&2; exit 1; }
"$src/build/probe" --mp6-profile
[[ ! -e "$base/controller.conf" && ! -L "$base/controller.conf" ]] || { echo 'Candidate policy already exists; refusing to overwrite.' >&2; exit 1; }
[[ ! -L "$base" ]] || exit 1
mkdir -p "$base"
chown root:wheel "$base"
chmod 700 "$base"
backup="$base/pilot-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -m 700 "$backup"
cp "$old_plist" "$backup/"
printf '%s\n' "$before" > "$backup/before.txt"
cat > "$base/controller.conf" <<'POLICY'
BASE 0 790
MAX 0 2141
SET 0 maximum
POLICY
chmod 600 "$base/controller.conf"
"$src/build/smcfan-ce-daemon" --check-config
changed=0
rollback() {
    set +e
    for label in dev.wolffcatskyy.smcfan-ce-watchdog dev.wolffcatskyy.smcfan-ce; do
        launchctl bootout "system/$label" 2>/dev/null
        rm -f "/Library/LaunchDaemons/$label.plist"
    done
    /usr/local/sbin/smcfan-ce-max --once 2141
    cp "$backup/$old_label.plist" "$old_plist"
    launchctl bootstrap system "$old_plist"
    if [[ -f "$base/controller.conf" ]]; then mv "$base/controller.conf" "$backup/failed-controller.conf"; fi
    echo 'Pilot failed; attempted rollback to the original 2141 RPM service.' >&2
    /usr/local/sbin/smcfan-ce-max --status
}
finish() {
    local result=$?
    if [[ "$result" != 0 && "$changed" == 1 ]]; then rollback; fi
    exit "$result"
}
trap finish EXIT
launchctl bootout "system/$old_label"
changed=1
rm "$old_plist"
bash "$src/install.sh"
# Wait for independent watchdog heartbeat before accepting the new installation.
healthy=0
for _ in {1..20}; do
    status=$(/usr/local/bin/smcfanctl STATUS)
    printf '%s\n' "$status"
    if [[ "$status" == *'"target":2141'* && "$status" == *'"error":0'* && "$status" != *'"watchdog_age":-1'* ]]; then healthy=1;break;fi
    sleep 1
done
[[ "$healthy" == 1 ]] || { echo 'Controller/watchdog readiness failed' >&2; exit 1; }
# Confirm actual fan speed independently of the new service's status response.
/usr/local/sbin/smcfan-ce-max --status
printf 'Pilot installed. Rollback plist: %s/%s.plist\n' "$backup" "$old_label"
printf '%s\n' 'Next: open Cooling CE.app. Reboot and watchdog-stall recovery still need explicit verification.'
