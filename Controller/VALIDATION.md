# Candidate validation: 2026-10-20

This is a dated evidence record, not a live health report or universal compatibility list. Physical observations concern one MacPro6,1 running macOS 26.7.2 (25G330). The configured 10.13 deployment target has not been tested on 10.13.

## Evidence and outstanding gates

| Check | Observed result | Limit |
| --- | --- | --- |
| Native C/AppKit build | Passed using macOS Command Line Tools, x86_64 | Legacy Xcode app not rebuilt |
| Portable policy/decoder checks | Passed, including Linux ASan/UBSan | No hardware access |
| Fake-backend integration | 12 passed on Linux and macOS | Test authorization bypasses production |
| Production backend regression fixtures | Passed automatic/manual transitions, write failures, fallback and force-bit preservation | Fake SMC, native SDK |
| Production membership helper | Root/admin accepted; nobody rejected | Does not alone prove socket enforcement |
| Real administrator socket request | Passed after membership fix | Full non-admin socket test awaits final wrapper |
| First privileged pilot handoff | Passed; controller and watchdog launched, old fixed service retired | Manual ownership was already latched |
| Physical maximum and sensors | Actual roughly 2139–2142 RPM, target 2141, error 0, heartbeat resumed; independent reader agreed | One machine and point-in-time samples |
| Watchdog deliberate suspension | Passed on earlier candidate: controller PID replaced, RPM held near 2141 | Corrected binary repeat and separate crash test pending |
| Corrected automatic-to-maximum transition | Source fixed and native regression passed | Final privileged physical update/test pending |
| Menu app | Process launched | Visual controls and policy actions unverified |
| Boot configuration | Both system plists installed with RunAtLoad/KeepAlive | Cold boot before login unverified |
| Lock/user switching, sleep/wake | Pending | No reliability claim yet |
| Other Intel/T2 models, multiple fans, fanless devices | Pending | No universal support claim |

Shell syntax and ShellCheck passed. Missing-sensor/failure behavior is covered in software paths; physical manual/minimum/curve responses and failure injection remain outstanding. Comprehensive sensor coverage and commercial feature parity are not implemented.

## Failures found and corrections

The first stall test passed while manual mode was already latched. A later update released the fan to automatic mode during shutdown. The replacement wrote its target before enabling manual ownership; firmware replaced that target, verification failed and control fell back to firmware. The fan fell toward its original minimum. This exposed a transition the first test had not exercised.

Cooling was restored through a verified minimum floor, manual ownership at the then-current target, and maximum selection. Independent readings returned to about 2140–2141 RPM. The production backend now enables manual ownership before writing/verifying the target. Native fixtures simulate firmware immediately overwriting automatic targets and pass with the corrected order. Emergency fallback now tries a maximum minimum-floor boost before firmware release.

The initial administrator group enumeration also rejected the administrator account. Apple's membership API replaced it. The production helper passed root/admin/nobody checks, and the administrator subsequently issued real socket policy requests successfully.

The prepared `update-verified-mp6.sh` tests both fixes on the staged machine, repeats watchdog recovery and attempts fixed-service rollback on failure. Until its output is verified, the corrected transition remains software-tested rather than physically validated. See [recovery](RECOVERY.md).

## Measurements and interpretation

The pilot retains an explicit root `MAX 0 2141` exception because raw `F0Mx` reported roughly 1900–1980 despite measured operation near 2141. Effective status maximum therefore represents policy, not corrected hardware metadata.

Sensor samples were CPU roughly 43–45 C and GPU roughly 49–54 C. These are not a stress test. An early idle snapshot showed controller RSS 8712 KiB, watchdog 1564 KiB and GUI 41084 KiB, with rounded CPU 0.0%. RSS includes shared pages and the sample is not a controlled benchmark. An early app bundle measured about 110 KB; later builds may differ. No smallest/fastest, power-use or commercial comparison is established.
