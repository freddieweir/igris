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
AUDIO_CONFIG="${TOMB_DIR}/configs/audio-alerts.yml"

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

    # Mask serial in logs unless debug mode
    if [ "${TOMB_DEBUG:-false}" = "true" ]; then
        echo "${timestamp} [${status}] ${OPERATION} - ${method} - Serial: ${serial}" >> "$LOG_FILE"
    else
        local masked_serial="${serial}"
        if [ "$serial" != "unknown" ] && [ "$serial" != "n/a" ]; then
            masked_serial="******${serial: -2}"
        fi
        echo "${timestamp} [${status}] ${OPERATION} - ${method} - Serial: ${masked_serial}" >> "$LOG_FILE"
    fi
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

# Play audio alert for YubiKey tap request
play_audio_alert() {
    # Check if audio is enabled in audio config
    if [ ! -f "$AUDIO_CONFIG" ]; then
        # Fallback to old config method if audio-alerts.yml doesn't exist
        local audio_enabled=$(grep -A 3 "^audio:" "$CONFIG_FILE" 2>/dev/null | grep "enabled:" | awk '{print $2}')
        if [ "$audio_enabled" != "true" ]; then
            return 0
        fi
        local custom_sound=$(grep -A 3 "^audio:" "$CONFIG_FILE" 2>/dev/null | grep "custom_sound_path:" | awk '{print $2}')
        if [[ ! "$custom_sound" =~ ^[/~] ]]; then
            custom_sound="${TOMB_DIR}/${custom_sound}"
        fi
        custom_sound="${custom_sound/#\~/$HOME}"
        if [ -f "$custom_sound" ]; then
            afplay "$custom_sound" &>/dev/null &
        else
            afplay "/System/Library/Sounds/Tink.aiff" &>/dev/null &
        fi
        return 0
    fi

    # Check if global audio is enabled
    local audio_enabled=$(grep "enabled:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
    if [ "$audio_enabled" != "true" ]; then
        return 0
    fi

    # Parse operation to find command-specific audio
    local cmd_type=""
    local cmd_action=""

    # Detect git vs gh operations
    if [[ "$OPERATION" =~ ^git ]]; then
        cmd_type="git"
        # Extract action (push, pull, fetch, etc.)
        if [[ "$OPERATION" =~ push ]]; then
            cmd_action="push"
        elif [[ "$OPERATION" =~ pull ]]; then
            cmd_action="pull"
        elif [[ "$OPERATION" =~ fetch ]]; then
            cmd_action="fetch"
        elif [[ "$OPERATION" =~ clone ]]; then
            cmd_action="clone"
        elif [[ "$OPERATION" =~ "remote add" ]]; then
            cmd_action="remote_add"
        elif [[ "$OPERATION" =~ "remote update" ]]; then
            cmd_action="remote_update"
        elif [[ "$OPERATION" =~ "submodule update" ]]; then
            cmd_action="submodule_update"
        fi
    elif [[ "$OPERATION" =~ ^gh ]]; then
        cmd_type="gh"
        # Extract gh action
        if [[ "$OPERATION" =~ "pr create" ]]; then
            cmd_action="pr_create"
        elif [[ "$OPERATION" =~ "pr merge" ]]; then
            cmd_action="pr_merge"
        elif [[ "$OPERATION" =~ "release create" ]]; then
            cmd_action="release_create"
        elif [[ "$OPERATION" =~ "repo clone" ]]; then
            cmd_action="repo_clone"
        elif [[ "$OPERATION" =~ "workflow run" ]]; then
            cmd_action="workflow_run"
        fi
    fi

    # Check if modular audio is enabled
    local use_modular=$(grep "use_modular_audio:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')

    if [ "$use_modular" = "true" ] && [ -n "$cmd_type" ] && [ -n "$cmd_action" ]; then
        # MODULAR MODE: Play prefix + action
        local pause_duration=$(grep "pause_between_clips:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
        pause_duration="${pause_duration:-0.0}"

        # Get operation category (read, write, security) and modular action audio
        local category=$(awk -v type="$cmd_type" -v action="$cmd_action" '
            $0 ~ "^" type ":" {in_section=1; next}
            in_section && $0 ~ "^[a-z]+:" {in_section=0}
            in_section && $1 == action ":" {in_action=1; next}
            in_action && /category:/ {gsub(/#.*/, ""); print $2; exit}
        ' "$AUDIO_CONFIG")

        local action_file=$(awk -v type="$cmd_type" -v action="$cmd_action" '
            $0 ~ "^" type ":" {in_section=1; next}
            in_section && $0 ~ "^[a-z]+:" {in_section=0}
            in_section && $1 == action ":" {in_action=1; next}
            in_action && /modular_audio:/ {print $2; exit}
        ' "$AUDIO_CONFIG")

        # Select prefix based on category
        local prefix_file=""
        case "$category" in
            write)
                prefix_file=$(grep "prefix_sound_write:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
                ;;
            read)
                prefix_file=$(grep "prefix_sound_read:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
                ;;
            security)
                prefix_file=$(grep "prefix_sound_security:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
                ;;
            *)
                prefix_file=$(grep "prefix_sound_default:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
                ;;
        esac

        # Resolve paths
        if [[ ! "$prefix_file" =~ ^[/~] ]]; then
            prefix_file="${TOMB_DIR}/${prefix_file}"
        fi
        prefix_file="${prefix_file/#\~/$HOME}"

        if [[ ! "$action_file" =~ ^[/~] ]]; then
            action_file="${TOMB_DIR}/${action_file}"
        fi
        action_file="${action_file/#\~/$HOME}"

        # Play prefix, pause, then action (in background)
        if [ -f "$prefix_file" ] && [ -f "$action_file" ]; then
            (
                afplay "$prefix_file" 2>/dev/null
                [ "$pause_duration" != "0.0" ] && sleep "$pause_duration"
                afplay "$action_file" 2>/dev/null
            ) &
            return 0
        fi
        # If modular files missing, fall through to legacy mode
    fi

    # LEGACY MODE: Play full phrase audio file
    local audio_file=""
    if [ -n "$cmd_type" ] && [ -n "$cmd_action" ]; then
        # Look for command-specific mapping in audio config
        audio_file=$(awk -v type="$cmd_type" -v action="$cmd_action" '
            $0 ~ "^" type ":" {in_section=1; next}
            in_section && $0 ~ "^[a-z]+:" {in_section=0}
            in_section && $1 == action ":" {in_action=1; next}
            in_action && /audio:/ {print $2; exit}
        ' "$AUDIO_CONFIG")
    fi

    # Get fallback sound if no specific mapping found
    if [ -z "$audio_file" ] || [ ! -f "${TOMB_DIR}/${audio_file}" ]; then
        audio_file=$(grep "fallback_sound:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
        if [ -z "$audio_file" ]; then
            audio_file="assets/audio/AlbedoYubikeyTapRequired.wav"
        fi
    fi

    # Resolve path (relative to TOMB_DIR)
    if [[ ! "$audio_file" =~ ^[/~] ]]; then
        audio_file="${TOMB_DIR}/${audio_file}"
    fi
    audio_file="${audio_file/#\~/$HOME}"

    # Play audio file or fallback to system sound
    if [ -f "$audio_file" ]; then
        afplay "$audio_file" &>/dev/null &
    else
        local fallback_system=$(grep "fallback_system_sound:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
        fallback_system="${fallback_system:-Tink}"
        afplay "/System/Library/Sounds/${fallback_system}.aiff" &>/dev/null &
    fi
}

# Check if enforcement is enabled
check_enforcement_enabled() {
    if [ "${TOMB_YUBIKEY_ENABLED:-true}" = "false" ]; then
        # Play bypass alert sound if enabled
        play_bypass_alert

        print_warning "YubiKey enforcement is disabled (TOMB_YUBIKEY_ENABLED=false)"
        log_verification "BYPASSED" "enforcement_disabled" "n/a"
        return 1
    fi
    return 0
}

# Play audio alert for bypass detection
play_bypass_alert() {
    # Check if bypass alerting is enabled
    if [ ! -f "$AUDIO_CONFIG" ]; then
        return 0
    fi

    local bypass_enabled=$(grep "bypass_alert_enabled:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
    if [ "$bypass_enabled" != "true" ]; then
        return 0
    fi

    # Get bypass alert sound path
    local bypass_sound=$(grep "bypass_alert_sound:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')

    # Resolve path (relative to TOMB_DIR)
    if [[ ! "$bypass_sound" =~ ^[/~] ]]; then
        bypass_sound="${TOMB_DIR}/${bypass_sound}"
    fi
    bypass_sound="${bypass_sound/#\~/$HOME}"

    # Play bypass alert or fallback to system Basso (warning sound)
    if [ -f "$bypass_sound" ]; then
        afplay "$bypass_sound" &>/dev/null &
    else
        # Use Basso (macOS warning sound) as fallback for bypass detection
        afplay "/System/Library/Sounds/Basso.aiff" &>/dev/null &
    fi
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

    # Play audio alert to grab attention
    play_audio_alert

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

# REMOVED: Legacy FIDO2 presence check
# This was insecure (no tap required) and has been removed
# YubiKey verification now requires OTP configuration

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

# REMOVED: Simple presence check
# This was insecure (no verification) and has been removed
# YubiKey verification now requires OTP configuration

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

    # Mask serial number unless debug mode enabled
    if [ "${TOMB_DEBUG:-false}" = "true" ]; then
        print_success "YubiKey detected: Serial ${YUBIKEY_SERIAL}"
    else
        print_success "YubiKey detected: Serial ******${YUBIKEY_SERIAL: -2}"
    fi

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
