#!/bin/bash

# YubiKey OTP Configuration Helper
# Manages OTP slot for HMAC-SHA1 challenge-response with REQUIRED physical touch
# Part of igris security system

set -euo pipefail

# Configuration
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${TOMB_DIR}/configs/yubikey-enforcement.yml"

# Read OTP slot from config/env (default: 1)
if [ -z "${IGRIS_OTP_SLOT:-}" ] && [ -f "$CONFIG_FILE" ]; then
    IGRIS_OTP_SLOT=$(grep -A 5 "^yubikey:" "$CONFIG_FILE" 2>/dev/null | grep "slot:" | head -1 | awk '{print $2}')
fi
SLOT="${IGRIS_OTP_SLOT:-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

show_usage() {
    cat << EOF
YubiKey OTP Slot ${SLOT} Management

USAGE:
    $(basename "$0") [COMMAND]

COMMANDS:
    configure   Configure OTP Slot ${SLOT} with touch-required challenge-response
    delete      Delete OTP Slot ${SLOT} configuration
    status      Show current OTP slot status
    help        Show this help message

EXAMPLES:
    $(basename "$0") configure    # Set up touch-required verification
    $(basename "$0") status        # Check current configuration
    $(basename "$0") delete        # Remove Slot ${SLOT} configuration

NOTES:
    - Slot ${SLOT} is used for YubiKey igris enforcement (HMAC-SHA1)
    - Touch requirement ensures physical presence for verification
    - Deleting Slot ${SLOT} will disable tap verification (falls back to insecure mode)
    - Override slot with IGRIS_OTP_SLOT env var or yubikey.slot in config

EOF
}

check_prerequisites() {
    if ! command -v ykman &> /dev/null; then
        print_error "ykman not found. Install with: brew install ykman"
        exit 1
    fi

    if ! ykman list 2>/dev/null | grep -q "YubiKey"; then
        print_error "No YubiKey detected. Please connect your YubiKey."
        exit 1
    fi
}

cmd_status() {
    print_header "YubiKey OTP Status"

    check_prerequisites

    # Get YubiKey info
    YUBIKEY_INFO=$(ykman list 2>/dev/null)
    print_info "Detected: $YUBIKEY_INFO"
    echo ""

    # Show OTP slot status
    print_info "OTP Slot Status:"
    ykman otp info

    echo ""
    # Check if configured slot is ready
    if ykman otp info 2>/dev/null | grep -q "Slot ${SLOT}: programmed"; then
        print_success "Slot ${SLOT} is configured (tap-required verification available)"
        echo ""
        print_info "Test verification:"
        echo "  \$TOMB_DIR/scripts/yubikey-verify.sh \"test\""
    elif ykman otp info 2>/dev/null | grep -q "Slot ${SLOT}: empty"; then
        print_warning "Slot ${SLOT} is NOT configured"
        echo ""
        print_info "Configure with:"
        echo "  $(basename "$0") configure"
    fi
    echo ""
}

