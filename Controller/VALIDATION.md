# Candidate validation — 2026-10-20

## Directly observed on physical mp6

- Hardware: MacPro6,1, macOS 26.7.2 (25G330).
- Native x86_64 AppKit/C build using Command Line Tools succeeds. Deployment target 10.13 is configured; execution on 10.13 itself is untested.
- New SMC backend read-only probe succeeds. The existing profile held approximately 2141 RPM while raw F0Mx reported roughly 1900–1936 RPM.
- User ran the privileged pilot installer. The explicit MacPro6,1 ceiling exception retains 2141; this is an effective software policy ceiling, not a corrected firmware maximum.
- New controller and independent watchdog are running as system LaunchDaemons with RunAtLoad and KeepAlive. The old fixed-speed service is absent from the system domain and its launch plist was archived by the pilot.
- Root CLI status: `mode=maximum`, `target=2141`, measured roughly 2139–2142 RPM, `error=0`, watchdog heartbeat age about 1–2 seconds. Independent older read-only CLI agrees on actual RPM and forced mode.
- Native interface process starts successfully from the staged .app. Visual controls and changes through its menus still require user testing.
- Sensor endpoint directly reads CPU TC0P around 43 C, GPU TG0D around 49 C, GPU TG1D around 52 C, plus GPU proximity/memory/ambient readings. These are point-in-time samples, not a thermal stress test.
- A single idle process snapshot reported controller RSS 8712 KiB, watchdog 1564 KiB, GUI 41084 KiB, with rounded CPU 0.0% for each. RSS includes shared pages; this is not a controlled comparison, power measurement, or proof of being smallest/fastest.

## Software checks

- 12 isolated fake-backend integration tests pass on Linux and on the Mac, including restart persistence, multi-client reads, bitmask preservation, bounded slow clients, duplicate-process lock refusal, command bounds and private-config checks.
- Portable policy/decoder assertions pass with AddressSanitizer and UndefinedBehaviorSanitizer on Linux.
- Native build and shell syntax/ShellCheck pass. Production peer-credential authorization has been compiled on macOS; distinct administrator/non-administrator accounts have not yet been exercised.

## Remaining physical gates

- Independent watchdog restart after deliberate controller suspension or crash. A root-only bounded `test-watchdog-mp6.sh` is staged for this purpose, with a resume/restart attempt on failure.
- Cold boot before login, sleep/wake, fast user switching, and interface quit/relaunch.
- Physical manual, minimum and curve responses; low-temperature and missing-sensor transitions; failed-write behavior.
- T2 Intel Macs, other Intel models, older supported macOS versions, and fanless devices.
- Comprehensive sensor coverage and commercial feature parity remain future work.

## Incident separation

The separate Linux host rebooted at 11:20 AM after its previous journal ended abruptly around 11:18. No cause was established from the checked logs. The new Linux fan integration was not installed there, and the native macOS candidate had only been compiled at that point. mp6 retained uptime of approximately 16 hours. This does not establish a cause or prove an unrelated event.

## Physical regression discovered during update

The first watchdog stall test passed: controller PID 19720 was replaced with 20157 and the fan stayed near 2141 RPM; the watchdog heartbeat subsequently resumed. The macOS unified log records the watchdog restart. This test began with manual mode already latched and therefore did not test the automatic-to-manual transition.

A subsequent binary update released fans to automatic mode on shutdown. The replacement failed target verification and fell back to firmware control. The initial target-before-force write order was incorrect for this transition. Cooling was restored remotely through a verified minimum floor, establishing manual mode at the then-current target, and reselecting maximum. Independent readings returned to 2140–2141 RPM. Sampled CPU/GPU temperatures at the time were about 45 C and 52–54 C; these readings do not erase the failed transition.

The production backend now enables manual ownership before writing/verifying its target. A native regression test links that actual backend to SMC fixtures that immediately overwrite automatic-mode targets. It covers auto-to-maximum, auto-to-manual, minimum-to-maximum, target-write failures, restoration and unrelated force bits. It passes. Emergency fallback now tries a maximum minimum-floor boost before relinquishing firmware control.

The initial administrator group enumeration also incorrectly rejected the administrator test account. It has been replaced with Apple's membership API. The production membership helper accepts root and the administrator UID and rejects nobody. After the membership update, the administrator successfully made real socket policy requests; a full non-admin socket check is included in the prepared update script.

`update-verified-mp6.sh` is staged for a final authenticated update. It checks the actual automatic-to-maximum transition, administrator and non-administrator socket requests, physical RPM, and repeat watchdog recovery, with a fixed-speed rollback attempt on failure. Until that script passes, the corrected transition remains software-regression-tested rather than physically validated.
