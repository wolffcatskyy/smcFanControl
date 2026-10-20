# smcFanControl Community Edition

Free, GPL-licensed fan-control software for Intel Macs, based on [Hendrik Holtmann's smcFanControl](https://github.com/hholtmann/smcFanControl).

This repository contains the legacy macOS application and **Cooling CE**, an experimental native successor. Cooling CE is being reviewed in [draft PR #38](https://github.com/wolffcatskyy/smcFanControl/pull/38); it is not a released replacement. Neither implementation has verified support for every Intel Mac. Apple Silicon is outside this project's scope.

## Choose the right component

| Component | Purpose | Status |
| --- | --- | --- |
| Legacy app (`Classes/`, Xcode project) | Menu-bar minimum fan speeds and existing preferences | Existing release lineage; this work does not rebuild or validate its release artifacts |
| [Cooling CE](Controller/README.md) | C boot controller, Objective-C menu app, CLI and independent watchdog | Experimental; physical pilot on one MacPro6,1 |
| [OCLP boot helper](FanControlHelper/INTEGRATION.md) | Apply saved minimums once at boot | Separate legacy integration; no continuous supervision |
| [Older boot helper](smclegacy-daemon/INSTALL.md) | Another historical one-shot minimum writer | Retained for reference/migration |
| [Raw SMC CLI](smc-command/README.md) | Developer reads and low-level access | Not the Cooling CE policy CLI |
| [Update Guardian](UpdateGuardian/README.md) | Optional update-preference changes | Separate from fan control; no compatibility guarantee |

Use one fan controller at a time. A one-shot helper can still conflict when it runs at boot. Cooling CE does not use the legacy app's per-user preferences or boot-helper plist.

## Existing releases

Get published legacy artifacts from [GitHub Releases](https://github.com/wolffcatskyy/smcFanControl/releases). Read the selected release's requirements and contents; a source branch or draft PR is not a release. Review unsigned downloads before granting administrator access. macOS security prompts depend on the artifact, quarantine state and system policy; no installation method here guarantees their absence.

The project's Homebrew tap has historically provided `wolffcatskyy/tap/smcfancontrol`. Its current cask and artifact must be checked independently before installation; it does not install this candidate merely because the candidate source is present here.

## Cooling CE development

Start with the [candidate build and operation guide](Controller/README.md), [architecture](Controller/ARCHITECTURE.md), [testing instructions](Controller/TESTING.md), [recovery guide](Controller/RECOVERY.md), and [dated validation record](Controller/VALIDATION.md).

The candidate centralizes hardware writes in one system service, so user login, locking, switching and GUI exit do not intentionally start another controller or replace system policy. Boot launch is configured; a cold boot before login and fast user switching still require physical verification. The corrected automatic-to-maximum transition also awaits the final privileged pilot test.

Implementation is C plus Objective-C/AppKit using system frameworks. No Rust, Python or browser runtime is required to run it. Smaller footprint is a design goal, not a demonstrated claim of being fastest or smallest. Comprehensive sensors, alerts, history, multi-sensor rules and commercial feature parity remain future work. See the [roadmap](ROADMAP.md).

## Legacy features and documentation

The legacy source includes power-management handling, minimum-speed controls, locale/UI changes and optional sleep/update helpers. Their presence in source does not establish that every packaged release includes them or that they resolve a particular machine's problem. Sleep-related system changes are not a general cure for EFI panics. OCLP detection is heuristic and does not prove fan or update compatibility.

The localized `Ressources/*/F.A.Q.rtf` files are historical smcFanControl 2.6 help. Their app-only uninstall instructions do **not** remove separately installed system helpers or Cooling CE; use the relevant component's guide.

## Contributing and security

Report ordinary bugs through [issues](https://github.com/wolffcatskyy/smcFanControl/issues), with model, macOS version, component/build, policy, measured RPM and reproduction steps. Distinguish expected behavior from observed results. See [SECURITY.md](SECURITY.md) for vulnerability reporting and privilege boundaries.

GPL v2 lineage and attribution are retained; see [LICENSE](LICENSE) and source-file notices. Original project by Hendrik Holtmann; community fork by [wolffcatskyy](https://github.com/wolffcatskyy). The candidate uses inherited open-source SMC code and independently implemented policies; it contains no imported commercial binary code or sensor tables.
