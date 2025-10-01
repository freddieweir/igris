# Igris - YubiKey Git Enforcement System

**Hardware-enforced git operation security with defense-in-depth architecture.**

Igris requires **physical YubiKey tap** for all git/gh network operations, ensuring no malicious code or compromised system can perform git operations without explicit hardware authorization.

## 🎯 What is Igris?

Igris (Iron Guardian Integration System) is a comprehensive security system that:

- **Enforces** physical YubiKey presence for git push, pull, fetch, clone, and PR operations
- **Protects** against compromised systems and malicious code
- **Verifies** physical presence through cryptographic challenge-response
- **Maintains** defense-in-depth with multiple enforcement layers

## 🔒 Security Architecture

### Multi-Layer Enforcement

1. **Shell Wrappers** - Intercept `git`/`gh` commands globally
2. **Git Hooks** - Secondary enforcement at pre-push level
3. **YubiKey Verification** - OTP challenge-response with physical touch requirement

### Core Principle

**Every network operation requires physical presence.** Period.

No malicious code, no compromised process, no automated system can perform git network operations without you physically tapping your YubiKey.

## ✨ Features

### Security
- ✅ Physical YubiKey tap required for every network operation
- ✅ Cryptographic challenge-response (HMAC-SHA1) with touch flag
- ✅ Defense in depth (wrappers + hooks prevent bypass)
- ✅ Setup verification ensures physical access during install
- ✅ Auto-revert on failed setup (no incomplete states)
- ✅ Comprehensive logging for security audit

### User Experience
- ✅ Interactive setup with clear prompts
- ✅ Automatic shell config reload
- ✅ Visual feedback with emoji indicators
- ✅ Clear "👆 TAP YOUR YUBIKEY NOW" prompts
- ✅ Graceful error handling with recovery instructions
- ✅ Complete management CLI (setup/enable/disable/remove/status)

### Operations

**Requires YubiKey Tap:**
- `git push`, `git pull`, `git fetch`, `git clone`
- `git remote add/update`, `git submodule update --remote`
- `gh pr create/merge`, `gh release create`
- `gh repo clone`, `gh workflow run`

**Pass-Through (No Tap):**
- `git commit`, `git status`, `git log`, `git diff`
- All read-only operations

## 🚀 Quick Start

### Prerequisites

```bash
# Install YubiKey Manager
brew install ykman  # macOS
sudo apt install yubikey-manager  # Linux

# Supported YubiKeys:
# - YubiKey 5 series (5, 5C, 5 NFC, 5C NFC, 5 Nano, 5C Nano)
# - YubiKey 4 series
# - Any YubiKey with OTP support
```

### Installation

```bash
# 1. Clone this repository
git clone https://github.com/freddieweir/igris.git
cd igris

# 2. Configure YubiKey OTP slot 2 with touch requirement
./scripts/yubikey-configure-otp.sh configure
# Prompts: "Test YubiKey tap verification now? (yes/no): yes"
# [Auto-tests - requires YubiKey tap]

# 3. Install enforcement system
./scripts/yubikey-git-setup.sh setup
# Interactive setup → Installs wrappers & hooks
# Prompts: "Ready to verify YubiKey? [Y/n]"
# [Requires YubiKey tap to complete setup]

# 4. Restart terminal or reload shell config
source ~/.zshrc  # or ~/.bashrc
```

### Usage

```bash
# Normal git operations now require YubiKey tap
git push origin main
# Output:
# 🔑 YubiKey verification required for: git push
# ✅ YubiKey detected: Serial 12345678
# ℹ️  Verifying with OTP challenge-response (requires physical tap)...
# ℹ️  👆 TAP YOUR YUBIKEY NOW to verify (timeout: 10s)
# [You tap your YubiKey]
# ✅ YubiKey tap verified! (2s)
# ✅ Verification successful! Proceeding with git push
# [push proceeds normally]

# Read-only operations work without tap
git status  # No tap required
git log     # No tap required
```

## 🔧 Management

### Check Status
```bash
./scripts/yubikey-git-setup.sh status

# Output:
# Enforcement: ✅ ENABLED
# YubiKey:     ✅ Connected (YubiKey 5C Nano)
# Wrappers:    ✅ Installed (git, gh)
# Hooks:       ✅ Configured (global template)
```

### Temporarily Disable
```bash
# Disable (keeps configuration)
./scripts/yubikey-git-setup.sh disable

# Re-enable
./scripts/yubikey-git-setup.sh enable
```

### Complete Removal
```bash
# Remove everything (creates timestamped backups)
./scripts/yubikey-git-setup.sh remove

# Backups saved to: ~/.tomb-yubikey-backup/removal-TIMESTAMP/
```

### YubiKey OTP Management
```bash
# Check OTP slot status
./scripts/yubikey-configure-otp.sh status

# Reconfigure slot 2
./scripts/yubikey-configure-otp.sh configure

# Delete slot 2 (disables tap verification)
./scripts/yubikey-configure-otp.sh delete
```

