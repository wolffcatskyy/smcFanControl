# Maintenance and recovery

Before changing a working installation, record measured RPM, saved policy, service labels and a usable rollback. Keep local administrator access available. Never start a second SMC writer to compete with a stalled controller.

## Inspect without changing policy

```sh
/usr/local/bin/smcfanctl STATUS
/usr/local/bin/smcfanctl SENSORS
sudo launchctl print system/dev.wolffcatskyy.smcfan-ce
sudo launchctl print system/dev.wolffcatskyy.smcfan-ce-watchdog
```

Compare sequence and heartbeat across several samples and verify actual RPM. Initial watchdog age `-1` can clear after its first check; persistent missing/stale heartbeat or nonzero error needs investigation. The watchdog uses system logging. A responding interface or a plausible target does not prove airflow or temperature safety.

An administrator can request a valid maximum policy with `smcfanctl SET 0 maximum`, checking the fan ID first. Confirm the reply and actual RPM. Do not clear errors by repeatedly issuing unrelated raw SMC writes.

## Update or uninstall

The installer stops watchdog before controller, replaces binaries and starts controller then watchdog. It preserves saved policy, but shutdown releases fans to firmware; a failed update needs an explicit recovery plan. Known competing service checks are not exhaustive.

```sh
sudo /bin/bash install.sh
# Or, from a reviewed matching source/package:
sudo /bin/bash uninstall.sh
```

Uninstall stops both services, obtains the writer lock for a verified firmware-release attempt, then removes launch plists and the public CLI. A release failure aborts visibly. Policy and private binaries remain for recovery. Uninstall does not restore a previous third-party controller. Removing only the .app leaves the system services installed. Do not delete the configuration directory as a troubleshooting shortcut.

## Existing MacPro6,1 pilot

The original pilot archived the fixed-speed plist under `pilot-backup-*` in `/Library/Application Support/smcFanControlCE`. `test-mp6.sh` expects the original fixed service; do not rerun it against an already migrated installation.

For the staged pilot, the prepared command is:

```sh
sudo /bin/bash /Users/Shared/Cooling-CE-pilot/Controller/update-verified-mp6.sh
```

This is specific to that staged machine. Read the script first: it requires the original fixed-speed backup plist and the separately built `recovery-max` helper. It installs the corrected controller, tests automatic-to-maximum, administrator/non-administrator access, physical RPM and watchdog recovery. On failure it attempts to stop/remove the candidate units, restore the fixed helper and boot plist, and hold 2141 RPM. A rollback attempt itself can fail; verify its result and measured fan speed.

`make recovery` builds the explicit pilot rollback helper; it is not part of the ordinary app bundle. The 2141 RPM profile must not be generalized to other machines. Restore an older controller only after both new services have stopped. If physical fan speed cannot be established, stop the thermal workload and use local recovery rather than assuming watchdog supervision is sufficient.
