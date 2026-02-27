#!/bin/bash

# Backup Password Verification Script
# Part of Igris hardware enforcement system
# Verifies YubiKey Slot 2 static password as fallback when Slot 1 HMAC fails
# Creates a 5-minute session on success to avoid re-prompting

set -euo pipefail

# Configuration
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HASH_FILE="${HOME}/.config/igris/backup-auth.hash"
SESSION_FILE="${HOME}/.config/igris/session-cache"
SESSION_DURATION="${IGRIS_SESSION_MINUTES:-5}"  # Minutes
SESSION_DURATION_SECS=$((SESSION_DURATION * 60))
LOG_FILE="${HOME}/.tomb-yubikey-verifications.log"
AUDIO_CONFIG="${TOMB_DIR}/configs/audio-alerts.yml"
TIMEOUT_SECONDS="${YUBIKEY_TIMEOUT:-30}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Operation context (passed by orchestrator)
OPERATION="${1:-unknown}"

print_info()    { echo -e "${BLUE}🔑${NC} $1" >&2; }
print_success() { echo -e "${GREEN}✅${NC} $1" >&2; }
print_error()   { echo -e "${RED}❌${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}⚠️${NC} $1" >&2; }

# Logging
log_verification() {
    local status="$1"
    local method="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    echo "${timestamp} [${status}] ${OPERATION} - ${method} - Serial: backup-password" >> "$LOG_FILE"
}

# ============================================================================
# SESSION MANAGEMENT
# ============================================================================
# Session tokens bind to: parent PID + TTY + operation + expiry
# This prevents session hijacking across terminals

generate_session_token() {
    local parent_pid="$1"
    local tty_name="$2"
    local expiry="$3"
    printf '%s' "${parent_pid}|${tty_name}|${OPERATION}|${expiry}" | shasum -a 256 | awk '{print $1}'
}

check_session() {
    if [ ! -f "$SESSION_FILE" ]; then
        return 1
    fi

    # Read session data
    local session_data
    session_data=$(cat "$SESSION_FILE" 2>/dev/null) || return 1

    local stored_token=$(echo "$session_data" | head -1)
    local stored_expiry=$(echo "$session_data" | sed -n '2p')
    local stored_operation=$(echo "$session_data" | sed -n '3p')
    local stored_parent_pid=$(echo "$session_data" | sed -n '4p')
    local stored_tty=$(echo "$session_data" | sed -n '5p')

    # Validate expiry
    if [ -z "$stored_expiry" ] || ! [[ "$stored_expiry" =~ ^[0-9]+$ ]]; then
        rm -f "$SESSION_FILE"
        return 1
    fi

    local current_time=$(date +%s)
    if [ "$current_time" -ge "$stored_expiry" ]; then
        rm -f "$SESSION_FILE"
        return 1  # Session expired
    fi

    local current_tty
    current_tty=$(tty 2>/dev/null || echo "notty")
    if [ "$stored_parent_pid" != "$PPID" ] || [ "$stored_tty" != "$current_tty" ] || [ "$stored_operation" != "$OPERATION" ]; then
        return 1
    fi

    local expected_token
    expected_token=$(generate_session_token "$stored_parent_pid" "$stored_tty" "$stored_expiry")
    if [ -z "$stored_token" ] || [ "$stored_token" != "$expected_token" ]; then
        rm -f "$SESSION_FILE"
        return 1
    fi

    # Session is valid — calculate remaining time
    local remaining=$(( (stored_expiry - current_time) / 60 ))
    local remaining_secs=$(( (stored_expiry - current_time) % 60 ))
    print_success "Active session found (${remaining}m ${remaining_secs}s remaining)"
    log_verification "SUCCESS" "BACKUP-SESSION"
    return 0
}

