# Cooling CE — native Intel Mac candidate

A small Objective-C/AppKit menu app, a C system controller, a native CLI, and an independent C watchdog. This is an experimental successor interface in the smcFanControl repository, not a finished replacement or a claim of support for every Intel Mac. It uses public/open-source SMC code and independently implemented policies; no commercial code or sensor tables are included.

## Architecture

The root controller starts from `/Library/LaunchDaemons/dev.wolffcatskyy.smcfan-ce.plist` at boot. It is the only normal SMC writer. The optional interface never opens AppleSMC or launches privileged command-line tools to apply fan changes. All user sessions connect to the same system Unix socket. Closing or locking a user's session does not remove cooling control. Administrator group membership or root identity is checked from the kernel's peer credentials for policy writes; ordinary users can read status and sensors.

The new interface is deliberately separate from the legacy app while it is tested. The legacy Xcode app is not silently converted to this protocol. Do not run its setuid writer alongside the new controller.

## Implemented policies

- System automatic: restore the captured original minimum and release the selected fan's manual bit.
- Minimum boost: raise the fan's floor and let firmware increase cooling further.
- Manual: hold a validated fixed target.
- Maximum: hold the validated ceiling.
- Curve: select an available SMC temperature key and lower/upper temperatures. Linear interpolation between minimum and maximum; immediate upward response and a maximum downward ramp of 100 RPM/second. Missing/invalid sensor readings demand maximum and mark status as unhealthy.

The native menu exposes all five modes per fan, a small known-key sensor list, and diagnostics. Comprehensive sensor enumeration/naming, multiple-sensor rules, AC/battery profiles, history charts, SMART sensors, alerts, and validated T2-specific handling are not implemented yet.

Metadata is cached in the inherited backend. Unchanged SMC values are not rewritten. The control loop runs every two seconds; the menu reads one snapshot every four seconds. Requests and replies are bounded; client timeouts are short. Policy changes are serialized and atomically saved in a root-private file. Original minima are recorded separately from the current requested floor so restarts do not turn a boosted minimum into the new baseline. Each force-bit change reads current hardware state and preserves other fans' bits.

## Watchdog

A separate system process checks the controller's progress every five seconds. Two failed/stalled checks trigger a bounded `launchctl kickstart -k`. If recovery is unsuccessful, a rescue invocation attempts maximum cooling only after acquiring the same exclusive hardware-writer lock. Failure to acquire the lock or apply cooling is logged as critical; a watchdog cannot fix a stuck kernel, a driver refusing all access, or a mechanical fan failure.

The watchdog sends a root-authenticated heartbeat. Status exposes its age, and the interface marks a missing/stale heartbeat as unhealthy. This avoids presenting a responsive GUI alone as proof that supervision is working. Both services are installed by default. Removing watchdog supervision is possible through launchd, but the UI deliberately continues to flag the missing heartbeat.

No hardware takeover, hang recovery, reboot, or user-switch behavior is claimed validated merely from compilation or fake-backend tests.

## Build

On an Intel-capable macOS SDK host with Command Line Tools:

```sh
cd Controller
make
```

Builds x86_64 for macOS 10.13+ with `-Os` and dead-code stripping. No Rust, Python, web UI, third-party GUI runtime, or bundled framework is needed at runtime. The app and helpers are local development artifacts, not Developer ID notarized releases. GPL source/attribution is retained.

`build/probe` reads hardware without writing fan settings. `build/probe --mp6-profile` checks the explicit 2141 RPM pilot ceiling; this is a software validation path, not a write or independent discovery of the physical maximum.

## mp6 pilot

The physical MacPro6,1 was observed holding 2140–2142 RPM under the earlier service while F0Mx reported roughly 1900–1923 RPM. The pilot explicitly retains 2141 as a root-configured `MAX 0 2141` exception, restricted to MacPro6,1. Other Macs do not get this exception. The status ceiling is therefore an effective policy limit, not always the raw firmware F0Mx. Do not generalize this measured profile to other machines.

The prepared `test-mp6.sh` checks model, existing target, and actual RPM; backs up the old service plist; validates the root profile before handoff; retires the old boot service; installs the new controller and watchdog; waits for the watchdog heartbeat; and prints independent physical RPM. A failed handoff attempts rollback to the original 2141 RPM service. Administrator authentication is required locally. This pilot must be reviewed before running; it is not a generic installation policy for all Macs.

For other installations, `sudo bash install.sh` refuses known active competing services. Migrate those deliberately first. Initial policy is unmanaged until an administrator selects a mode. GUI startup never applies a per-user profile over system policy.

## CLI

```sh
smcfanctl STATUS
smcfanctl SENSORS
smcfanctl SET 0 auto
smcfanctl SET 0 maximum
smcfanctl SET 0 minimum 1500
smcfanctl SET 0 manual 2000
smcfanctl SET 0 curve TC0P 50 80
```

Example temperatures/RPM are illustrative, not model-specific recommendations. Unsupported keys, invalid limits and non-admin write attempts must fail instead of guessing.

## Tests and limits

```sh
cc -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -O2 tests/test_policy.c policy.c decode.c -lm -o /tmp/ce-policy-test
/tmp/ce-policy-test
python3 -m unittest discover -s tests -v
```

The integration tests compile a fake backend and use isolated `/tmp` sockets/configuration. They cover policy persistence, concurrent readers, duplicate-process locks, force-bit preservation, invalid command refusal, baseline restoration, curve interpolation and slow clients. Test mode bypasses real peer authorization; production macOS administrator/non-admin verification remains a physical test gate. These tests do not write SMC, start launchd services, or prove hardware recovery.

Physical gates: first handoff and RPM verification, UI/manual/curve behavior, watchdog stall/crash recovery, administrator/non-administrator accounts, screen locking and fast user switching, sleep/wake, and a cold boot before login. Only mark a gate passed when directly observed.

## Uninstall / rollback

`sudo bash uninstall.sh` stops the watchdog first, stops the controller, acquires the writer lock for a verified firmware-release attempt, and removes launch plists and the CLI. Root-private policy and binaries remain for rollback. If release fails, the script aborts so failure is visible.

The mp6 pilot additionally saves the old fixed-speed plist under `pilot-backup-*` in `/Library/Application Support/smcFanControlCE`. Restore it only after stopping both new services. Never enable both controllers at boot.
