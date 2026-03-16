# smcFanControl Boot Fan Daemon - Installation Guide

A lightweight daemon that sets fan minimum RPMs at boot time, before login.
Designed for Macs running smcFanControl Community Edition where you want
fan settings applied immediately at boot rather than waiting for the app to launch.

## Requirements

- macOS 10.13+ (Intel Mac with SMC fan control)
- Admin (sudo) access

## Files

| File | Purpose |
|------|---------|
| `smcfancontrol-daemon` | The daemon binary (ad-hoc signed) |
| `com.smcfancontrol.boot-fan.plist` | LaunchDaemon configuration |
| `fan-boot-profile.plist` | Example fan configuration |

## Gatekeeper: Allowing Downloaded Binaries

macOS will block this daemon binary because it's unsigned. You must allow it before copying to `/usr/local/bin/`.

**Option 1: Remove quarantine attribute (recommended)**

```bash
xattr -cr smcfancontrol-daemon
```

This removes the quarantine flag set by macOS when downloading from the internet.

**Option 2: Allow via System Settings**

1. Open System Settings → Privacy & Security
2. Scroll to "smcfancontrol-daemon" and click "Allow Anyway"

After using either method, the binary will run without prompts.

## Installation

### 1. Copy the binary

```bash
sudo cp smcfancontrol-daemon /usr/local/bin/
sudo chmod 755 /usr/local/bin/smcfancontrol-daemon
```

### 2. Create your fan config

```bash
sudo mkdir -p "/Library/Application Support/smcFanControl"
sudo cp fan-boot-profile.plist "/Library/Application Support/smcFanControl/"
```

Edit the config to match your fans. To find your fan IDs and current speeds:

```bash
# Using the smc command-line tool from smcFanControl:
smc -f
```

The config format is a standard plist with a `fans` array:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>fans</key>
    <array>
        <dict>
            <key>id</key>
            <integer>0</integer>
            <key>min_rpm</key>
            <integer>1800</integer>
        </dict>
        <dict>
            <key>id</key>
            <integer>1</integer>
            <key>min_rpm</key>
            <integer>1200</integer>
        </dict>
    </array>
</dict>
</plist>
```

### 3. Install the LaunchDaemon

```bash
sudo cp com.smcfancontrol.boot-fan.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.smcfancontrol.boot-fan.plist
sudo chmod 644 /Library/LaunchDaemons/com.smcfancontrol.boot-fan.plist
```

### 4. Load the daemon (or reboot)

```bash
sudo launchctl load /Library/LaunchDaemons/com.smcfancontrol.boot-fan.plist
```

The daemon runs once at boot (RunAtLoad + LaunchOnlyOnce), sets the fan
minimums, then exits. It does not stay resident.

## Testing

You can test the daemon manually before installing:

```bash
# Test with a custom config path (runs as root):
sudo /usr/local/bin/smcfancontrol-daemon /path/to/test-config.plist

# Check the log after boot:
cat /var/log/smcfancontrol-daemon.log
```

## Uninstallation

```bash
sudo launchctl unload /Library/LaunchDaemons/com.smcfancontrol.boot-fan.plist
sudo rm /Library/LaunchDaemons/com.smcfancontrol.boot-fan.plist
sudo rm /usr/local/bin/smcfancontrol-daemon
sudo rm -rf "/Library/Application Support/smcFanControl"
```

## How It Works

1. macOS launches the daemon at boot via launchd (before login)
2. The daemon reads fan settings from the plist config
3. For each fan, it writes the F{n}Mn SMC key using fpe2 encoding
4. Logs actions to `/var/log/smcfancontrol-daemon.log`
5. Exits immediately after setting all fans

## Troubleshooting

**"error: no AppleSMC device found"** - Your Mac may not have an accessible SMC
(virtual machines, very old hardware).

**"error: cannot write key F0Mn (0xe00002c1)"** - The daemon is not running as
root. LaunchDaemons in `/Library/LaunchDaemons/` run as root by default.

**"error: cannot open config file"** - Check that the config exists at
`/Library/Application Support/smcFanControl/fan-boot-profile.plist`.
