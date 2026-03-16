# smcFanControl Community Edition

**Homepage:** [wolffcatskyy.dev/smcfancontrol](https://wolffcatskyy.dev/smcfancontrol)

Community-maintained fork of [smcFanControl](https://github.com/hholtmann/smcFanControl) for Intel Macs. Set a minimum fan speed to keep your Mac running cooler.

## Install

```bash
brew tap wolffcatskyy/smcfancontrol
brew install --cask smcfancontrol
```

That's it. No Gatekeeper warnings, no right-click tricks.

### Why Homebrew only?

macOS blocks apps downloaded from the internet that aren't signed with an Apple Developer certificate ($99/year). Homebrew strips the quarantine flag automatically during install, giving you a clean one-command experience without any security dialogs.

### Manual install (no Homebrew)

Download the `.zip` from [GitHub Releases](https://github.com/wolffcatskyy/smcFanControl/releases), extract it, then remove the quarantine flag before first launch:

```bash
xattr -cr /Applications/smcFanControl.app
```

This is required because the app is unsigned. Homebrew handles this for you automatically.

## Features

- **Simple fan slider** — Set-and-forget minimum RPM per fan, no profiles needed
- **Sleep/Wake Fix** — One-click fix for "Sleep Wake Failure in EFI" panics on older Intel Macs (reversible)
- **Boot-time fan daemon** — Optional LaunchDaemon applies fan settings before login, before you even log in
- **Icon-only menu bar** — Minimal CPU usage; no temperature/RPM clutter unless you want it
- **Auto-detect temperature unit** — Celsius or Fahrenheit from system locale, no manual setting
- **Lightweight** — ~94% smaller than original (Sparkle framework removed)

## smc CLI

A standalone `smc` binary for reading SMC sensors and fan speeds from the terminal is included in releases. When installing via Homebrew, it is included automatically.

## What Changed from Upstream

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
- **Ko-fi donation link** — Support the maintainer

## License

GPL v2 (inherited from upstream).

## Credits

Original by [Hendrik Holtmann](https://github.com/hholtmann). Community fork by [wolffcatskyy](https://github.com/wolffcatskyy).
