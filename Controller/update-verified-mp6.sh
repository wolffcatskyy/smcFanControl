#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Bounded update + real auto/manual regression + real peer-authorization tests.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run with sudo on mp6'; exit 1; }
[[ $(sysctl -n hw.model) == MacPro6,1 ]] || exit 1
src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
old_plist='/Library/Application Support/smcFanControlCE/pilot-backup-20261020-113219/dev.wolffcatskyy.smcfan-ce-max.plist'
[[ -f "$old_plist" && -x "$src/../recovery-max" ]] || { echo 'Verified fixed-speed rollback files are required'; exit 1; }
rollback() {
    set +e
    for label in dev.wolffcatskyy.smcfan-ce-watchdog dev.wolffcatskyy.smcfan-ce; do
        launchctl bootout "system/$label" 2>/dev/null
        rm -f "/Library/LaunchDaemons/$label.plist"
    done
    install -o root -g wheel -m 755 "$src/../recovery-max" /usr/local/sbin/smcfan-ce-max
    /usr/local/sbin/smcfan-ce-max --once 2141
    cp "$old_plist" /Library/LaunchDaemons/dev.wolffcatskyy.smcfan-ce-max.plist
    chown root:wheel /Library/LaunchDaemons/dev.wolffcatskyy.smcfan-ce-max.plist
    chmod 644 /Library/LaunchDaemons/dev.wolffcatskyy.smcfan-ce-max.plist
    launchctl bootstrap system /Library/LaunchDaemons/dev.wolffcatskyy.smcfan-ce-max.plist
    /usr/local/sbin/smcfan-ce-max --status
    echo 'Candidate rejected; attempted restoration of fixed 2141 RPM boot service.' >&2
}
finish() {
    local result=$?
    if [[ "$result" != 0 ]]; then rollback; fi
    exit "$result"
}
trap finish EXIT
bash "$src/install.sh"
# This is the transition the initial latch-preserving restart test missed.
/usr/local/bin/smcfanctl SET 0 auto
/usr/local/bin/smcfanctl SET 0 maximum
/usr/local/bin/smcfanctl STATUS
# Verify the REAL socket's kernel peer identity checks, not only a UID helper.
/usr/bin/sudo -u ms /usr/local/bin/smcfanctl SET 0 maximum
if /usr/bin/sudo -u nobody /usr/local/bin/smcfanctl SET 0 maximum; then
    echo 'FAIL: non-administrator unexpectedly changed policy' >&2
    exit 1
fi
printf '%s\n' 'PASS: administrator accepted and non-administrator rejected over the live socket.'
spinning=0
for _ in {1..15}; do
    state=$(/usr/local/sbin/smcfan-ce-max --status)
    current=$(printf '%s\n' "$state" | sed -E 's/.*current=([0-9]+).*/\1/')
    if [[ "$state" == *'target=2141 forced=1'* && "$current" -ge 2050 && "$current" -le 2250 ]]; then spinning=1;break;fi
    sleep 1
done
printf '%s\n' "$state"
[[ "$spinning" == 1 ]] || { echo 'Physical fan did not approach the verified target';exit 1; }
# Wait for the supervisor's first heartbeat before deliberately stalling its child.
ready=0
for _ in {1..20}; do
    status=$(/usr/local/bin/smcfanctl STATUS)
    if [[ "$status" == *'"error":0'* && "$status" != *'"watchdog_age":-1'* ]]; then ready=1;break;fi
    sleep 0.5
done
[[ "$ready" == 1 ]] || { echo 'Watchdog did not become ready';exit 1; }
# The independent watchdog must still recover the corrected production binary.
bash "$src/test-watchdog-mp6.sh"
healthy=0
for _ in {1..20}; do
    status=$(/usr/local/bin/smcfanctl STATUS)
    if [[ "$status" == *'"error":0'* && "$status" == *'"target":2141'* && "$status" != *'"watchdog_age":-1'* ]]; then healthy=1;break;fi
    sleep 0.5
done
[[ "$healthy" == 1 ]] || { echo 'Final controller/watchdog health check failed';exit 1; }
printf 'PASS: updated controller, auto-to-manual transition, real authorization and watchdog recovery.\n%s\n' "$status"
