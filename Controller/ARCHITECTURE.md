# Architecture and ownership

The system LaunchDaemon `dev.wolffcatskyy.smcfan-ce` runs `smcfan-ce-daemon`. It owns the SMC connection and serializes policy writes, CLI requests and control ticks. The AppKit interface and `smcfanctl` use `/var/run/smcfan-ce.sock`; they do not independently write SMC. Multiple user sessions therefore share one system policy.

The controller ticks every two seconds. The GUI requests one snapshot every four seconds. Requests/replies and client wait times are bounded. An exclusive lock at `/var/run/smcfan-ce.lock` prevents another cooperating controller/rescue process from becoming a simultaneous writer. Other fan programs do not honor that lock and must be retired separately.

## Hardware backend

`backend_macos.c` uses the inherited `smc-command` implementation, one connection and cached metadata. The policy layer supports up to 16 fans. Original minimums are saved separately from requested floors. Unchanged values are skipped; writes require readback. Manual ownership is enabled before the target is written, because firmware can immediately replace a target written while automatic mode is active. Per-fan mode keys are used when available; the global force mask fallback preserves unrelated bits.

On a write/control failure, recovery attempts maximum, then a maximum minimum-floor boost, then firmware release. These are attempts, not an assurance that inaccessible hardware is controlled. Curves use one temperature key, bounded interpolation, immediate increases and a downward limit of 100 RPM/second. Missing/invalid readings demand maximum and unhealthy status.

## Persistence and authorization

`controller.conf` lives under `/Library/Application Support/smcFanControlCE`. The installer makes that directory root:wheel 0700; the policy file is root-private and atomically replaced. `BASE` records original minimums, `MAX` records an explicit effective ceiling where supported, and `SET` records policy. Administrators normally use the CLI/menu rather than editing this implementation format. A missing saved policy starts unmanaged.

Kernel peer credentials identify socket clients. Root or administrator membership authorizes policy changes; root alone may send WATCHDOG. Production membership uses Apple's membership API. Reads expose status/sensor information to local users. The root processes are not sandboxed; see [security policy](../SECURITY.md).

## Supervision

`dev.wolffcatskyy.smcfan-ce-watchdog` runs an independent C watchdog. Every five seconds it checks controller progress and error state. Two failed/stalled checks trigger a bounded `launchctl kickstart -k`; continued failure can invoke rescue, which must obtain the same writer lock before attempting maximum cooling. Failure is logged through system logging. The watchdog's authenticated heartbeat is visible in status so a missing supervisor is detectable.

Launchd RunAtLoad/KeepAlive configures boot startup and process restart. Configuration is not evidence of cold-boot, sleep/wake or mechanical-failure recovery. Watchdog restart was physically observed on an earlier candidate; the corrected binary still needs its repeat test.

## Files and lifecycle

Installed binaries: `/Library/Application Support/smcFanControlCE/{smcfan-ce-daemon,smcfanctl,smcfan-ce-watchdog}`. A public executable CLI copy is installed at `/usr/local/bin/smcfanctl`. Plists live in `/Library/LaunchDaemons/` under the two labels above.

The menu app may exit without stopping cooling. Planned maintenance stops watchdog before controller. Controller shutdown releases managed fans; an update can therefore involve a firmware-controlled interval. Installation preserves saved policy but is not a transaction with automatic rollback on every failure. The special pilot wrapper adds an explicit fixed-service rollback attempt. Neither the legacy preferences nor either historical boot-helper plist is automatically imported.
