#!/bin/bash

# Touch ID Verification Script
# Part of Igris hardware enforcement system
# Requires Touch ID via 1Password CLI biometric unlock

set -euo pipefail

# Configuration
TIMEOUT_SECONDS="${YUBIKEY_TIMEOUT:-10}"
LOG_FILE="${HOME}/.tomb-yubikey-verifications.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Operation context (passed by orchestrator)
OPERATION="${1:-unknown}"

# Logging function
log_verification() {
    local status="$1"
    local method="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    echo "${timestamp} [${status}] ${OPERATION} - ${method} - Serial: 1password-cli" >> "$LOG_FILE"
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

# Check if 1Password CLI is available
check_1password_cli() {
    if ! command -v op &> /dev/null; then
        print_error "1Password CLI (op) not found"
        print_info "Install with: brew install 1password-cli"
        return 1
    fi

    # Check if signed in
    if ! op account list &>/dev/null; then
        print_error "1Password CLI not signed in"
        print_info "Sign in with: op signin"
        return 1
    fi

    return 0
}

# Touch ID verification via 1Password CLI
verify_touchid() {
    print_info "Verifying with Touch ID via 1Password CLI..."

    # NOTE: Touch ID enforcement depends on 1Password app settings:
    # - "Require Touch ID" must be enabled in 1Password app
    # - Session timeout should be set to a short duration
    # - This provides physical presence verification via biometric

    print_warning "Touch ID verification relies on 1Password biometric settings"
    print_info "Ensure 'Require Touch ID' is enabled in 1Password app preferences"
    echo "" >&2

    # Use item list which accesses vault data
    # With biometric unlock enabled and proper timeout, this requires Touch ID
    local start_time=$(date +%s)
    local output

    if output=$(timeout "${TIMEOUT_SECONDS}s" op item list --format=json 2>&1 | head -1); then
        local elapsed=$(($(date +%s) - start_time))

        # Verify we got valid output
        if [ -n "$output" ]; then
            print_success "1Password CLI verification successful (${elapsed}s)"
            print_info "If Touch ID did not prompt, check 1Password app biometric settings"
            log_verification "SUCCESS" "TOUCH-ID"
            return 0
        fi
    fi

    # If we reach here, verification failed
    local elapsed=$(($(date +%s) - start_time))
    if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
        print_error "Timeout waiting for 1Password CLI"
        log_verification "TIMEOUT" "TOUCH-ID"
    else
        print_error "1Password CLI verification failed"
        log_verification "FAILURE" "TOUCH-ID"
    fi
    return 1
}

# Main verification flow
main() {
    print_info "Touch ID verification for: ${OPERATION}"

    # Check if 1Password CLI is available and signed in
    if ! check_1password_cli; then
        log_verification "FAILURE" "TOUCH-ID-UNAVAILABLE"
        exit 1
    fi

    # Attempt Touch ID verification
    if verify_touchid; then
        print_success "✅ Verification successful! Proceeding with ${OPERATION}"
        exit 0
    else
        print_error "Touch ID verification failed"
        echo "" >&2
        print_info "Troubleshooting:" >&2
        echo "  1. Ensure Touch ID is enabled in System Settings" >&2
        echo "  2. Check 1Password app for biometric unlock settings" >&2
        echo "  3. Try: op signin (to refresh authentication)" >&2
        echo "  4. Verify Touch ID sensor is working" >&2
        exit 1
    fi
}

# Run main function
main "$@"
