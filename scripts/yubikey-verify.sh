#!/bin/bash

# YubiKey Verification Script
# Part of tomb-of-nazarick security enforcement system
# Requires physical YubiKey tap for verification

set -euo pipefail

# Configuration
TIMEOUT_SECONDS="${YUBIKEY_TIMEOUT:-10}"
LOG_FILE="${HOME}/.tomb-yubikey-verifications.log"
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${TOMB_DIR}/configs/yubikey-enforcement.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Operation context (passed by wrapper)
OPERATION="${1:-unknown}"

# Logging function
log_verification() {
    local status="$1"
    local method="$2"
    local serial="${3:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    echo "${timestamp} [${status}] ${OPERATION} - ${method} - Serial: ${serial}" >> "$LOG_FILE"
}

# Print with color
print_info() {
    echo -e "${BLUE}🔑${NC} $1" >&2
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

# Check if enforcement is enabled
check_enforcement_enabled() {
    if [ "${TOMB_YUBIKEY_ENABLED:-true}" = "false" ]; then
        print_warning "YubiKey enforcement is disabled (TOMB_YUBIKEY_ENABLED=false)"
        log_verification "BYPASSED" "enforcement_disabled" "n/a"
        return 1
    fi
    return 0
}

# Detect YubiKey presence
detect_yubikey() {
    if ! command -v ykman &> /dev/null; then
        print_error "ykman not found. Install with: brew install ykman"
        return 1
    fi

    local yubikey_info
    if ! yubikey_info=$(ykman list 2>/dev/null); then
        print_error "No YubiKey detected. Please connect your YubiKey."
        return 1
    fi

    if ! echo "$yubikey_info" | grep -q "YubiKey"; then
        print_error "No YubiKey detected. Please connect your YubiKey."
        return 1
    fi

    # Extract serial number
    YUBIKEY_SERIAL=$(echo "$yubikey_info" | grep -oE 'Serial: [0-9]+' | awk '{print $2}')

    return 0
}

# OTP Challenge-Response verification with REQUIRED physical touch
verify_otp_touch() {
    print_info "Verifying with OTP challenge-response (requires physical tap)..."

    # Check if OTP slot 2 is configured
    local otp_info
    if ! otp_info=$(ykman otp info 2>/dev/null); then
        print_warning "OTP not configured on this YubiKey"
        return 1
    fi

    # Check if slot 2 has a credential
    if echo "$otp_info" | grep -q "Slot 2: empty"; then
        print_warning "OTP Slot 2 is empty - needs configuration"
        print_info "Run: ykman otp chalresp --generate --touch 2"
        return 1
    fi

    # Generate random challenge
    local challenge=$(openssl rand -hex 32)

    print_info "👆 TAP YOUR YUBIKEY NOW to verify (timeout: ${TIMEOUT_SECONDS}s)"

    # Use ykman otp calculate which works with configured slots
    # This will REQUIRE physical touch if the slot was configured with --touch
    local response
    local start_time=$(date +%s)

    # Try the challenge-response
    if response=$(timeout "${TIMEOUT_SECONDS}s" ykman otp calculate 2 "$challenge" 2>&1); then
        local elapsed=$(($(date +%s) - start_time))
        print_success "YubiKey tap verified! (${elapsed}s)"
        log_verification "SUCCESS" "OTP-TOUCH" "$YUBIKEY_SERIAL"
        return 0
    else
        # Check if it was a timeout or other error
        if [[ "$response" =~ "timeout" ]] || [ $(($(date +%s) - start_time)) -ge $TIMEOUT_SECONDS ]; then
            print_error "Timeout waiting for YubiKey tap"
            log_verification "TIMEOUT" "OTP-TOUCH" "$YUBIKEY_SERIAL"
        else
            print_error "YubiKey verification failed: $response"
            log_verification "FAILURE" "OTP-TOUCH" "$YUBIKEY_SERIAL"
        fi
        return 1
    fi
}

# Legacy FIDO2 presence check (not secure - doesn't require tap)
verify_fido2_presence_only() {
    print_warning "Using FIDO2 presence check (does NOT require tap)"
    print_warning "This is insecure - configure OTP slot 2 for proper security"

    # Check if FIDO2 is available
    if ! ykman fido info &>/dev/null; then
        print_warning "FIDO2 not available on this YubiKey"
        return 1
    fi

    # Just check if device responds (NO TAP REQUIRED - INSECURE)
    if ykman fido info &>/dev/null; then
        print_warning "YubiKey detected (no tap verification)"
        log_verification "SUCCESS" "FIDO2-PRESENCE-ONLY" "$YUBIKEY_SERIAL"
        return 0
    else
        return 1
    fi
}

# OTP Challenge-Response verification (fallback)
verify_otp() {
    print_info "Attempting OTP challenge-response verification..."

    # Check if OTP is configured
    local otp_info
    if ! otp_info=$(ykman otp info 2>/dev/null); then
        print_warning "OTP not configured on this YubiKey"
        return 1
    fi

    # Check if slot 2 is configured for challenge-response
    if ! echo "$otp_info" | grep -q "Slot 2:"; then
        print_warning "OTP Slot 2 not configured for challenge-response"
        return 1
    fi

    # Generate challenge
    local challenge=$(openssl rand -hex 32)

    print_info "Please tap your YubiKey within ${TIMEOUT_SECONDS} seconds..."

    # Attempt challenge-response (requires tap if configured with --touch)
    local response
    if response=$(timeout "$TIMEOUT_SECONDS" ykman otp chalresp 2 "$challenge" 2>/dev/null); then
        print_success "YubiKey verified via OTP challenge-response!"
        log_verification "SUCCESS" "OTP" "$YUBIKEY_SERIAL"
        return 0
    else
        print_error "OTP verification failed or timeout"
        log_verification "TIMEOUT" "OTP" "$YUBIKEY_SERIAL"
        return 1
    fi
}

# Simple presence check (minimal security fallback)
verify_presence() {
    print_warning "Using minimal presence check (lowest security)"
    print_warning "Consider configuring FIDO2 or OTP for stronger security"

    # Just verify YubiKey is still connected
    if ykman list 2>/dev/null | grep -q "YubiKey"; then
        print_success "YubiKey presence confirmed"
        log_verification "SUCCESS" "PRESENCE" "$YUBIKEY_SERIAL"
        return 0
    else
        print_error "YubiKey no longer detected"
        log_verification "FAILURE" "PRESENCE" "$YUBIKEY_SERIAL"
        return 1
    fi
}

# Main verification flow
main() {
    # Check if enforcement is enabled
    if ! check_enforcement_enabled; then
        exit 0  # Pass through if disabled
    fi

    print_info "YubiKey verification required for: ${OPERATION}"

    # Detect YubiKey
    if ! detect_yubikey; then
        log_verification "FAILURE" "no_device" "n/a"
        print_error "Cannot proceed without YubiKey"
        echo "" >&2
        print_info "Recovery options:" >&2
        echo "  1. Connect your YubiKey and try again" >&2
        echo "  2. Temporarily disable: export TOMB_YUBIKEY_ENABLED=false" >&2
        echo "  3. Contact security team if YubiKey is lost" >&2
        exit 1
    fi

    print_success "YubiKey detected: Serial ${YUBIKEY_SERIAL}"

    # Try verification methods in priority order (most secure first)
    # 1. OTP with required physical touch (SECURE - REQUIRED)
    if verify_otp_touch; then
        print_success "✅ Verification successful! Proceeding with ${OPERATION}"
        exit 0
    fi

    # 2. OTP without guaranteed touch (LESS SECURE but acceptable)
    print_warning "OTP touch verification not available, trying OTP without touch..."
    if verify_otp; then
        print_warning "⚠️  Used OTP without guaranteed touch - consider configuring slot 2 with --touch"
        print_success "Verification successful! Proceeding with ${OPERATION}"
        exit 0
    fi

    # OTP verification failed - this is a hard failure
    print_error "YubiKey OTP verification failed!"
    print_error "YubiKey is connected but not properly configured"
    echo "" >&2
    print_info "Required configuration:" >&2
    echo "  1. Configure OTP slot 2: ${TOMB_DIR}/scripts/yubikey-configure-otp.sh configure" >&2
    echo "  2. Ensure tap within timeout (${TIMEOUT_SECONDS}s)" >&2
    echo "  3. Check YubiKey firmware supports OTP" >&2
    log_verification "FAILURE" "otp_not_configured" "$YUBIKEY_SERIAL"

    # Check for repeated failures (potential attack)
    local recent_failures=$(grep -c "\[FAILURE\]\|\[TIMEOUT\]" "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$recent_failures" -ge 5 ]; then
        print_warning "Multiple verification failures detected!"
        # Send macOS notification
        osascript -e 'display notification "Multiple YubiKey verification failures detected" with title "Security Alert" sound name "Basso"' &>/dev/null || true
    fi

    exit 1
}

# Run main function
main "$@"
