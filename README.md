# Igris

In 2025 and onward, **every** push/pull/pr should require physical hardware verification. Inspired by the September 2025 [Shai-Hulud npm breach](https://www.cisa.gov/news-events/alerts/2025/09/23/widespread-supply-chain-compromise-impacting-npm-ecosystem) where malware stole credentials and auto-published malicious code to 500+ packages.

## Overview

**The Problem:** Stolen credentials let attackers push code silently. Even with SSH keys, tokens, and 2FA, compromised systems can modify your repos without you knowing.

**The Solution:** Physical hardware verification. Require YubiKey tap or Touch ID for every git network operation. If a malicious actor can physically access your hardware, you have much more pressing matters to attend to.

### What Igris Provides

- **Hardware Verification Enforcement** - YubiKey tap OR Touch ID via 1Password CLI
- **Defense-in-Depth Architecture** with multiple enforcement layers preventing bypass
- **Flexible Authentication** - Use YubiKey (most secure) or Touch ID (convenient alternative)
- **Cryptographic Verification** via HMAC-SHA1 challenge-response with touch requirement
- **Auto-Revert Setup** ensuring no incomplete or misconfigured installations
- **Comprehensive Audit Logging** for all verification attempts and failures
- **Graceful Fallback** with security warnings when optimal verification unavailable

**Operations Requiring Hardware Verification:**
- `git push`, `git pull`, `git fetch`, `git clone`
- `git remote add/update/set-url`, `git submodule update --remote`
- `gh pr create/merge`, `gh release create`, `gh repo clone`, `gh workflow run`

**Pass-Through Operations (No Tap):**
- `git commit`, `git status`, `git log`, `git diff`
- All read-only and local operations

<details>
<summary><strong>🏗️ Architecture</strong></summary>

## System Architecture

Igris implements a defense-in-depth security model with three enforcement layers:

### Enforcement Layers

```
🔒 Igris Security Enforcement
│
├── Layer 1: Shell Wrappers
│   ├── git-yubikey-wrapper.sh      → Intercepts git commands
│   └── gh-yubikey-wrapper.sh       → Intercepts GitHub CLI commands
│
├── Layer 2: Git Hooks
│   └── pre-push hook               → Catches direct binary invocations
│
└── Layer 3: YubiKey Verification
    └── yubikey-verify.sh           → Cryptographic challenge-response
```

### Security Flow

**Shell Wrapper Layer (Primary):**
1. User executes `git push origin main`
2. Shell function intercepts command
3. Detects network operation
4. Triggers YubiKey verification
5. Only proceeds if verification succeeds

**Git Hook Layer (Secondary):**
1. Even if wrappers bypassed (direct binary call)
2. Pre-push hook executes before network operation
3. Requires YubiKey verification again
4. Aborts push if verification fails

**YubiKey Verification Core:**
1. Detects YubiKey presence via `ykman`
2. Generates random 32-byte challenge
3. Sends challenge to YubiKey OTP slot 2
4. Requires physical tap (hardware enforced)
5. Validates HMAC-SHA1 response
6. Logs attempt (success/failure/timeout)

### Verification Methods (Priority Order)

1. **YubiKey OTP with Required Touch** (MOST SECURE)
   - Cryptographic HMAC-SHA1 challenge-response
   - Touch flag enforced on YubiKey slot 2
   - Random 32-byte challenge per operation
   - Hardware-verified physical presence
   - Preferred method for maximum security

2. **Touch ID via 1Password CLI** (SECURE)
   - Biometric authentication using macOS Secure Enclave
   - Requires 1Password CLI with biometric unlock enabled
   - Hardware-backed (Touch ID sensor)
   - Excellent alternative when YubiKey unavailable
   - macOS only

3. **YubiKey OTP without Guaranteed Touch** (LESS SECURE)
   - Fallback if slot not configured with --touch
   - Still cryptographic but no guaranteed tap
   - Warns user to reconfigure for security

4. **YubiKey FIDO2 Presence Check** (INSECURE)
   - Only verifies YubiKey is plugged in
   - No tap requirement
   - Loudly warns this provides minimal security

5. **Simple Presence** (INSECURE FALLBACK)
   - Last resort verification
   - Critical warnings displayed
   - Only checks device connectivity

### Shell Integration

The system integrates with your shell configuration (~/.zshrc or ~/.bashrc):

```bash
# Wrapper functions
git() {
    "/path/to/git-yubikey-wrapper.sh" "$@"
}

gh() {
    "/path/to/gh-yubikey-wrapper.sh" "$@"
}

# Environment variables
export TOMB_DIR="/path/to/igris"
export TOMB_YUBIKEY_ENABLED=true
```

Wrappers intercept commands transparently while preserving all git/gh functionality and completions.

### Data Persistence

**Verification Logs:**
- Location: `~/.tomb-yubikey-verifications.log`
- Format: ISO 8601 timestamp, status, operation, method, serial number
- Monitors for repeated failures (alerts after 5 failures)

**Backups:**
- Location: `~/.tomb-yubikey-backup/`
- Contains timestamped shell config backups
- Removal creates comprehensive backup in `removal-TIMESTAMP/`

</details>

<details>
<summary><strong>🚀 Quick Start</strong></summary>

## Quick Start

### Prerequisites

**Hardware Verification (Choose One or Both):**

**Option 1: YubiKey (Most Secure)**
- YubiKey 4/5 series with OTP support
- `ykman` (YubiKey Manager CLI)

```bash
# macOS
brew install ykman

# Linux (Ubuntu/Debian)
sudo apt install yubikey-manager

# Linux (Fedora/RHEL)
sudo dnf install yubikey-manager

# Verify installation
ykman list
# Should show: YubiKey 5C Nano (Serial: 12345678)
```

**Option 2: Touch ID (Convenient Alternative - macOS only)**
- macOS device with Touch ID sensor
- 1Password CLI (`op`)

```bash
# macOS
brew install 1password-cli

# Sign in to 1Password
op signin

# Verify biometric unlock is enabled
op account list  # Should trigger Touch ID prompt
```

**General Requirements:**
- `git` (2.0+)
- Bash or Zsh shell

**Platform Support:**
- ✅ macOS (YubiKey + Touch ID)
- ✅ Linux (YubiKey only)
- ❌ Windows (not yet supported)

### Installation

**1. Clone Repository:**
```bash
git clone https://github.com/freddieweir/igris.git
cd igris
```

**2. Configure Hardware Verification:**

*If using YubiKey:*
```bash
./scripts/yubikey-configure-otp.sh configure
```
This sets up HMAC-SHA1 challenge-response with required touch on slot 2.

*If using Touch ID:*
```bash
# Ensure 1Password CLI is signed in
op signin

# Verify biometric unlock works
op account list  # Should trigger Touch ID
```

**3. Install Enforcement System:**
```bash
./scripts/yubikey-git-setup.sh setup
```

Interactive setup process:
- Detects available hardware (YubiKey and/or Touch ID)
- Installs shell wrappers for git/gh commands
- Configures global git hooks via template directory
- Backs up existing shell configuration
- **Requires hardware verification to complete** (proves physical access)
- Auto-reverts if verification fails

**4. Reload Shell Configuration:**
```bash
# Zsh
source ~/.zshrc

# Bash (macOS)
source ~/.bash_profile

# Bash (Linux)
source ~/.bashrc

# Or restart your terminal
```

### First Use

**Test Verification:**
```bash
./scripts/yubikey-git-setup.sh test
```

**Verify Status:**
```bash
./scripts/yubikey-git-setup.sh status
```

Expected output:
```
Enforcement: ✅ ENABLED
YubiKey:     ✅ Connected (YubiKey 5C Nano)
Touch ID:    ✅ Available (via 1Password CLI)
Wrappers:    ✅ Installed (git, gh)
Hooks:       ✅ Configured (global template)
```

**Try a Git Operation:**
```bash
git push origin main
```

**With YubiKey:**
```
🔑 Hardware verification required for: git push origin main
✅ YubiKey detected: Serial 12345678
ℹ️  Verifying with OTP challenge-response (requires physical tap)...
ℹ️  👆 TAP YOUR YUBIKEY NOW to verify (timeout: 10s)
[Tap your YubiKey]
✅ YubiKey tap verified! (2s)
✅ Verification successful! Proceeding with git push
[push proceeds normally]
```

**With Touch ID (no YubiKey connected):**
```
🔑 Hardware verification required for: git push origin main
ℹ️  Verifying with Touch ID via 1Password CLI...
ℹ️  👆 TOUCH ID REQUIRED to verify operation
[Touch the Touch ID sensor]
✅ Touch ID verified! (1s)
✅ Verification successful! Proceeding with git push
[push proceeds normally]
```

### Optional: Multi-Repository Installation

To install hooks in all workspace repositories:

```bash
./scripts/yubikey-git-setup.sh setup --all-repos
```

This installs pre-push hooks in repositories listed in `configs/yubikey-enforcement.yml`:
- `/Users/fweir/git/internal/repos/carian-observatory`
- `/Users/fweir/git/internal/repos/fifth-symphony`
- `/Users/fweir/git/internal/repos/EchoLink-Reborn`

</details>

<details>
<summary><strong>🛠️ Operations</strong></summary>

## Daily Operations

### Common Commands

| Task | Command | Description |
|------|---------|-------------|
| **Check Status** | `./scripts/yubikey-git-setup.sh status` | Show enforcement state and hardware availability |
| **Test Verification** | `./scripts/yubikey-git-setup.sh test` | Test hardware verification (YubiKey or Touch ID) |
| **Disable Enforcement** | `./scripts/yubikey-git-setup.sh disable` | Temporarily disable |
| **Enable Enforcement** | `./scripts/yubikey-git-setup.sh enable` | Re-enable after disable |
| **Remove System** | `./scripts/yubikey-git-setup.sh remove` | Complete uninstall |

### YubiKey OTP Management

| Task | Command | Description |
|------|---------|-------------|
| **Check Slot Status** | `./scripts/yubikey-configure-otp.sh status` | Show OTP configuration |
| **Configure Slot 2** | `./scripts/yubikey-configure-otp.sh configure` | Setup challenge-response |
| **Delete Slot 2** | `./scripts/yubikey-configure-otp.sh delete` | Remove OTP configuration |

### Management Workflow

**Temporarily Disable (Emergency):**
```bash
# Keep configuration, just disable checks
./scripts/yubikey-git-setup.sh disable

# Work without tap requirement
git push  # No tap required

# Re-enable when ready
./scripts/yubikey-git-setup.sh enable
```

**Environment Variable Override:**
```bash
# One-time bypass (use with caution)
export TOMB_YUBIKEY_ENABLED=false
git push  # Will work without tap (with warnings)
unset TOMB_YUBIKEY_ENABLED
```

**Complete Removal:**
```bash
./scripts/yubikey-git-setup.sh remove
```

Creates timestamped backup in `~/.tomb-yubikey-backup/removal-TIMESTAMP/` containing:
- Shell configuration before removal
- Pre-push hooks from all repositories
- Configuration files

### Troubleshooting

**"No YubiKey detected":**
```bash
# Check if YubiKey is recognized
ykman list

# Try replugging YubiKey
# Check USB connection
# Try different USB port
```

**"OTP Slot 2 is empty":**
```bash
# Configure OTP slot 2 with touch requirement
./scripts/yubikey-configure-otp.sh configure

# Verify configuration
./scripts/yubikey-configure-otp.sh status
```

**"Timeout waiting for tap":**
- YubiKey has 10-second timeout
- Watch for blinking LED indicating tap needed
- Ensure good finger contact with touch sensor
- Try tapping more firmly

**"1Password CLI not signed in":**
```bash
# Sign in to 1Password
op signin

# Verify biometric unlock is enabled
op account list  # Should trigger Touch ID

# Check 1Password app settings for biometric unlock
```

**"Touch ID verification failed":**
- Ensure Touch ID is enabled in System Settings
- Check 1Password CLI biometric unlock is enabled in 1Password app
- Try: `op signin` to refresh authentication
- Verify Touch ID sensor is working: System Settings → Touch ID & Password

**"Timeout waiting for Touch ID":**
- Touch ID has 10-second timeout
- Ensure finger is clean and dry
- Try different finger if enrolled with multiple
- Check System Settings for Touch ID configuration

**"Verification failed in pre-push hook":**
- Shell wrapper may have been bypassed
- Hook provides secondary enforcement
- Check status: `./scripts/yubikey-git-setup.sh status`
- Verify wrappers installed: `grep "YubiKey" ~/.zshrc`

**Wrapper Not Working After Setup:**
```bash
# Reload shell configuration
source ~/.zshrc  # or ~/.bashrc

# Or restart terminal
exit
# Open new terminal

# Verify installation
./scripts/yubikey-git-setup.sh status
```

**Multiple YubiKey Serials:**

Edit `configs/yubikey-enforcement.yml`:
```yaml
devices:
  allowed_serials:
    - 12345678  # Primary YubiKey
    - 87654321  # Backup YubiKey
  require_specific_device: false  # Allow any from list
```

### Verification Logs

**View Recent Verifications:**
```bash
tail -20 ~/.tomb-yubikey-verifications.log
```

**Check for Failures:**
```bash
grep "FAILURE\|TIMEOUT" ~/.tomb-yubikey-verifications.log
```

**Log Format:**
```
2025-10-01T14:23:45+0000 [SUCCESS] git push - OTP-TOUCH - Serial: 12345678
2025-10-01T14:25:12+0000 [TIMEOUT] git push - OTP-TOUCH - Serial: 12345678
2025-10-01T14:26:03+0000 [FAILURE] git fetch - no_device - Serial: n/a
```

</details>

<details>
<summary><strong>🔧 Development</strong></summary>

## Development & Customization

### Adding New Git Operations

**Edit Wrapper:** `scripts/git-yubikey-wrapper.sh`

```bash
# Add to NETWORK_OPERATIONS array
NETWORK_OPERATIONS=(
    "push"
    "pull"
    "fetch"
    "clone"
    "your-new-operation"  # Add here
)
```

**Update Configuration:** `configs/yubikey-enforcement.yml`

```yaml
operations:
  git:
    your_new_operation: required  # Add policy
```

### Adding GitHub CLI Operations

**Edit Wrapper:** `scripts/gh-yubikey-wrapper.sh`

Follow same pattern as git wrapper for `gh` commands.

### Customizing Verification Methods

**Edit Verification Script:** `scripts/yubikey-verify.sh`

The script tries verification methods in priority order:
1. `verify_otp_touch()` - Most secure
2. `verify_otp()` - Fallback
3. `verify_fido2_presence_only()` - Insecure
4. `verify_presence()` - Last resort

To enforce only OTP with touch, remove fallback methods from `main()` function.

### Testing Changes

**Test Verification:**
```bash
./scripts/yubikey-verify.sh "test-operation"
```

**Test Wrapper:**
```bash
./scripts/git-yubikey-wrapper.sh push origin main
```

**Dry Run Setup:**
```bash
# Setup with non-interactive mode
./scripts/yubikey-git-setup.sh setup --non-interactive

# Review changes before applying
grep "YubiKey" ~/.zshrc
```

### Integration with Other Tools

**Pre-commit Hooks:**
Igris uses pre-push hooks. To integrate with pre-commit framework:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: yubikey-verify
        name: YubiKey Verification
        entry: /path/to/yubikey-verify.sh
        language: system
        stages: [push]
```

**CI/CD Integration:**
Disable enforcement for CI/CD runners:

```bash
# In CI/CD environment
export TOMB_YUBIKEY_ENABLED=false
```

Or use exemptions in configuration:

```yaml
exemptions:
  repos:
    - /path/to/ci-automation-repo
```

### Contributing

**Areas for Improvement:**
- [ ] FIDO2 proper implementation (not just presence check)
- [ ] Windows support (PowerShell wrappers)
- [ ] GUI installer for non-technical users
- [ ] Multi-YubiKey rotation support
- [ ] Time-based caching (tap once, valid for N minutes)
- [ ] Homebrew formula for easy installation
- [ ] Automated integration tests
- [ ] Keybase/GPG integration

**Submitting Changes:**
1. Fork the repository
2. Create feature branch: `git checkout -b feature/description`
3. Test thoroughly with your own YubiKey
4. Ensure no security regressions
5. Submit PR with clear description

</details>

---

## Project Structure

```
igris/
├── scripts/
│   ├── yubikey-verify.sh            # Core verification logic
│   ├── git-yubikey-wrapper.sh       # Git command wrapper
│   ├── gh-yubikey-wrapper.sh        # GitHub CLI wrapper
│   ├── yubikey-git-setup.sh         # Management CLI
│   └── yubikey-configure-otp.sh     # YubiKey OTP configuration
├── hooks/
│   └── git-hooks/
│       └── pre-push                  # Pre-push hook template
├── configs/
│   └── yubikey-enforcement.yml       # Configuration file
└── README.md                         # This file
```

## Design Principles

### What This Project Prioritizes

**Security by Default:**
- Physical tap required for all network operations
- Cryptographic challenge-response verification
- Defense-in-depth with multiple enforcement layers
- Auto-revert on setup failure (prevents incomplete installations)
- Comprehensive audit logging
- Default-deny with explicit operation allowlist

**Operational Excellence:**
- Interactive setup with clear prompts
- Automatic shell configuration reload
- Visual feedback (emojis, colors, clear messages)
- Graceful error handling with recovery instructions
- Complete management CLI (setup/enable/disable/remove/status)
- Non-interactive mode for automation

**Maintainability:**
- Modular script architecture
- Self-documenting configuration (YAML with comments)
- Standardized logging format
- Timestamped backups for all destructive operations

This system demonstrates security-conscious git operation enforcement with practical implementations of hardware-based authentication.

---

## Links

- **GitHub Repository**: https://github.com/freddieweir/igris
- **YubiKey Manager**: https://github.com/Yubico/yubikey-manager
- **YubiKey Hardware**: https://www.yubico.com/products/

## License

MIT License - See LICENSE file

## Acknowledgments

- Yubico for YubiKey hardware and `ykman` CLI
- Git hooks and wrapper pattern inspiration from various security tools
- Defense-in-depth architecture principles

