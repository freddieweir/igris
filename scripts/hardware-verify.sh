#!/bin/bash

# Hardware Verification Orchestrator
# Part of Igris security enforcement system
# Delegates to: YubiKey Slot 1 (HMAC) → YubiKey Slot 2 (backup password)

set -euo pipefail

# Configuration
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
YUBIKEY_VERIFY="${TOMB_DIR}/scripts/yubikey-verify.sh"
BACKUP_VERIFY="${TOMB_DIR}/scripts/backup-password-verify.sh"
CONFIG_FILE="${TOMB_DIR}/configs/yubikey-enforcement.yml"
LOG_FILE="${HOME}/.tomb-yubikey-verifications.log"

# Parse config for verification method and backup password settings
# Default to yubikey-only mode (most secure)
VERIFICATION_METHOD="${TOMB_VERIFICATION_METHOD:-}"
BACKUP_PASSWORD_ENABLED="${TOMB_BACKUP_PASSWORD_ENABLED:-}"

# Read from config file if not set via environment
if [ -z "$VERIFICATION_METHOD" ] && [ -f "$CONFIG_FILE" ]; then
    VERIFICATION_METHOD=$(grep -E "^\s*method:" "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '\r')
fi
if [ -z "$BACKUP_PASSWORD_ENABLED" ] && [ -f "$CONFIG_FILE" ]; then
    # Parse backup_password.enabled specifically
    BACKUP_PASSWORD_ENABLED=$(awk '/^\s+backup_password:/{found=1} found && /enabled:/{print $2; exit}' "$CONFIG_FILE" | tr -d '\r')
fi

# Defaults: yubikey-only mode, backup password enabled
VERIFICATION_METHOD="${VERIFICATION_METHOD:-yubikey}"
BACKUP_PASSWORD_ENABLED="${BACKUP_PASSWORD_ENABLED:-true}"

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

# Check if backup password is available and configured
check_backup_available() {
    [ -f "${HOME}/.config/igris/backup-auth.hash" ] && [ -x "$BACKUP_VERIFY" ]
}

# Check if backup password fallback is allowed based on config
is_backup_fallback_allowed() {
    case "$VERIFICATION_METHOD" in
        yubikey)
            # YubiKey-only mode: allow backup password if enabled (it's still YubiKey-based)
            if [ "$BACKUP_PASSWORD_ENABLED" = "true" ]; then
                return 0
            fi
            return 1
            ;;
        auto|*)
            # Auto mode: check if backup password is explicitly enabled
            if [ "$BACKUP_PASSWORD_ENABLED" = "true" ]; then
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
    print_info "Verification mode: ${VERIFICATION_METHOD} (backup password fallback: ${BACKUP_PASSWORD_ENABLED})"
    echo "" >&2

    # Try verification methods based on configuration

    # 1. YubiKey Slot 1 HMAC-SHA1 (most secure - cryptographic challenge-response)
    if check_yubikey_available; then
        print_info "Attempting YubiKey HMAC verification (Slot 1, short tap)..."
        if "$YUBIKEY_VERIFY" "$OPERATION"; then
            exit 0
        fi
        echo "" >&2

        if is_backup_fallback_allowed; then
            print_warning "YubiKey HMAC failed, trying backup password (Slot 2, long press)..."
        else
            print_warning "YubiKey HMAC failed (backup password fallback disabled)"
        fi
        echo "" >&2
    fi

    # 2. Backup Password (YubiKey Slot 2 static password — still hardware-bound)
    if is_backup_fallback_allowed && check_backup_available; then
        if "$BACKUP_VERIFY" "$OPERATION"; then
            exit 0
        fi
        echo "" >&2
        print_warning "Backup password verification failed"
        echo "" >&2
    elif is_backup_fallback_allowed && ! check_backup_available; then
        print_warning "Backup password not configured"
        print_info "Set up with: ${TOMB_DIR}/scripts/backup-password-setup.sh setup"
        echo "" >&2
    fi

    # All methods failed
    print_error "Hardware verification failed"
    log_verification "FAILURE" "all_methods"
    echo "" >&2
    print_info "Recovery options:" >&2
    echo "  1. Connect your YubiKey and try again" >&2
    echo "  2. Set up backup password: ${TOMB_DIR}/scripts/backup-password-setup.sh setup" >&2
    echo "  3. Temporarily disable: export TOMB_YUBIKEY_ENABLED=false" >&2
    echo "  4. Check status: ${TOMB_DIR}/scripts/hardware-git-setup.sh status" >&2

    # Check for repeated failures in last 5 minutes (potential attack)
    local failure_window=300  # 5 minutes in seconds
    local current_epoch=$(date +%s)
    local recent_failures=0
    if [ -f "$LOG_FILE" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ \[FAILURE\]|\[TIMEOUT\] ]]; then
                local log_ts=$(echo "$line" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
                if [ -n "$log_ts" ]; then
                    local log_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$log_ts" +%s 2>/dev/null || echo "0")
                    if [ $((current_epoch - log_epoch)) -lt $failure_window ]; then
                        recent_failures=$((recent_failures + 1))
                    fi
                fi
            fi
        done < "$LOG_FILE"
    fi
    if [ "$recent_failures" -ge 5 ]; then
        print_warning "Multiple verification failures detected!"
        osascript -e 'display notification "Multiple hardware verification failures in last 5 minutes" with title "🔒 Security Alert" sound name "Basso"' &>/dev/null || true
    fi

    exit 1
}

# Run main function
main "$@"
