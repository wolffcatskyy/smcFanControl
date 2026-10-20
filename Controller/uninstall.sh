#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
[[ $(id -u) == 0 ]] || exit 1
for label in dev.wolffcatskyy.smcfan-ce-watchdog dev.wolffcatskyy.smcfan-ce; do
    if launchctl print "system/$label" >/dev/null 2>&1; then launchctl bootout "system/$label"; fi
done
# Verify firmware release only after acquiring the controller's exclusive lock.
'/Library/Application Support/smcFanControlCE/smcfan-ce-daemon' --release
for label in dev.wolffcatskyy.smcfan-ce-watchdog dev.wolffcatskyy.smcfan-ce; do
    rm -f "/Library/LaunchDaemons/$label.plist"
done
rm -f /usr/local/bin/smcfanctl
printf '%s\n' 'Services removed. Root-owned policy/binaries retained for rollback. Inspect fan state before enabling another controller.'
