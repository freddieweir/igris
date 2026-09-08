#!/bin/bash

# Backup Password Setup Script
# Part of Igris hardware enforcement system
# Stores a PBKDF2-HMAC-SHA256 hash of the YubiKey Slot 2 static password for fallback auth
#
# Usage:
#   ./scripts/backup-password-setup.sh setup    # Initial setup (long-press YubiKey)
#   ./scripts/backup-password-setup.sh verify   # Test that it works
#   ./scripts/backup-password-setup.sh status    # Check if configured
#   ./scripts/backup-password-setup.sh remove    # Remove stored hash

set -euo pipefail

# Configuration
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HASH_DIR="${HOME}/.config/igris"
HASH_FILE="${HASH_DIR}/backup-auth.hash"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}ℹ️${NC} $1" >&2; }
print_success() { echo -e "${GREEN}✅${NC} $1" >&2; }
print_error()   { echo -e "${RED}❌${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}⚠️${NC} $1" >&2; }
print_header()  { echo -e "${CYAN}🔐${NC} $1" >&2; }

# Hash with Python's standard-library PBKDF2-HMAC-SHA256 implementation
hash_password() {
    local password="$1"
    printf '%s' "$password" | python3 -c '
import base64, hashlib, os, sys
salt = os.urandom(32)
password = sys.stdin.buffer.read()
dk = hashlib.pbkdf2_hmac("sha256", password, salt, 100000)
print(base64.b64encode(salt).decode() + ":" + base64.b64encode(dk).decode())
' 2>/dev/null
}

verify_password() {
    local password="$1"
    local stored_hash="$2"
    local salt_b64=$(echo "$stored_hash" | cut -d: -f1)
    local hash_b64=$(echo "$stored_hash" | cut -d: -f2)

    printf '%s' "$password" | python3 -c '
import base64, hashlib, hmac, sys
salt = base64.b64decode(sys.argv[1])
stored = base64.b64decode(sys.argv[2])
password = sys.stdin.buffer.read()
dk = hashlib.pbkdf2_hmac("sha256", password, salt, 100000)
sys.exit(0 if hmac.compare_digest(dk, stored) else 1)
' "$salt_b64" "$hash_b64" 2>/dev/null
}

do_setup() {
    print_header "Igris Backup Password Setup"
    echo "" >&2

    if [ -f "$HASH_FILE" ]; then
        print_warning "Backup password hash already exists at: $HASH_FILE"
        echo -n "  Overwrite? [y/N]: " >&2
        read -r confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_info "Setup cancelled"
            exit 0
        fi
    fi

    echo "" >&2
    print_info "This will store a hash of your YubiKey Slot 2 static password."
    print_info "When prompted, LONG-PRESS your YubiKey to enter the static password."
    print_info "The password will be hidden — nothing will appear on screen."
    echo "" >&2

    # First entry
    echo -n "  👆 Long-press YubiKey now (password): " >&2
    read -s password1
    echo "" >&2

    if [ -z "$password1" ]; then
        print_error "Empty password. Aborting."
        exit 1
    fi

    # Confirm entry
    echo -n "  👆 Long-press YubiKey again (confirm): " >&2
    read -s password2
    echo "" >&2

    if [ "$password1" != "$password2" ]; then
        print_error "Passwords don't match. Try again."
        print_info "Make sure you're using the same YubiKey and same long-press duration."
        exit 1
    fi

    # Generate and store hash
    mkdir -p "$HASH_DIR"
    local hashed
    hashed=$(hash_password "$password1")

    if [ -z "$hashed" ]; then
        print_error "Failed to generate password hash"
        exit 1
    fi

    echo "$hashed" > "$HASH_FILE"
    chmod 600 "$HASH_FILE"

    print_success "Backup password hash stored at: $HASH_FILE"
    print_info "Permissions: $(ls -la "$HASH_FILE" | awk '{print $1}')"
    echo "" >&2
    print_info "You can now use long-press YubiKey as a fallback when Slot 1 HMAC fails."
    print_info "Session lasts 5 minutes after successful backup auth."

    # Clear password from memory
    password1=""
    password2=""
}

do_verify() {
    print_header "Testing Backup Password"
    echo "" >&2

    if [ ! -f "$HASH_FILE" ]; then
        print_error "No backup password configured. Run: $0 setup"
        exit 1
    fi

    local stored_hash
    stored_hash=$(cat "$HASH_FILE")

    echo -n "  👆 Long-press YubiKey (password): " >&2
    read -s test_password
    echo "" >&2

    if verify_password "$test_password" "$stored_hash"; then
        print_success "Backup password verified successfully!"
    else
        print_error "Backup password verification failed."
        print_info "If you reprogrammed Slot 2, run: $0 setup"
    fi

    test_password=""
}

do_status() {
    print_header "Backup Password Status"
    echo "" >&2

    if [ -f "$HASH_FILE" ]; then
        local perms=$(ls -la "$HASH_FILE" | awk '{print $1}')
        local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$HASH_FILE" 2>/dev/null || stat -c "%y" "$HASH_FILE" 2>/dev/null | cut -d. -f1)
        print_success "Configured"
        print_info "  Hash file: $HASH_FILE"
        print_info "  Permissions: $perms"
        print_info "  Last modified: $modified"

        # Check permissions are correct
        if [ "$perms" != "-rw-------" ]; then
            print_warning "  Permissions should be 600 (-rw-------). Run: chmod 600 $HASH_FILE"
        fi
    else
        print_warning "Not configured"
        print_info "  Run: $0 setup"
    fi
}

do_remove() {
    print_header "Remove Backup Password"
    echo "" >&2

    if [ ! -f "$HASH_FILE" ]; then
        print_info "No backup password hash found. Nothing to remove."
        exit 0
    fi

    echo -n "  Remove backup password hash? [y/N]: " >&2
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -f "$HASH_FILE"
        print_success "Backup password hash removed."
    else
        print_info "Cancelled."
    fi
}

# Main
case "${1:-help}" in
    setup)   do_setup ;;
    verify)  do_verify ;;
    status)  do_status ;;
    remove)  do_remove ;;
    *)
        echo "Usage: $0 {setup|verify|status|remove}" >&2
        echo "" >&2
        echo "  setup   - Store hash of YubiKey Slot 2 static password" >&2
        echo "  verify  - Test backup password verification" >&2
        echo "  status  - Check if backup password is configured" >&2
        echo "  remove  - Remove stored hash" >&2
        exit 1
        ;;
esac
