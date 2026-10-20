# Cooling CE: experimental Intel Mac controller

Cooling CE combines a C system controller, C CLI and independent C watchdog with an Objective-C/AppKit menu app. It is an experimental successor in the smcFanControl repository, not a finished replacement. One physical MacPro6,1 has been piloted; other models, T2 Macs and older macOS versions remain unverified. Fanless devices are not a validated target.

## Build and inspect

On macOS with Command Line Tools and an SDK capable of building x86_64:

```sh
cd Controller
make
./build/probe
```

`probe` reads hardware without setting fan policies. The build targets x86_64 and macOS 10.13 with `-Os` and dead-code stripping; 10.13 runtime compatibility is untested. System IOKit/CoreFoundation/Cocoa frameworks are required. Python is used for development tests only; neither Python nor Rust is a runtime dependency. Builds are local development artifacts, not notarized releases.

Output includes `build/Cooling CE.app`, `smcfan-ce-daemon`, `smcfanctl`, `smcfan-ce-watchdog` and `probe`. Do not treat successful compilation as a hardware compatibility check.

## Install and operate

Review [validation](VALIDATION.md) and prepare [recovery](RECOVERY.md) first. Quit other fan applications and deliberately retire their boot helpers. The installer rejects several known competing service labels/processes; this is not exhaustive conflict detection.

```sh
sudo /bin/bash install.sh
open 'build/Cooling CE.app'
/usr/local/bin/smcfanctl STATUS
```

Installation immediately starts system LaunchDaemons and configures them for boot. It does not wait for login. A first installation without saved policy starts unmanaged; an upgrade retains the existing root policy. Installing alone does not select maximum mode. An administrator may explicitly select it:

```sh
/usr/local/bin/smcfanctl SET 0 maximum
```

Fan 0 is only an example. Check detected fans and limits first. Root and administrator accounts may change policies; other users may read diagnostics. GUI startup does not apply per-user preferences. Quitting or locking the GUI session leaves the system controller running. Cold-boot and fast-user-switch behavior still need physical verification.

Both controller and watchdog install by default. The GUI is optional. There is no supported installer switch for opting out of watchdog supervision; a missing heartbeat is shown as unhealthy.

## Policies and CLI

```sh
smcfanctl STATUS
smcfanctl SENSORS
smcfanctl SET 0 auto
smcfanctl SET 0 maximum
smcfanctl SET 0 minimum 1500
smcfanctl SET 0 manual 2000
smcfanctl SET 0 curve TC0P 50 80
```

The RPM and temperatures above illustrate syntax, not recommended settings for a model.

| Policy | Behavior |
| --- | --- |
| `auto` | Restore the captured original minimum and release the fan's manual bit |
| `minimum RPM` | Raise the minimum floor while allowing firmware control above it |
| `manual RPM` | Hold a bounded fixed target |
| `maximum` | Hold the effective validated ceiling |
| `curve KEY LOW HIGH` | Interpolate between minimum/maximum from one available temperature key |

Curves increase immediately and reduce demand by at most 100 RPM/second. Invalid/missing sensor input requests maximum and marks status unhealthy. Comprehensive sensor enumeration/naming, multiple-sensor rules, history, SMART sensors and notifications are not implemented. `SENSORS` checks a limited list of known keys; missing entries do not establish that hardware has no sensor.

`STATUS` includes sequence, error, watchdog age and per-fan policy/RPM/limits. A negative watchdog age means no heartbeat has arrived; it can occur briefly at startup. Persistent missing/stale heartbeat, nonzero error or a stalled sequence needs investigation. Confirm measured RPM independently; a target alone is insufficient.

## MacPro6,1 pilot exception

On the pilot machine, measured RPM was about 2141 while raw `F0Mx` reported roughly 1900–1980. Root configuration explicitly retains `MAX 0 2141`, restricted in code to MacPro6,1. This is a software policy exception validated on one machine, not a discovered or repaired firmware maximum and not a recommendation for every MacPro6,1. `probe --mp6-profile` checks that profile without applying it.

The initial `test-mp6.sh` is a migration from the earlier fixed service, not a repeatable general installer. The prepared `update-verified-mp6.sh` handles the existing pilot's corrected update and fixed-speed rollback prerequisites. Read [recovery](RECOVERY.md) before using either. The final corrected transition test remains pending in the dated record.

See [architecture](ARCHITECTURE.md), [tests](TESTING.md), [recovery](RECOVERY.md) and [observed results](VALIDATION.md). GPL lineage and inherited SMC attribution remain in the repository and application bundle.
