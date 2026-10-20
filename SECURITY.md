# Security policy

This repository includes code that can run as root and change cooling behavior. The experimental Cooling CE branch has not completed a security audit or its physical release gates. This file does not promise a support window, response deadline or audited release status for historical versions.

## Report privately

Use [GitHub private vulnerability reporting](https://github.com/wolffcatskyy/smcFanControl/security/advisories/new) if enabled. Otherwise use a private contact explicitly published on the [maintainer's profile](https://github.com/wolffcatskyy). Do not post an exploit or sensitive system output in a public issue while arranging private contact. Ordinary non-sensitive bugs may use public issues.

Include the affected commit/release, component, model/macOS version, reproduction, expected and observed behavior, and impact. Exclude passwords, private keys, serial numbers and unrelated personal logs. No response-time guarantee is made here.

## Privilege boundaries

The legacy application uses a privileged SMC command path. Historical helper installers and update/sleep utilities have different privileges and lifecycle rules; do not infer their security from the new controller.

Cooling CE runs a root system controller and root watchdog. These processes have normal root privileges: the protocol restricts requests but is **not an operating-system sandbox**. The menu app reads status and requests policy changes through a Unix socket. Production code uses kernel peer identity and Apple's membership API to authorize root or administrator policy writes. Ordinary users can read status/sensors; WATCHDOG is root-only. Fake-backend tests bypass production authorization and cannot prove this boundary.

The installed policy directory is `/Library/Application Support/smcFanControlCE` (root:wheel, mode 0700), with a root-private policy file. Installed executables and launch plists must remain root-owned and protected against unprivileged replacement. The socket is `/var/run/smcfan-ce.sock`; the exclusive controller lock is `/var/run/smcfan-ce.lock`. Protocol bounds, atomic policy saves and a single normal writer reduce specific failure paths but are not proof of security.

## Cooling failures

The controller verifies writes and attempts maximum cooling on failures, with a maximum minimum-floor fallback before firmware release. The independent watchdog checks progress and attempts restart/rescue. Failed access, an unresponsive kernel or a mechanical fault can defeat these attempts. A configured target, running GUI or installed plist does not prove physical fan speed.

For diagnosis and rollback use [the recovery guide](Controller/RECOVERY.md). Do not start another writer alongside a stalled service. Quitting the GUI does not stop cooling; removing only the GUI does not uninstall the services. Review source and provenance before installing unsigned development builds. No commercial code or proprietary sensor database is included in this candidate.