## 📁 Repository Structure

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
│       └── pre-push                  # Pre-push hook
├── configs/
│   └── yubikey-enforcement.yml       # Configuration file
└── README.md                         # This file
```

## 🔍 How It Works

### 1. Shell Wrapper Layer

When you run `git push`, the shell wrapper:
1. Detects this is a network operation
2. Calls `yubikey-verify.sh`
3. Only proceeds if verification succeeds

### 2. YubiKey Verification

`yubikey-verify.sh` performs:
1. YubiKey presence detection
2. OTP challenge-response with random challenge
3. **Requires physical tap** (hardware enforced)
4. Returns success/failure

### 3. Git Hook Layer

Even if wrappers are bypassed, the `pre-push` hook:
1. Runs before any network push
2. Calls `yubikey-verify.sh` again
3. Aborts push if verification fails

### Defense in Depth

- **Layer 1 (Wrappers)**: Catches normal command usage
- **Layer 2 (Hooks)**: Catches direct binary invocations
- **Layer 3 (OPSEC)**: Monitors for tampering attempts

## 🛡️ Security Guarantees

### What Igris Protects Against

✅ Compromised development machines
✅ Malicious scripts automating git operations
✅ Supply chain attacks via git
✅ Unauthorized code pushes from your account
✅ Social engineering (requires physical hardware)

### What Igris Does NOT Protect Against

❌ Physical theft of YubiKey (use with PIN/biometric locks)
❌ Attacks after YubiKey tap (tap authorizes the specific operation)
❌ Vulnerabilities in YubiKey firmware itself
❌ Read-only git operations (these don't need protection)

## 🔐 Technical Details

### Verification Methods (Priority Order)

1. **OTP with required touch** (SECURE)
   - Cryptographic HMAC-SHA1 challenge-response
   - Touch flag set on YubiKey slot 2
   - Random 32-byte challenge per operation

2. **OTP without guaranteed touch** (LESS SECURE)
   - Fallback if slot not configured with --touch
   - Warns user to reconfigure

3. **FIDO2 presence** (NO TAP - INSECURE)
   - Only checks if YubiKey is plugged in
   - Loudly warns user this is insecure

4. **Simple presence** (INSECURE FALLBACK)
   - Last resort
   - Critical warnings displayed

### Configuration

Edit `configs/yubikey-enforcement.yml`:

```yaml
enforcement:
  enabled: true                # Master switch
  require_tap: true            # Require physical tap
  timeout_seconds: 10          # Tap timeout
  retry_attempts: 3            # Failed attempts before alert

operations:
  git:
    push: required             # Require tap for push
    pull: required             # Require tap for pull
    fetch: required            # Require tap for fetch
    clone: required            # Require tap for clone

security:
  alert_on_bypass_attempt: true
  log_file: ~/.tomb-yubikey-verifications.log
  max_failed_attempts: 5
```

## 🚨 Troubleshooting

### "No YubiKey detected"
- Ensure YubiKey is plugged in
- Check: `ykman list`
- Try replugging YubiKey

### "OTP Slot 2 is empty"
- Configure OTP slot 2: `./scripts/yubikey-configure-otp.sh configure`
- Ensures touch requirement is set

### "Timeout waiting for tap"
- Tap YubiKey more quickly (10 second timeout)
- Check YubiKey LED is blinking
- Ensure finger makes good contact

### "Verification failed in pre-push hook"
- Wrapper may be bypassed
- Hook provides secondary enforcement
- Check status: `./scripts/yubikey-git-setup.sh status`

### To Temporarily Disable
```bash
# Disable enforcement (for emergency situations)
export TOMB_YUBIKEY_ENABLED=false
git push  # Will work without tap (with warnings)

# Or properly disable:
./scripts/yubikey-git-setup.sh disable
```

## 🤝 Contributing

Contributions welcome! This is an open-source security tool.

### Areas for Improvement
- [ ] FIDO2 proper implementation (not just presence check)
- [ ] Windows support
- [ ] GUI installer
- [ ] Multi-YubiKey rotation support
- [ ] Time-based caching (configurable grace period)
- [ ] Homebrew formula
- [ ] Integration tests

### Submitting Changes
1. Fork the repository
2. Create a feature branch
3. Test thoroughly with your own YubiKey
4. Submit PR with clear description

## 📜 License

MIT License - See LICENSE file

## 🙏 Acknowledgments

- Yubico for YubiKey hardware and ykman CLI
- Git hooks and wrapper pattern inspiration from various security tools
- Defense-in-depth architecture principles

## 🔗 Links

- **GitHub Repository**: https://github.com/freddieweir/igris
- **YubiKey Manager**: https://github.com/Yubico/yubikey-manager
- **YubiKey Hardware**: https://www.yubico.com/products/

---

**"Physical presence required. Always."** 🔐

Made with ❤️ for secure development workflows.
