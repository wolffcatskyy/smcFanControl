# Historical one-shot boot helper

`smclegacy-daemon.c` is a separate legacy minimum-speed writer, not the new resident [Cooling CE controller](../Controller/README.md). Retained files describe migration/reference use; no new hardware validation or signed release is established by this guide.

## Build and inspect

From this directory on a macOS SDK host:

```sh
clang -Os smclegacy-daemon.c -framework IOKit -framework CoreFoundation -o smcfancontrol-daemon
plutil -lint com.smcfancontrol.boot-fan.plist fan-boot-profile.plist
```

Compilation and plist syntax do not validate RPM choices. Inspect `fan-boot-profile.plist` for the actual machine. Its `fans` array contains `id` and `min_rpm` entries. Example values must not be applied blindly. The executable's optional first argument is a configuration path; invoking it is not a dry run and can write SMC.

## Historical installed layout

| Item | Path |
| --- | --- |
| Executable | `/usr/local/bin/smcfancontrol-daemon` |
| Configuration | `/Library/Application Support/smcFanControl/fan-boot-profile.plist` |
| Launch plist | `/Library/LaunchDaemons/com.smcfancontrol.boot-fan.plist` |
| stderr log | `/var/log/smcfancontrol-daemon.log` |

The plist uses RunAtLoad and LaunchOnlyOnce. The program reads configuration, writes each fan's minimum and exits. It does not continuously hold maximum or supervise failures. Installation requires root-owned, protected binaries/configuration and an explicit policy/rollback plan. Do not load this job with Cooling CE, the other legacy boot helper, or a third-party writer active.

## Retiring an existing installation

First inspect the service and establish how firmware control or the replacement controller will be verified. An administrator can remove the launch job with:

```sh
sudo launchctl bootout system/com.smcfancontrol.boot-fan
```

An already-exited or unloaded one-shot job may be absent. After verifying that state, archive/remove its specific launch plist and executable. Preserve configuration for rollback. Removing the job or executable does not undo minimums already written and does not uninstall other helpers. Verify actual RPM after handoff.

An SMC error can reflect permissions, unsupported hardware, driver access or a rejected operation; an error code alone does not identify the cause. Quarantine removal is not recommended as a blanket installation step and does not establish trust, compatibility or guaranteed execution.
