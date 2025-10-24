# 1Password Touch ID Monitor

Background service that plays audio alerts when 1Password's Touch ID authentication prompt appears, helping you notice prompts on other screens.

## Quick Start

```bash
# Test the alert sound
./scripts/1password-touchid-monitor.sh test

# Start monitoring
./scripts/1password-touchid-monitor.sh start

# Check status
./scripts/1password-touchid-monitor.sh status

# Stop monitoring
./scripts/1password-touchid-monitor.sh stop
```

## Auto-Start on Login

To have the monitor automatically start when you log in:

```bash
./scripts/1password-touchid-monitor.sh install
```

To remove auto-start:

```bash
./scripts/1password-touchid-monitor.sh uninstall
```

## Configuration

Edit [`configs/audio-alerts.yml`](../configs/audio-alerts.yml) to customize:

```yaml
onepassword:
  enabled: true  # Enable/disable audio alerts
  touchid_alert_sound: Glass  # Change alert sound
```

### Available System Sounds

- **Glass** (default) - Clear, attention-getting chime
- **Tink** - Soft metallic sound
- **Pop** - Quick pop sound
- **Purr** - Gentle alert
- **Hero** - Triumphant fanfare
- **Ping** - Simple ping
- **Blow** - Whoosh sound
- **Bottle** - Cork pop sound

## How It Works

The monitor runs in the background and checks every 0.5 seconds for 1Password's Touch ID authentication window. When it detects the prompt:

1. Plays the configured system sound
2. Logs the event to `~/.1password-touchid-monitor.log`
3. Only plays once per prompt (no repeated sounds)

## Use Cases

- **Multi-monitor setups** - Notice prompts on other screens
- **Full-screen applications** - Get alerts when prompts appear behind apps
- **Focus work** - Audio cue draws attention without checking screens
- **Accessibility** - Auditory notification for visual prompts

## Troubleshooting

### Monitor won't start

Check configuration:
```bash
cat configs/audio-alerts.yml | grep -A 2 "onepassword:"
```

Ensure `enabled: true` is set.

### No sound plays

Test sound manually:
```bash
./scripts/1password-touchid-monitor.sh test
```

Try different sounds in config (Glass, Tink, Pop, etc.).

### Sound plays but prompt not detected

Check logs:
```bash
tail -20 ~/.1password-touchid-monitor.log
```

The monitor looks for 1Password windows with "Touch ID" or "Unlock" in their description.

### Want to temporarily disable

```bash
./scripts/1password-touchid-monitor.sh stop
```

Or set `enabled: false` in config and restart.

## Files

- **Script**: [`scripts/1password-touchid-monitor.sh`](../scripts/1password-touchid-monitor.sh)
- **Config**: [`configs/audio-alerts.yml`](../configs/audio-alerts.yml)
- **PID file**: `~/.1password-touchid-monitor.pid`
- **Log file**: `~/.1password-touchid-monitor.log`
- **LaunchAgent**: `~/Library/LaunchAgents/com.igris.1password-touchid-monitor.plist`

## Integration with Igris

This monitor is part of the Igris audio alert system, which also provides:

- **YubiKey tap alerts** - Audio for git operation authorization
- **Bypass detection** - Warning when security is bypassed
- **Modular audio** - Prefix + action sound composition

All audio features can be configured in [`configs/audio-alerts.yml`](../configs/audio-alerts.yml).
