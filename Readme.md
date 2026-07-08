# smcFanControl Community Edition

**Homepage:** [wolffcatskyy.dev/smcfancontrol](https://wolffcatskyy.dev/smcfancontrol)

Community-maintained fork of [smcFanControl](https://github.com/hholtmann/smcFanControl) for Intel Macs. Set a minimum fan speed to keep your Mac running cooler.

---

## 🔥 NEW: Boot-Time Fan Control for OCLP Macs

Fans screaming at 100% on your OpenCore-patched Mac? Not anymore. smcFanControl now applies your fan settings **at boot, before you even log in** — the first fan control app to support this.

- Auto-detects OCLP (OpenCore Legacy Patcher) installations
- Applies saved fan speeds via Launch Daemon before login screen
- Zero overhead — runs once at boot, then exits

Works on all OCLP-patched Macs running supported macOS versions.

👉 [How it works →](#oclp-boot-fan-control)

---

## Install

```bash
brew tap wolffcatskyy/tap
brew install --cask wolffcatskyy/tap/smcfancontrol
```

That's it. No Gatekeeper warnings, no right-click tricks.

### Why Homebrew?

macOS Gatekeeper blocks apps downloaded from the internet that aren't signed with an Apple Developer certificate ($99/year). When you try to open an unsigned app, macOS refuses with *"app can't be opened because Apple cannot check it for malicious software"* — and there's no "Open Anyway" button on first attempt.

Homebrew bypasses this entirely by stripping the quarantine flag during install, giving you a clean one-command experience with no security dialogs or workarounds.

### Manual install (no Homebrew)

Download the `.zip` from [GitHub Releases](https://github.com/wolffcatskyy/smcFanControl/releases), extract it, and move `smcFanControl.app` to `/Applications`.

If macOS blocks the app from opening:

1. Right-click (or Control-click) smcFanControl.app and select **Open**
2. Click **Open** in the dialog that appears
3. Alternatively, go to **System Settings > Privacy & Security** and click **Open Anyway**

Homebrew installs bypass Gatekeeper automatically.

## Bug Fixes

### Power management fan clamping fix

The original smcFanControl had a bug in `FanControl.m` where the power management handler would clamp fan speeds incorrectly on AC/battery transitions. When switching between power sources, the fan speed logic could override user-set minimums or fail to apply the correct speed, causing fans to not respond properly to manual adjustments.

This fork fixes the clamping behavior so fan speeds are applied reliably regardless of power state changes.

## Features

- **Simple fan slider** — Set-and-forget minimum RPM per fan, no profiles needed
- **Sleep/Wake Fix** — One-click fix for "Sleep Wake Failure in EFI" panics on older Intel Macs (reversible)
- **Boot-time fan daemon** — Optional LaunchDaemon applies fan settings before login, before you even log in
- **Icon-only menu bar** — Minimal CPU usage; no temperature/RPM clutter unless you want it
- **Auto-detect temperature unit** — Celsius or Fahrenheit from system locale, no manual setting
- **OCLP Update Guardian** — Blocks incompatible macOS updates on OCLP-patched Macs
- **Lightweight** — ~94% smaller than original (Sparkle framework removed)

## OCLP Boot Fan Control

If you're running [OpenCore Legacy Patcher](https://dortania.github.io/OpenCore-Legacy-Patcher/) (OCLP) on an unsupported Mac, fans typically run at 100% from boot until smcFanControl starts — which only happens after you log in.

The **OCLP Boot Fan Daemon** fixes this by applying your saved fan settings at boot, before login. On first launch, smcFanControl auto-detects OCLP and offers to install the daemon.

**How it works:**
- A small LaunchDaemon (`smcfancontrold`) runs once at boot
- It reads your saved fan settings from `/Library/Application Support/smcFanControl/fan-settings.plist`
- It applies fan minimum RPMs via SMC, then exits
- Settings are synced automatically whenever you adjust fan speeds in the app

**Manual install (advanced):**
```bash
cd FanControlHelper
make
sudo make install
# Edit fan settings:
sudo cp fan-settings-example.plist "/Library/Application Support/smcFanControl/fan-settings.plist"
```

**Manual uninstall:**
```bash
cd FanControlHelper
sudo make uninstall
```

See [`FanControlHelper/INTEGRATION.md`](FanControlHelper/INTEGRATION.md) for full technical details.

## OCLP Update Guardian

Automatically blocks macOS updates that aren't yet supported by OpenCore Legacy Patcher.

When enabled, the guardian checks OCLP's latest release to see which macOS versions are supported. If Apple offers an update that OCLP hasn't confirmed compatible, notifications are suppressed and automatic downloads are blocked. When OCLP releases support for that version, updates flow through normally.

A daily LaunchDaemon re-checks automatically, since macOS tends to reset update preferences and OCLP releases new versions.

**Emergency abort:** If an update accidentally starts downloading, use `--abort` to kill the download and purge staged files.

```bash
sudo updateguardian --enable     # Turn on
sudo updateguardian --disable    # Turn off
sudo updateguardian --status     # Show current state
sudo updateguardian --check      # Check OCLP compatibility now
sudo updateguardian --abort      # Kill staged download (emergency)
```

See [`UpdateGuardian/`](UpdateGuardian/) for implementation details.

## smc CLI

A standalone `smc` binary for reading SMC sensors and fan speeds from the terminal is included in releases. When installing via Homebrew, it is included automatically.

## What Changed from Upstream

- **Fixed power management clamping bug** — Fan speeds now apply reliably across AC/battery transitions
- Stripped Apple Silicon code (Intel-only fork)
- Fixed 16 deprecated macOS APIs
- Removed Sparkle auto-updater framework (5.3 MB)
- Removed dead code and unused classes
- Merged community PRs (#143, #146, #108)
- **Sleep/Wake Fix** — One-click fix for sleep panics
- **Simple slider control** — No profiles, just set minimum RPM per fan
- **Boot daemon** — LaunchDaemon for pre-login fan control
- **Auto-detect locale** — Temperature unit (°C/°F) from system locale
- **Modern UI** — SF Symbol fan icon, system fonts, dark mode support
- **Icon-only menu bar** — Minimal CPU usage, optional temperature/RPM display
- **Fixed auth error** — Works on modern macOS without deprecated APIs
- **OCLP Update Guardian** — Simple on/off toggle blocks incompatible updates automatically
- **Ko-fi donation link** — Support the maintainer

## License

GPL v2 (inherited from upstream).

## Credits

Original by [Hendrik Holtmann](https://github.com/hholtmann). Community fork by [wolffcatskyy](https://github.com/wolffcatskyy).
