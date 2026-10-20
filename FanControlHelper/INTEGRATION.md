# Legacy OCLP boot helper

This is a separate, one-shot legacy minimum-speed writer. New controller development is in [Cooling CE](../Controller/README.md). Do not enable this helper alongside Cooling CE or another fan controller. A process that exits after boot can still overwrite another controller's settings at startup.

## Behavior and limitations

The launch label is `com.smcfancontrol.bootdaemon`. The executable reads `/Library/Application Support/smcFanControl/fan-settings.plist`, applies configured fan minimums, logs to `/var/log/smcfancontrold.log` and exits. It does not supervise cooling continuously or restart a stalled GUI.

OCLP detection uses filesystem/NVRAM/boot-argument indicators. These are heuristics: OpenCore presence does not establish OCLP, and absence of an indicator does not disprove it. No support claim for every OCLP-patched Mac or cure for maximum-speed fans follows from this detection.

## Build and inspect

```sh
cd FanControlHelper
make
./smcfancontrold -h
sudo ./smcfancontrold -n
```

`-n` is a dry run: detect/read configuration without SMC writes. Options include `-c PATH` for configuration, `-f` to bypass detection, and `-q` for stderr-only logging. Combining `-f` with a configuration **without `-n` writes hardware**. The supplied settings are examples, not validated recommendations.

The source targets a macOS SDK with IOKit/CoreFoundation. A deployment setting is not evidence that the executable runs on every older OS. Review model-specific limits, root ownership, plist contents and rollback before live use.

## Historical application integration

`Classes/OCLPHelper.{h,m}` contains installation and settings-sync logic; `FanControl.m` imports the helper. Source presence does not establish correct Xcode target membership or packaged resources. This candidate work has not rebuilt/verified the legacy app's integration.

To integrate a reviewed legacy build, add the Objective-C helper to the app target, build `smcfancontrold` with `OCLPDetect.c` and IOKit/CoreFoundation, and copy the resulting binary and launch plist into the application resources expected by `OCLPHelper`. Verify installation and settings synchronization end to end. Do not describe this as automatic integration until that packaged build is tested.

## Maintenance

The standalone Makefile provides `sudo make install` and `sudo make uninstall`. Installation copies root-owned files and attempts `launchctl load`; its recipe suppresses launchctl failures, so a successful make exit is not proof that the job loaded or applied settings. It does not populate a complete model-specific settings file for you. Inspect the installed plist and logs and verify actual RPM.

Uninstall leaves the settings plist in place. Stopping/removing a one-shot job does not itself undo fan minimums already written. Plan explicit firmware restoration or a deliberate controller handoff. Never remove shared application-support directories indiscriminately.
