# Dangerous Command Audio Files

Audio clips for dangerous shell command protection (rm -rf, etc.).

## Required Files

| File | Phrase | Tone | Duration |
|------|--------|------|----------|
| `prefix-dangerous-operation.wav` | "YubiKey tap required for dangerous operation" | Serious, warning (firm but not panic) | ~2s |
| `action-rm.wav` | "remove" | Clear, final | ~0.5s |

## Generation Guide

Use ElevenLabs with these settings:
- **Voice**: Albedo v2 (or your preferred voice)
- **Stability**: 0.5-0.6 (consistent but with some variation)
- **Similarity**: 0.75 (natural)
- **Style**: 0.2-0.3 (subtle expression)

### Prompts

**prefix-dangerous-operation.wav**:
```
YubiKey tap required for dangerous operation
```
- Tone: Authoritative warning
- Pacing: Measured, clear
- Not panicked, but serious

**action-rm.wav**:
```
remove
```
- Tone: Clear, final
- Pacing: Normal
- Conveys finality of the action

## Future Audio Files

When additional commands are added:
- `action-sudo.wav` - "sudo"
- `action-chmod.wav` - "chmod"

## Fallback

If audio files are missing, the system falls back to:
1. `prefix_sound_security` from global config
2. System sound: Sosumi (serious alert)
