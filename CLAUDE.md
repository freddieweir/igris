# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

**Igris** (Iron Guardian Integration System) is a hardware-enforced git security system requiring physical YubiKey tap for all git/gh network operations. The system implements defense-in-depth with multiple enforcement layers to prevent compromised systems or malicious code from performing git operations without explicit hardware authorization.

## Core Architecture

### Defense-in-Depth Layers

1. **Shell Wrapper Layer** (`scripts/git-yubikey-wrapper.sh`, `scripts/gh-yubikey-wrapper.sh`)
   - Shell function wrappers intercept git/gh commands before execution
   - Detects network operations and triggers verification
   - Primary enforcement point for normal command usage

2. **Git Hook Layer** (`hooks/git-hooks/pre-push`)
   - Secondary enforcement via git's pre-push hook
   - Catches direct binary invocations that bypass wrappers
   - Last line of defense before network operations

3. **YubiKey Verification Core** (`scripts/yubikey-verify.sh`)
   - Implements cryptographic challenge-response using HMAC-SHA1
   - Requires physical tap through OTP slot 2 (configured with --touch)
   - Falls back through multiple verification methods with security warnings

### Verification Priority Order

The system attempts verification methods in order of security:
1. **OTP with required touch** (SECURE) - Cryptographic challenge-response requiring physical tap
2. **OTP without guaranteed touch** (LESS SECURE) - Warns to reconfigure with --touch
3. **FIDO2 presence** (INSECURE) - Only checks if plugged in, loudly warns
4. **Simple presence** (INSECURE FALLBACK) - Last resort with critical warnings

## Common Commands

### Installation and Setup

```bash
# Configure YubiKey OTP slot 2 with touch requirement
./scripts/yubikey-configure-otp.sh configure

# Install enforcement system (interactive setup)
./scripts/yubikey-git-setup.sh setup

# Install with all workspace repos
./scripts/yubikey-git-setup.sh setup --all-repos

# Non-interactive setup
./scripts/yubikey-git-setup.sh setup --non-interactive
```

### Management

```bash
# Check system status
./scripts/yubikey-git-setup.sh status

# Temporarily disable enforcement (keeps configuration)
./scripts/yubikey-git-setup.sh disable

# Re-enable enforcement
./scripts/yubikey-git-setup.sh enable

# Test YubiKey verification
./scripts/yubikey-git-setup.sh test

# Complete removal (creates timestamped backups)
./scripts/yubikey-git-setup.sh remove
```

### YubiKey OTP Management

```bash
# Check OTP slot status
./scripts/yubikey-configure-otp.sh status

# Reconfigure OTP slot 2
./scripts/yubikey-configure-otp.sh configure

# Delete OTP slot 2
./scripts/yubikey-configure-otp.sh delete
```

### Emergency Bypass

```bash
# Temporary environment variable bypass (use with caution)
export TOMB_YUBIKEY_ENABLED=false
git push  # Will work without tap (with warnings)
unset TOMB_YUBIKEY_ENABLED
```

## Key Implementation Details

### Setup Script Auto-Revert

The setup process (`yubikey-git-setup.sh setup`) includes a critical safety feature:
- After installing wrappers and hooks, it requires a YubiKey tap to verify physical access
- If verification fails, **all changes are automatically reverted**
- Prevents incomplete or misconfigured installations that could provide false security

### Shell Configuration Integration

The system adds function wrappers to your shell config (~/.zshrc or ~/.bashrc):
- `git()` function wraps `/usr/bin/git`
- `gh()` function wraps the GitHub CLI
- `TOMB_DIR` environment variable points to repository location
- `TOMB_YUBIKEY_ENABLED` controls enforcement (true/false)

### Network Operations Detection

The wrappers identify network operations requiring verification:
- Direct: `push`, `pull`, `fetch`, `clone`
- Complex: `remote add/update/set-url`, `submodule update --remote`
- GitHub CLI: `pr create/merge`, `release create`, `repo clone`, `workflow run`

Read-only operations (`status`, `log`, `diff`, `commit`) pass through without verification.

### Verification Logging

All verification attempts are logged to `~/.tomb-yubikey-verifications.log`:
- Timestamp (ISO 8601 format)
- Status (SUCCESS, FAILURE, TIMEOUT, BYPASSED)
- Method used (OTP-TOUCH, OTP, FIDO2-PRESENCE-ONLY, PRESENCE)
- YubiKey serial number
- Operation context

The system monitors for repeated failures and triggers macOS notifications after 5 failures.

## Configuration

Primary configuration file: `configs/yubikey-enforcement.yml`

Key settings:
- `enforcement.enabled`: Master switch (true/false)
- `enforcement.require_tap`: Require physical tap vs presence
- `enforcement.timeout_seconds`: How long to wait for tap (default: 10)
- `operations.git.*`: Per-operation settings (required/optional/disabled)
- `security.max_failed_attempts`: Alert threshold
- `integration.workspace_repos`: List of repositories to auto-install hooks

## Workspace Integration

This repository is designed to work across multiple repositories in the workspace:
- `integration.workspace_repos` lists target repositories
- `setup --all-repos` installs hooks in all listed repositories
- Global git template directory (`~/.git-templates`) ensures new repos get hooks
- Each repo maintains independent hook in `.git/hooks/pre-push`

## Security Considerations

### What This Protects Against
- Compromised development machines running malicious scripts
- Supply chain attacks attempting automated git operations
- Unauthorized code pushes from your account
- Social engineering (requires physical hardware access)

### What This Does NOT Protect Against
- Physical theft of YubiKey (use PIN/biometric locks)
- Attacks after successful tap (tap authorizes specific operation)
- Vulnerabilities in YubiKey firmware
- Read-only git operations (these don't need protection)

### OPSEC Note
The configuration file contains specific YubiKey serial numbers and workspace paths. While this repository is internal, be cautious about:
- Not committing `~/.tomb-yubikey-verifications.log` (contains operation history)
- Keeping backups secure (`~/.tomb-yubikey-backup/`)
- Serial numbers in `configs/yubikey-enforcement.yml` are not sensitive but do identify hardware

## Troubleshooting

### "No YubiKey detected"
- Verify YubiKey is plugged in: `ykman list`
- Check USB connection and try replugging
- Ensure `ykman` is installed: `brew install ykman`

### "OTP Slot 2 is empty"
- Configure slot 2: `./scripts/yubikey-configure-otp.sh configure`
- This sets up challenge-response with touch requirement

### "Timeout waiting for tap"
- YubiKey has 10-second timeout
- Watch for blinking LED indicating tap needed
- Ensure good finger contact with sensor

### Wrapper Not Working After Setup
- Reload shell: `source ~/.zshrc` (or `~/.bashrc`)
- Restart terminal
- Verify wrappers installed: `grep "YubiKey Git Enforcement" ~/.zshrc`

### Hook Verification Failed
- Shell wrapper may have been bypassed
- Hook provides secondary enforcement
- Check status: `./scripts/yubikey-git-setup.sh status`

## References to Legacy System

Several scripts reference `tomb-of-nazarick` in comments and paths:
- Legacy naming from original development project
- Functionality is identical - "Igris" is the public project name
- `TOMB_DIR` environment variable points to this repository
- Default paths in hooks use absolute path: `/Users/fweir/git/internal/repos/tomb-of-nazarick`

When working in this codebase, treat "tomb-of-nazarick" references as referring to the Igris system.
