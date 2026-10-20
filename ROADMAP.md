# Roadmap

Updated 2026-10-20. These are development priorities, without a promised release date or version number. Cooling CE is a working name for the experimental successor in `Controller/`; the existing application remains separate.

## Reliability before release

1. Run the corrected binary's physical automatic-to-maximum transition, administrator/non-administrator socket checks and repeat watchdog suspension test using the prepared pilot recovery wrapper.
2. Verify a cold boot before any login, GUI quit/relaunch, screen locking, fast user switching, and sleep/wake. Confirm policy retention and measured fan response throughout.
3. Exercise manual, minimum and curve policies on hardware, including missing sensors and failed writes. Extend beyond one MacPro6,1 to multiple-fan and T2 Intel models before claiming support.
4. Audit privileged IPC, file ownership, installation, upgrade and rollback failure paths. Build with the oldest claimed SDK/runtime combination and test it on that runtime. A 10.13 deployment flag alone is insufficient.

Current evidence and known failures belong in [VALIDATION.md](Controller/VALIDATION.md), not in a blanket compatibility claim.

## A small useful application

Keep C for the controller/CLI/watchdog and Objective-C/AppKit for the interface unless measurement justifies a change. Measure installed bytes, idle wakeups, CPU, memory and command latency on a stated build and machine. Rust is an option for future evaluation, not an implemented rewrite or a guaranteed optimization.

Expand sensor discovery and model-aware names, then consider multi-sensor rules, notifications and diagnostics export. Keep charts, history and other optional features from becoming dependencies of cooling control. The watchdog currently installs by default; a supported opt-out needs explicit product behavior and health reporting.

## Distribution and maintenance

Choose a final app identity, review inherited licensing, provide reproducible build instructions, and decide signing/notarization and packaging before publishing a candidate release. Preserve deliberate migration and rollback from old helpers. Maintain a hardware/OS matrix with measured results, not inferred support.

Review legacy Xcode/helper integration and historical localized help separately. Optional sleep and update utilities require their own evidence and ownership; they are not prerequisites for fan control. Linux integration is maintained in the separate linux-mac repository and must be tested independently of the macOS launchd implementation.
