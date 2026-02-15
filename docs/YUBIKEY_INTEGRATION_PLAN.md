# 🇺🇸🔐 igris: YubiKey-Gated Privilege Escalation

> Physical authentication for AI agent permission boundaries

---

## Overview

igris becomes the security boundary between planning (Claude.app) and execution (Claude Code CLI + Gemini sub-agents). A YubiKey tap is required to escalate from read-only planning mode to full execution permissions.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Planning Layer                          │
│  ┌─────────────┐                                                │
│  │ Claude.app  │  Research, plan, discuss                       │
│  │ (this chat) │  No filesystem writes, no code execution       │
│  └──────┬──────┘                                                │
│         │                                                       │
│         │ "Ready to execute"                                    │
│         ▼                                                       │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────┐   │
│  │    igris    │────▶│  YubiKey    │────▶│ Session Token   │   │
│  │   elevate   │     │  FIDO2 tap  │     │ (time-limited)  │   │
│  └─────────────┘     └─────────────┘     └────────┬────────┘   │
│                                                    │            │
└────────────────────────────────────────────────────┼────────────┘
                                                     │
┌────────────────────────────────────────────────────┼────────────┐
│                      Execution Layer               │            │
│                                                    ▼            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Claude Code CLI                         │   │
│  │  + Gemini sub-agents (pleiades-agents)                   │   │
│  │                                                          │   │
│  │  Full permissions: filesystem, code execution, network   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Core Features

### `igris elevate`

Requests YubiKey tap to unlock execution permissions.

```bash
$ igris elevate
🔐 Requesting elevated permissions...
👆 Touch your YubiKey to continue

✅ Elevated session started
   Expires: 30 minutes (or next `igris lock`)
   Scope: ~/projects, ~/artificial-roundtable
```

**Implementation options:**
- FIDO2/WebAuthn via `python-fido2` library
- Or shell out to `ykman` (YubiKey Manager CLI)

### `igris lock`

Immediately revokes elevated session.

```bash
$ igris lock
🔒 Elevated session terminated
   Returning to planning mode
```

### `igris status`

Shows current permission level.

```bash
$ igris status
Mode: ELEVATED
Expires: 18 minutes remaining
Last elevated: 2026-01-24 14:32:00
Scope: ~/projects, ~/artificial-roundtable
```

### `igris guard <path>`

Marks directories for extra protection (requires elevation even for reads in some cases).

```bash
$ igris guard ~/artificial-roundtable/voice-fingerprint
🛡️ Path guarded: ~/artificial-roundtable/voice-fingerprint
   Requires elevation for: read, write, execute
```

---

## Session Management

| Parameter | Default | Configurable |
|-----------|---------|--------------|
| Session timeout | 30 min | Yes, in config |
| Auto-lock on idle | 10 min | Yes |
| Require re-tap for sensitive paths | Yes | Per-path |
| Session scope | Specified dirs | Yes |

### Session Storage

Session tokens stored in:
- `~/.igris/session.json` (encrypted with YubiKey-derived key)
- Or environment variable for current shell only

```json
{
  "token": "encrypted-session-token",
  "created_at": "2026-01-24T14:32:00Z",
  "expires_at": "2026-01-24T15:02:00Z",
  "scope": ["~/projects", "~/artificial-roundtable"],
  "yubikey_serial": "12345678"
}
```

---

## Integration with Claude Code CLI

### Pre-execution Hook

Claude Code CLI checks igris before any write/execute operation:

```python
# Pseudo-code for Claude Code integration
def before_action(action_type, path):
    if action_type in ['write', 'execute', 'delete']:
        if not igris.is_elevated():
            raise PermissionError("Run `igris elevate` first")
        if igris.is_guarded(path):
            if not igris.check_guard_permission(path):
                raise PermissionError(f"Path {path} requires explicit elevation")
```

### Gemini Sub-agent Permissions

Gemini sub-agents inherit the igris session from parent Claude Code process:
- Session token passed via environment
- Sub-agents cannot elevate themselves
- Any elevation request bubbles up to user

---

## Configuration

`~/.igris/config.yaml`:

```yaml
# igris configuration

session:
  default_timeout_minutes: 30
  idle_timeout_minutes: 10
  require_yubikey: true

yubikey:
  # Restrict to specific YubiKey serial (optional)
  allowed_serials:
    - "12345678"
  
  # FIDO2 relying party ID
  rp_id: "igris.local"

guarded_paths:
  # Always require elevation
  - path: "~/artificial-roundtable/voice-fingerprint"
    level: "strict"  # read+write+execute require elevation
  
  - path: "~/artificial-roundtable"
    level: "write"   # only writes require elevation
  
  - path: "~/.ssh"
    level: "strict"

# Paths that never require elevation (safe zone)
safe_paths:
  - "~/scratch"
  - "/tmp"

logging:
  enabled: true
  path: "~/.igris/audit.log"
```

---

## USB Passthrough (VM Integration)

For M4 Max VM usage:

1. YubiKey connected to host Mac
2. USB passthrough configured to VM
3. igris in VM sees YubiKey as local device

```bash
# On VM, verify YubiKey is visible
$ ykman info
Device type: YubiKey 5 NFC
Serial number: 12345678
...
```

### Apple Shortcuts Integration (Future)

Potential workflow:
1. Shortcut triggered: "Elevate igris session"
2. Shortcut sends command to VM via SSH
3. VM's igris prompts for YubiKey tap
4. Session elevated

This enables voice-triggered elevation: "Hey Siri, elevate igris"

---

## Audit Logging

All elevation events logged:

```
2026-01-24 14:32:00 | ELEVATE | yubikey:12345678 | scope:~/projects,~/artificial-roundtable | timeout:30m
2026-01-24 14:45:22 | ACCESS  | path:~/artificial-roundtable/voice-fingerprint | action:read | granted
2026-01-24 15:01:00 | LOCK    | reason:manual | session_duration:29m
```

---

## Resume/Portfolio Value

This project demonstrates:

| Skill | Evidence |
|-------|----------|
| Security architecture | Physical auth for privilege escalation |
| FIDO2/WebAuthn | YubiKey integration |
| Systems design | Session management, scope control |
| Python | Implementation |
| DevSecOps | Audit logging, principle of least privilege |

Can be open-sourced (minus personal config) as a portfolio piece.

---

## Implementation Phases

### Phase 1: Core CLI (MVP)
- [ ] `igris elevate` with YubiKey FIDO2
- [ ] `igris lock`
- [ ] `igris status`
- [ ] Basic session timeout

### Phase 2: Path Guarding
- [ ] `igris guard <path>`
- [ ] Config file support
- [ ] Audit logging

### Phase 3: Integrations
- [ ] Claude Code CLI hook
- [ ] Gemini sub-agent inheritance
- [ ] Apple Shortcuts trigger

### Phase 4: Polish
- [ ] Visual indicators (Hammerspoon glow when elevated?)
- [ ] Stream Deck integration
- [ ] Documentation for open source release

---

## Dependencies

```
python-fido2    # FIDO2/WebAuthn library
pyyaml          # Config parsing
click           # CLI framework
cryptography    # Session encryption
```

Or if shelling out to ykman:
```
yubikey-manager # brew install ykman
```

---

## Open Questions

1. **Session encryption**: Use YubiKey's PIV for deriving encryption key, or simpler approach?
2. **Multi-YubiKey**: Support multiple registered keys for backup?
3. **Remote elevation**: Allow elevation via SSH with agent forwarding?
4. **Integration depth**: Hook into shell (bash/zsh) or just CLI tools?

---

*Planning doc for Claude Code CLI handoff*
