#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run with sudo on mp6'; exit 1; }
[[ $(sysctl -n hw.model) == MacPro6,1 ]] || exit 1
label=system/dev.wolffcatskyy.smcfan-ce
status=$(/usr/local/bin/smcfanctl STATUS)
[[ "$status" == *'"mode":"maximum"'* && "$status" == *'"target":2141'* && "$status" == *'"error":0'* && "$status" != *'"watchdog_age":-1'* ]] || { echo 'Maximum-profile/health precondition failed'; exit 1; }
launchctl print system/dev.wolffcatskyy.smcfan-ce-watchdog >/dev/null
before_pid=$(launchctl print "$label" | awk '$1 == "pid" { print $3; exit }')
[[ "$before_pid" =~ ^[0-9]+$ ]] || exit 1
recover() {
    local result=$?
    if [[ "$result" != 0 ]]; then
        launchctl kill SIGCONT "$label" 2>/dev/null || true
        launchctl kickstart -k "$label" 2>/dev/null || true
        echo 'Watchdog test did not pass; attempted to resume/restart the controller.' >&2
    fi
    exit "$result"
}
trap recover EXIT
printf 'Suspending controller PID %s; its latched 2141 RPM target is left unchanged.\n' "$before_pid"
launchctl kill SIGSTOP "$label"
passed=0
for _ in {1..40}; do
    sleep 0.5
    after_pid=$(launchctl print "$label" | awk '$1 == "pid" { print $3; exit }')
    if [[ "$after_pid" =~ ^[0-9]+$ && "$after_pid" != "$before_pid" ]]; then
        if status=$(/usr/local/bin/smcfanctl STATUS); then
            if [[ "$status" == *'"target":2141'* && "$status" == *'"error":0'* ]]; then passed=1;break;fi
        fi
    fi
done
[[ "$passed" == 1 ]] || { echo 'No verified watchdog recovery within 20 seconds' >&2; exit 1; }
printf 'PASS: watchdog replaced PID %s with %s\n%s\n' "$before_pid" "$after_pid" "$status"
/usr/local/sbin/smcfan-ce-max --status
