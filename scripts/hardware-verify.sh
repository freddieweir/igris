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
    command -v ykman &> /dev/null && ykman list 2>/dev/null | grep -q "YubiKey"
}

# Check if Touch ID is available
check_touchid_available() {
    command -v op &> /dev/null && op account list &>/dev/null 2>&1
}

# Main verification flow
main() {
    # Check if enforcement is enabled
    if ! check_enforcement_enabled; then
        exit 0  # Pass through if disabled
    fi

    print_info "Hardware verification required for: ${OPERATION}"
    echo "" >&2

    # Try verification methods in priority order

    # 1. YubiKey (most secure - hardware token with cryptographic verification)
    # Skip YubiKey if TOMB_TOUCHID_ONLY is set (for testing)
    if [ "${TOMB_TOUCHID_ONLY:-false}" = "false" ] && check_yubikey_available; then
        print_info "Attempting YubiKey verification (most secure)..."
        if "$YUBIKEY_VERIFY" "$OPERATION"; then
            exit 0
        fi
        echo "" >&2
        print_warning "YubiKey verification failed, trying alternative methods..."
        echo "" >&2
    fi

    # 2. Touch ID (secure - biometric with hardware-backed Secure Enclave)
    if check_touchid_available; then
        print_info "Attempting Touch ID verification..."
        if "$TOUCHID_VERIFY" "$OPERATION"; then
            exit 0
        fi
        echo "" >&2
        print_warning "Touch ID verification failed"
        echo "" >&2
    fi

    # All methods failed
    print_error "All hardware verification methods failed"
    log_verification "FAILURE" "all_methods"
    echo "" >&2
    print_info "Recovery options:" >&2
    echo "  1. Connect your YubiKey and try again" >&2
    echo "  2. Ensure 1Password CLI is signed in: op signin" >&2
    echo "  3. Temporarily disable: export TOMB_YUBIKEY_ENABLED=false" >&2
    echo "  4. Check status: ${TOMB_DIR}/scripts/yubikey-git-setup.sh status" >&2

    # Check for repeated failures (potential attack)
    local recent_failures=$(grep -c "\[FAILURE\]\|\[TIMEOUT\]" "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$recent_failures" -ge 5 ]; then
        print_warning "Multiple verification failures detected!"
        # Send macOS notification
        osascript -e 'display notification "Multiple hardware verification failures detected" with title "Security Alert" sound name "Basso"' &>/dev/null || true
    fi

    exit 1
}

# Run main function
main "$@"
