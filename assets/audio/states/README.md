# State-Based Audio Alerts

This directory contains audio files for verification state feedback. These files provide immediate auditory indication of verification results and errors.

## Required Audio Files

### Completion States

#### `verification-complete.wav`
**When played**: After successful YubiKey verification (tap accepted)
**Purpose**: Immediate positive feedback that hardware verification succeeded
**Suggested content**:
- Short affirmative tone (1-2 seconds)
- Examples: "Verified", "Complete", "Success", or a positive chime

**ElevenLabs prompt example**:
```
A brief, professional confirmation: "Verified"
Voice: Confident, authoritative
Duration: ~1 second
```

#### `verification-cached.wav` (Optional)
**When played**: When using cached verification within 5-second window (second layer check)
**Purpose**: Indicate that verification was reused from recent tap
**Suggested content**:
- Subtle acknowledgment (0.5-1 second)
- Examples: "Cached", "Reused", or a soft click sound
- Should be distinct from "complete" but less prominent

**ElevenLabs prompt example**:
```
A subtle, quiet acknowledgment: "Cached"
Voice: Soft, understated
Duration: ~0.5 seconds
```

**Note**: If not provided, system will reuse `verification-complete.wav` for cached verifications.

---

### Error States

#### `error-timeout.wav`
**When played**: User didn't tap YubiKey within 10-second timeout window
**Purpose**: Alert that verification failed due to timeout
**Suggested content**:
- Clear error indication (1-2 seconds)
- Examples: "Timeout", "No tap detected", "Verification timed out"

**ElevenLabs prompt example**:
```
A clear error message: "Verification timeout"
Voice: Professional, alert tone
Duration: ~1.5 seconds
```

#### `error-no-yubikey.wav`
**When played**: YubiKey hardware not detected or unplugged
**Purpose**: Alert that YubiKey is not connected
**Suggested content**:
- Hardware issue alert (1-2 seconds)
- Examples: "YubiKey not found", "No hardware detected", "Connect YubiKey"

**ElevenLabs prompt example**:
```
A hardware alert: "YubiKey not detected"
Voice: Professional, concerned tone
Duration: ~1.5 seconds
```

#### `error-verification-failed.wav`
**When played**: Challenge-response mismatch or cryptographic verification failed
**Purpose**: Alert that YubiKey responded but verification failed
**Suggested content**:
- Security failure alert (1-2 seconds)
- Examples: "Verification failed", "Invalid response", "Authentication error"

**ElevenLabs prompt example**:
```
A security alert: "Verification failed"
Voice: Serious, authoritative
Duration: ~1.5 seconds
```

#### `error-timing-violation.wav`
**When played**: YubiKey response too fast (< 800ms), indicating OTP slot not configured with --touch
**Purpose**: Alert that hardware tap requirement is not properly configured
**Suggested content**:
- Configuration error alert (2-3 seconds)
- Examples: "Configuration error", "Touch not required", "Security violation"

**ElevenLabs prompt example**:
```
A serious security warning: "Security violation: touch not configured"
Voice: Urgent, authoritative
Duration: ~2 seconds
```

---

## Audio File Specifications

**Format**: WAV (uncompressed)
**Sample rate**: 44.1 kHz or 48 kHz
**Bit depth**: 16-bit or 24-bit
**Channels**: Mono or Stereo
**Duration**: 0.5-3 seconds (keep brief for minimal disruption)

---

## Placeholder Files

Until you provide custom audio files, the system will:
1. Check for each required file before playing
2. Fall back to system sounds if file missing (via `afplay /System/Library/Sounds/Funk.aiff`)
3. Log warning in `~/.tomb-yubikey-verifications.log` when using fallback

To add your custom audio:
1. Generate audio using ElevenLabs with prompts above
2. Save as WAV files with exact filenames listed
3. Place in this directory (`assets/audio/states/`)
4. Test with: `afplay assets/audio/states/verification-complete.wav`

---

## Testing Audio Files

```bash
# Test individual files
afplay assets/audio/states/verification-complete.wav
afplay assets/audio/states/verification-cached.wav
afplay assets/audio/states/error-timeout.wav
afplay assets/audio/states/error-no-yubikey.wav
afplay assets/audio/states/error-verification-failed.wav
afplay assets/audio/states/error-timing-violation.wav

# Test all files in sequence
for file in assets/audio/states/*.wav; do
    echo "Playing: $(basename "$file")"
    afplay "$file"
    sleep 1
done
```

---

## Integration with Verification System

These audio files are configured in `configs/audio-alerts.yml` under the `states` section. The verification system (`scripts/yubikey-verify.sh`) will:

1. **Before verification**: Play modular audio (prefix + action)
2. **After verification**: Play appropriate state audio:
   - Success → `verification-complete.wav`
   - Cache hit → `verification-cached.wav`
   - Timeout → `error-timeout.wav`
   - No YubiKey → `error-no-yubikey.wav`
   - Failed verification → `error-verification-failed.wav`
   - Timing violation → `error-timing-violation.wav`

This provides complete auditory feedback for the entire verification lifecycle.