cmd_configure() {
    print_header "YubiKey OTP Slot ${SLOT} Configuration (Touch-Required)"

    check_prerequisites

    # Get YubiKey info
    YUBIKEY_INFO=$(ykman list 2>/dev/null)
    print_info "Detected: $YUBIKEY_INFO"
    echo ""

    # Check current OTP slot status
    print_info "Checking OTP Slot ${SLOT} status..."
    ykman otp info
    echo ""

    # Check if slot is already configured
    if ykman otp info 2>/dev/null | grep -q "Slot ${SLOT}: programmed"; then
        print_warning "OTP Slot ${SLOT} is already programmed!"
        echo ""
        echo "Options:"
        echo "  1. Overwrite (will generate NEW credential - breaks existing uses)"
        echo "  2. Cancel (keep current configuration)"
        echo ""
        read -p "Enter choice (1/2): " choice

        case "$choice" in
            1)
                print_warning "Proceeding with overwrite..."
                ;;
            2)
                print_info "Configuration cancelled"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi

    # Configure slot with challenge-response + touch requirement
    echo ""
    print_header "Configuring OTP Slot ${SLOT}"

    echo "This will:"
    echo "  • Generate a random secret key for challenge-response"
    echo "  • Store it securely on your YubiKey (Slot ${SLOT})"
    echo "  • Require physical touch for every verification"
    echo ""
    read -p "Proceed with configuration? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "Configuration cancelled"
        exit 0
    fi

    echo ""
    print_info "Configuring OTP Slot ${SLOT} with touch requirement..."

    # Run ykman otp chalresp with --generate and --touch flags
    if ykman otp chalresp --generate --touch --force "$SLOT"; then
        echo ""
        print_success "OTP Slot ${SLOT} configured successfully!"
        echo ""
        print_info "Configuration details:"
        echo "  • Type: Challenge-Response (HMAC-SHA1)"
        echo "  • Secret: Randomly generated (stored on YubiKey)"
        echo "  • Touch: REQUIRED for every verification"
        echo ""
        print_success "Your YubiKey is now configured for secure tap verification!"
        echo ""
        print_info "Test the configuration:"
        echo "  \$TOMB_DIR/scripts/yubikey-verify.sh \"test operation\""
        echo ""
    else
        echo ""
        print_error "Configuration failed!"
        print_info "Check the error message above and try again"
        exit 1
    fi

    # Show final status
    print_header "Final OTP Status"
    ykman otp info

    echo ""

    # Offer to test verification immediately
    read -p "Test YubiKey tap verification now? (yes/no): " test_confirm

    if [ "$test_confirm" = "yes" ]; then
        echo ""
        print_info "Testing tap verification..."
        echo ""

        # Find the verification script
        TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
        VERIFY_SCRIPT="${TOMB_DIR}/scripts/yubikey-verify.sh"

        if [ -x "$VERIFY_SCRIPT" ]; then
            if "$VERIFY_SCRIPT" "OTP-configuration-test"; then
                echo ""
                print_success "Tap verification test PASSED!"
                echo ""
                print_info "Your YubiKey is fully configured and working"
            else
                echo ""
                print_error "Tap verification test FAILED"
                print_warning "Check the error above and try reconfiguring"
            fi
        else
            print_warning "Verification script not found at: $VERIFY_SCRIPT"
            print_info "Manual test: \$TOMB_DIR/scripts/yubikey-verify.sh \"test\""
        fi
    else
        print_info "Skipped verification test"
    fi

    echo ""
    print_info "Next steps:"
    echo "  • Use normally: git push (will require tap)"
    echo "  • Check status: $(basename "$0") status"
    if [ -n "${TOMB_DIR:-}" ]; then
        echo "  • Manual test: $TOMB_DIR/scripts/yubikey-verify.sh \"test\""
    fi
    echo "  • Backup YubiKey: Configure it the same way"
    echo ""
}

cmd_delete() {
    print_header "Delete YubiKey OTP Slot ${SLOT} Configuration"

    check_prerequisites

    # Check if slot is configured
    if ykman otp info 2>/dev/null | grep -q "Slot ${SLOT}: empty"; then
        print_info "Slot ${SLOT} is already empty (nothing to delete)"
        exit 0
    fi

    print_warning "This will DELETE the challenge-response credential from Slot ${SLOT}"
    echo ""
    echo "Impact:"
    echo "  • YubiKey tap verification will no longer work"
    echo "  • Git enforcement will fall back to insecure presence check"
    echo "  • You'll see warnings about missing tap verification"
    echo ""
    print_warning "This is a DESTRUCTIVE operation!"
    echo ""

    read -p "Are you sure you want to delete Slot ${SLOT}? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "Deletion cancelled"
        exit 0
    fi

    echo ""
    print_info "Deleting OTP Slot ${SLOT}..."

    if ykman otp delete --force "$SLOT"; then
        echo ""
        print_success "OTP Slot ${SLOT} deleted successfully"
        echo ""
        print_info "Current status:"
        ykman otp info
        echo ""
        print_warning "YubiKey tap verification is now disabled"
        print_info "To re-enable: $(basename "$0") configure"
        echo ""
    else
        echo ""
        print_error "Deletion failed!"
        exit 1
    fi
}

# Main command router
main() {
    local command="${1:-status}"

    case "$command" in
        configure|config|setup)
            cmd_configure
            ;;
        delete|remove|clear)
            cmd_delete
            ;;
        status|info)
            cmd_status
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
