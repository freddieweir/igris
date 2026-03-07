#!/bin/bash

# Hardware Verification Orchestrator
# Part of Igris security enforcement system
# Delegates to specific verification methods (YubiKey, Touch ID)

set -euo pipefail

# Configuration
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
YUBIKEY_VERIFY="${TOMB_DIR}/scripts/yubikey-verify.sh"
TOUCHID_VERIFY="${TOMB_DIR}/scripts/touchid-verify.sh"
CONFIG_FILE="${TOMB_DIR}/configs/yubikey-enforcement.yml"
LOG_FILE="${HOME}/.tomb-yubikey-verifications.log"

# Parse config for verification method and Touch ID settings
# Default to yubikey-only mode (most secure)
VERIFICATION_METHOD="${TOMB_VERIFICATION_METHOD:-}"
TOUCHID_ENABLED="${TOMB_TOUCHID_ENABLED:-}"

# Read from config file if not set via environment
if [ -z "$VERIFICATION_METHOD" ] && [ -f "$CONFIG_FILE" ]; then
    VERIFICATION_METHOD=$(grep -E "^\s*method:" "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '\r')
fi
if [ -z "$TOUCHID_ENABLED" ] && [ -f "$CONFIG_FILE" ]; then
    TOUCHID_ENABLED=$(grep -E "^\s+enabled:" "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '\r')
fi

# Defaults: yubikey-only mode, Touch ID disabled
VERIFICATION_METHOD="${VERIFICATION_METHOD:-yubikey}"
TOUCHID_ENABLED="${TOUCHID_ENABLED:-false}"

# Use Homebrew ykman explicitly to avoid broken Python installations
if [ -x "/opt/homebrew/bin/ykman" ]; then
    YKMAN_BIN="/opt/homebrew/bin/ykman"
else
    YKMAN_BIN="ykman"  # Fallback to PATH
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Operation context (passed by wrapper)
OPERATION="${1:-unknown}"

# Print with color
print_info() {
    echo -e "${BLUE}ℹ️${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}✅${NC} $1" >&2
}

print_error() {
    echo -e "${RED}❌${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1" >&2
}

# Logging function
log_verification() {
    local status="$1"
    local method="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    echo "${timestamp} [${status}] ${OPERATION} - ${method} - Serial: n/a" >> "$LOG_FILE"
}

# Check if enforcement is enabled
check_enforcement_enabled() {
    if [ "${TOMB_YUBIKEY_ENABLED:-true}" = "false" ]; then
        print_warning "Hardware enforcement is disabled (TOMB_YUBIKEY_ENABLED=false)"
        log_verification "BYPASSED" "enforcement_disabled"
        return 1
    fi
    return 0
}

# Check if YubiKey is available
check_yubikey_available() {
    command -v "$YKMAN_BIN" &> /dev/null && "$YKMAN_BIN" list 2>/dev/null | grep -q "YubiKey"
}

# Check if Touch ID is available
check_touchid_available() {
    command -v op &> /dev/null && op account list &>/dev/null 2>&1
}

# Check if Touch ID fallback is allowed based on config
is_touchid_fallback_allowed() {
    # Respect verification method setting
    case "$VERIFICATION_METHOD" in
        yubikey)
            # YubiKey-only mode: no Touch ID fallback
            return 1
            ;;
        touchid)
            # Touch ID only mode: always allow (but YubiKey skipped above)
            return 0
            ;;
        auto|*)
            # Auto mode: check if Touch ID is explicitly enabled
            if [ "$TOUCHID_ENABLED" = "true" ]; then
                return 0
            fi
            return 1
            ;;
    esac
}

# Main verification flow
main() {
    # Check if enforcement is enabled
    if ! check_enforcement_enabled; then
        exit 0  # Pass through if disabled
    fi

    print_info "Hardware verification required for: ${OPERATION}"
    print_info "Verification mode: ${VERIFICATION_METHOD} (Touch ID fallback: ${TOUCHID_ENABLED})"
    echo "" >&2

    # Try verification methods based on configuration

    # 1. YubiKey (most secure - hardware token with cryptographic verification)
    # Skip YubiKey if TOMB_TOUCHID_ONLY is set (for testing) or method is touchid-only
    if [ "${TOMB_TOUCHID_ONLY:-false}" = "false" ] && [ "$VERIFICATION_METHOD" != "touchid" ] && check_yubikey_available; then
        print_info "Attempting YubiKey verification (most secure)..."
        if "$YUBIKEY_VERIFY" "$OPERATION"; then
            exit 0
        fi
        echo "" >&2

        # Only mention fallback if Touch ID is actually allowed
        if is_touchid_fallback_allowed; then
            print_warning "YubiKey verification failed, trying Touch ID fallback..."
        else
            print_warning "YubiKey verification failed (Touch ID fallback disabled)"
        fi
        echo "" >&2
    fi

    # 2. Touch ID (secure - biometric with hardware-backed Secure Enclave)
    # Only attempt if allowed by configuration
    if is_touchid_fallback_allowed && check_touchid_available; then
        print_info "Attempting Touch ID verification..."
        if "$TOUCHID_VERIFY" "$OPERATION"; then
            exit 0
        fi
        echo "" >&2
        print_warning "Touch ID verification failed"
        echo "" >&2
    fi

    # All methods failed
    print_error "Hardware verification failed"
    log_verification "FAILURE" "all_methods"
    echo "" >&2
    print_info "Recovery options:" >&2
    echo "  1. Connect your YubiKey and try again" >&2
    if [ "$VERIFICATION_METHOD" = "yubikey" ]; then
        echo "  2. Enable Touch ID fallback: set touchid.enabled: true in config" >&2
    else
        echo "  2. Ensure 1Password CLI is signed in: op signin" >&2
    fi
    echo "  3. Temporarily disable: export TOMB_YUBIKEY_ENABLED=false" >&2
    echo "  4. Check status: ${TOMB_DIR}/scripts/hardware-git-setup.sh status" >&2

    # Check for repeated failures within 5-minute window (potential attack)
    local five_min_ago
    five_min_ago=$(date -u -v-5M +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || date -u -d '5 minutes ago' +"%Y-%m-%dT%H:%M:%S")
    local recent_failures
    recent_failures=$(awk -v cutoff="$five_min_ago" '$1 >= cutoff' "$LOG_FILE" 2>/dev/null | grep -c "\[FAILURE\]\|\[TIMEOUT\]" || echo "0")
    if [ "$recent_failures" -ge 5 ]; then
        print_warning "Multiple verification failures detected (${recent_failures} in last 5 minutes)!"
        # Send macOS notification
        osascript -e 'display notification "Multiple hardware verification failures detected" with title "Security Alert" sound name "Basso"' &>/dev/null || true
    fi

    exit 1
}

# Run main function
main "$@"