create_session() {
    local expiry=$(( $(date +%s) + SESSION_DURATION_SECS ))
    local parent_pid="$PPID"
    local tty_name
    tty_name=$(tty 2>/dev/null || echo "notty")
    local token
    token=$(generate_session_token "$parent_pid" "$tty_name" "$expiry")

    mkdir -p "$(dirname "$SESSION_FILE")"
    cat > "$SESSION_FILE" <<EOF
${token}
${expiry}
${OPERATION}
${parent_pid}
${tty_name}
EOF
    chmod 600 "$SESSION_FILE"
    print_info "Session created (${SESSION_DURATION} minute window)"
}

# ============================================================================
# PASSWORD VERIFICATION
# ============================================================================

verify_password_hash() {
    local password="$1"
    local stored_hash
    stored_hash=$(cat "$HASH_FILE")

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

# Play audio alert for backup password prompt
play_backup_audio() {
    if [ ! -f "$AUDIO_CONFIG" ]; then
        afplay "/System/Library/Sounds/Tink.aiff" &>/dev/null &
        return 0
    fi

    local audio_enabled=$(grep "enabled:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
    if [ "$audio_enabled" != "true" ]; then
        return 0
    fi

    # Use the security prefix sound for backup password prompts
    local prefix_file=$(grep "prefix_sound_security:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
    if [ -n "$prefix_file" ]; then
        if [[ ! "$prefix_file" =~ ^[/~] ]]; then
            prefix_file="${TOMB_DIR}/${prefix_file}"
        fi
        prefix_file="${prefix_file/#\~/$HOME}"
        if [ -f "$prefix_file" ]; then
            afplay "$prefix_file" &>/dev/null &
            return 0
        fi
    fi

    # Fallback to system sound
    afplay "/System/Library/Sounds/Tink.aiff" &>/dev/null &
}

do_verify() {
    print_info "Backup password verification for: ${OPERATION}"

    # Check if backup password is configured
    if [ ! -f "$HASH_FILE" ]; then
        print_error "Backup password not configured"
        print_info "Run: ${TOMB_DIR}/scripts/backup-password-setup.sh setup"
        log_verification "FAILURE" "BACKUP-NOT-CONFIGURED"
        return 1
    fi

    # Check permissions
    local perms=$(stat -f "%Lp" "$HASH_FILE" 2>/dev/null || stat -c "%a" "$HASH_FILE" 2>/dev/null)
    if [ "$perms" != "600" ]; then
        print_warning "Hash file permissions are $perms (should be 600). Fixing..."
        chmod 600 "$HASH_FILE"
    fi

    # Check for active session first
    if check_session; then
        return 0
    fi

    # Play audio to grab attention
    play_backup_audio

    echo "" >&2
    print_info "👆 LONG-PRESS YOUR YUBIKEY to enter backup password"
    print_info "   (password is hidden — nothing will appear on screen)"
    echo "" >&2

    # Read password with hidden input
    local password=""
    local attempts=0
    local max_attempts=3

    while [ $attempts -lt $max_attempts ]; do
        attempts=$((attempts + 1))
        echo -n "  🔐 Backup password [${attempts}/${max_attempts}]: " >&2
        read -s -t "$TIMEOUT_SECONDS" password || true
        echo "" >&2

        if [ -z "$password" ]; then
            if [ $attempts -lt $max_attempts ]; then
                print_warning "Empty input. Try again (long-press YubiKey)."
                continue
            else
                print_error "Timeout or empty input after ${max_attempts} attempts"
                log_verification "TIMEOUT" "BACKUP-PASSWORD"
                return 1
            fi
        fi

        # Verify against stored hash
        if verify_password_hash "$password"; then
            password=""  # Clear from memory
            print_success "Backup password verified!"
            log_verification "SUCCESS" "BACKUP-PASSWORD"

            # Create session
            create_session
            return 0
        else
            password=""  # Clear from memory
            if [ $attempts -lt $max_attempts ]; then
                print_error "Incorrect password. ${max_attempts - attempts} attempt(s) remaining."
            fi
        fi
    done

    print_error "Backup password verification failed after ${max_attempts} attempts"
    log_verification "FAILURE" "BACKUP-PASSWORD"
    return 1
}

# Main
do_verify
