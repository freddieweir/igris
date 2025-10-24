# Audio Assets

This directory contains audio files for the Igris YubiKey enforcement system.

## 🎵 Command-Specific Audio Alerts

The system plays different audio clips based on the git/gh command being executed. Configure mappings in `configs/audio-alerts.yml`.

### 🎯 Category-Based Audio System (Recommended)

**Semantic approach**: Different prefix sounds for different operation types + action voice clips.

**Example**:
- Write operations: `*alert-beep* + "git push"`
- Read operations: `*soft-chime* + "git pull"`
- Security alerts: `*warning-tone* + "bypass detected"`

**Benefits**:
- ✅ **Instant recognition**: Know operation type by sound before voice
- ✅ **Save time**: Generate 3 prefix tones + 12 actions = 15 files total
- ✅ **Attention management**: Different urgency levels for different ops
- ✅ **Muscle memory**: Learn to recognize operation categories by ear

**Operation Categories**:
- **Write** (`prefix-write-operation.wav`): push, merge, pr create, release - modifies remote
- **Read** (`prefix-read-operation.wav`): pull, fetch, clone - retrieves from remote
- **Security** (`prefix-security-alert.wav`): bypass detection, security warnings
- **Default** (`prefix-yubikey-tap-required-for.wav`): fallback for unmapped commands

### 📋 Quick Reference Table - Category-Based Audio

| Type | File | Status | Sound Description |
|------|------|--------|-------------------|
| **Category Prefixes** |
| Write Operations | `prefix-write-operation.wav` | ⬜ Missing | Alert beep/tone (higher urgency) |
| Read Operations | `prefix-read-operation.wav` | ⬜ Missing | Soft chime/tone (lower urgency) |
| Security Alerts | `prefix-security-alert.wav` | ⬜ Missing | Warning tone (urgent) |
| Default Fallback | `prefix-yubikey-tap-required-for.wav` | ✅ Present | Voice: "YubiKey tap required for" |
| **Git Actions** |
| `git push` | `action-git-push.wav` | ✅ Present | "git push" |
| `git pull` | `action-git-pull.wav` | ✅ Present | "git pull" |
| `git fetch` | `action-git-fetch.wav` | ✅ Present | "git fetch" |
| `git clone` | `action-git-clone.wav` | ✅ Present | "git clone" |
| `git remote add` | `action-git-remote-add.wav` | ⬜ Missing | "git remote add" |
| `git remote update` | `action-git-remote-update.wav` | ⬜ Missing | "git remote update" |
| `git submodule update` | `action-git-submodule-update.wav` | ⬜ Missing | "git submodule update" |
| **GitHub Actions** |
| `gh pr create` | `action-gh-pr-create.wav` | ✅ Present | "GitHub pull request create" |
| `gh pr merge` | `action-gh-pr-merge.wav` | ⬜ Missing | "GitHub pull request merge" |
| `gh release create` | `action-gh-release-create.wav` | ⬜ Missing | "GitHub release create" |
| `gh repo clone` | `action-gh-repo-clone.wav` | ⬜ Missing | "GitHub repo clone" |
| `gh workflow run` | `action-gh-workflow-run.wav` | ⬜ Missing | "GitHub workflow run" |
| **Security Alerts** |
| Bypass detected | `bypass-detected.wav` | ⬜ Missing | "Warning: YubiKey enforcement bypassed" |
| **Fallback** |
| Any other command | `prefix-yubikey-tap-required-for.wav` | ✅ Present | Uses prefix as fallback |

<details>
<summary>📜 Legacy Full-Phrase Audio (Optional - click to expand)</summary>

If modular audio doesn't sound right, you can disable it and use full phrases instead.

Set `use_modular_audio: false` in `configs/audio-alerts.yml`, then create these:

| Command | File | ElevenLabs Prompt |
|---------|------|-------------------|
| `git push` | `git-push.wav` | "YubiKey tap required for git push" |
| `git pull` | `git-pull.wav` | "YubiKey tap required for git pull" |
| `git fetch` | `git-fetch.wav` | "YubiKey tap required for git fetch" |
| (etc.) | | |

</details>

### 📝 How to Update

1. **Generate audio with ElevenLabs**:
   - Use the prompt from the table above
   - Export as WAV format (recommended) or MP3
   - Keep clips short (1-3 seconds)

2. **Add file to this directory**:
   ```bash
   # Example: Adding git push audio
   cp ~/Downloads/git-push.wav $GIT_ROOT/internal/repos/igris/assets/audio/
   ```

3. **Update status in table**:
   - Change ⬜ Missing to ✅ Present
   - Audio will automatically work for that command

4. **Test it**:
   ```bash
   # Test specific command
   git push  # Should play git-push.wav when asking for tap
   ```

### 🔧 Configuration

Audio mappings are in `configs/audio-alerts.yml`. The system:
- ✅ Automatically detects command type (git/gh)
- ✅ Matches command to audio file
- ✅ Falls back to default if file missing
- ✅ Falls back to system "Tink" if all files missing

### 🎯 Requirements
- **Format**: WAV preferred (instant playback), MP3 also supported
- **Duration**: 1-3 seconds (short, attention-grabbing)
- **Volume**: Normalized to avoid being too loud/quiet
- **Voice**: Clear, distinct, easy to understand

### 🧪 Testing

Test audio file directly:
```bash
afplay assets/audio/git-push.wav
```

Test with YubiKey verification:
```bash
git push  # Trigger real verification with audio
```
