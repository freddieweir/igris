# USB Passthrough for YubiKey in Docker

This guide covers how to use physical YubiKey devices with the igris Docker container across different platforms.

## Platform Support Matrix

| Platform | FIDO2 Registration | FIDO2 Auth | OTP Auth | Notes |
|---|---|---|---|---|
| Linux (native Docker) | Direct USB mount | Direct USB mount | No USB needed | Best support |
| macOS (Docker Desktop) | Host-mode only | Host-mode only | No USB needed | No USB passthrough |
| macOS (Parallels VM) | USB forwarding | USB forwarding | No USB needed | Requires config |
| Windows (Docker Desktop) | Host-mode only | Host-mode only | No USB needed | No USB passthrough |

## Architecture

```
┌──────────────────────────────────┐
│         Host Machine             │
│                                  │
│  ┌──────────┐  ┌──────────────┐  │
│  │ YubiKey  │  │   igris      │  │
│  │ (USB)    │  │ (host-mode)  │  │
│  └────┬─────┘  └──────┬───────┘  │
│       │               │          │
│       │    Register    │          │
│       └───────────────►│          │
│                        │          │
│              ┌─────────▼────────┐ │
│              │   igris.db      │ │
│              │  (shared vol)   │ │
│              └─────────┬───────┘ │
│                        │ mount   │
│              ┌─────────▼───────┐ │
│              │  igris Docker   │ │
│              │  (validates     │ │
│              │   sessions)     │ │
│              └─────────────────┘ │
└──────────────────────────────────┘
```

## Linux: Native USB Passthrough

Linux Docker supports direct USB device access via device mounting.

### Basic Setup

```yaml
# docker-compose.yml
services:
  igris:
    # ... existing config ...
    devices:
      - /dev/bus/usb:/dev/bus/usb
```

### Targeted Device Mount (Recommended)

More secure than mounting the entire USB bus:

```bash
# Find your YubiKey device path
lsusb | grep Yubico
# Example output: Bus 001 Device 042: ID 1050:0407 Yubico.com YubiKey OTP+FIDO+CCID

# Mount specific device
docker run -d \
  --device /dev/bus/usb/001/042 \
  -v igris-data:/data \
  -p 8920:8920 \
  igris
```

### udev Rules

Create persistent device permissions:

```bash
# /etc/udev/rules.d/70-yubikey.rules
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050", MODE="0660", GROUP="plugdev"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1050", MODE="0660", GROUP="plugdev"
```

Apply rules:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## macOS: Host-Mode Registration

Docker Desktop for macOS does not support USB passthrough. Use the host-mode pattern instead:

### Pattern: Register on Host, Auth in Container

1. **Run igris directly on host** for registration (requires USB access):

```bash
# Install igris on host
uv sync

# Start igris on host temporarily for registration
IGRIS_DB_PATH=./data/igris.db \
IGRIS_DB_MASTER_KEY_FILE=./data/.igris-master-key \
uv run uvicorn igris.main:app --host 127.0.0.1 --port 8920
```

2. **Register your YubiKey** via the FIDO2 endpoints (key physically connected to host).

3. **Stop host igris**, mount the database into Docker:

```yaml
# docker-compose.yml
services:
  igris:
    volumes:
      - ./data:/data  # Contains igris.db with registered key
```

4. **Auth from container**: For FIDO2 auth, the ceremony requires the physical key on the host — use host-mode for FIDO2 flows. For OTP auth, no USB is needed (password-based).

### OTP: The USB-Free Alternative

OTP authentication does not require USB passthrough at all. Once a key is registered, configure an OTP credential:

```bash
# Register OTP credential (one-time, after FIDO2 key registration)
curl -X POST http://localhost:8920/auth/otp/register \
  -H 'Content-Type: application/json' \
  -d '{"yubikey_serial": "12345678", "password": "your-long-tap-output"}'

# Authenticate via OTP (no USB needed)
curl -X POST http://localhost:8920/auth/otp/verify \
  -H 'Content-Type: application/json' \
  -d '{"password": "your-long-tap-output"}'
```

## Parallels Desktop: USB Forwarding

For macOS VMs running under Parallels Desktop Pro, USB devices can be forwarded to the VM.

### Configuration

1. **Parallels settings**: VM Configuration > Hardware > USB
2. **Add YubiKey**: Select "Yubico YubiKey" from device list
3. **Persistent assignment**: Enable "Connect to this virtual machine" for the YubiKey serial

### Persistent Assignment by Serial

```bash
# List connected USB devices in VM
system_profiler SPUSBDataType | grep -A 5 "YubiKey"

# Verify device is accessible
# The YubiKey should appear as a HID device
ls /dev/hidraw* 2>/dev/null || echo "No HID devices (expected on macOS)"
```

Once USB is forwarded to the Parallels VM, Linux Docker USB passthrough works normally within the VM.

## Security Considerations

- **Never use `--privileged`**: This grants full device access and disables security features
- **Prefer `--device` over volume mounts**: More targeted, less attack surface
- **OTP flow never requires USB**: Use OTP for containerized/VM environments where USB is impractical
- **Database encryption**: igris uses sqlcipher when available — the database file contains credential hashes, not raw keys
- **Network isolation**: Bind igris to localhost or trusted subnets only
