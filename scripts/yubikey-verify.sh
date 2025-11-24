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
AUDIO_CACHE_FILE="${HOME}/.tomb-audio-cache"

# Use Homebrew $YKMAN_BIN explicitly to avoid broken Python installations
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

# Check if audio should be deduplicated (time-based cache)
should_play_audio() {
    # Get deduplication window from config (default: 8 seconds)
    local dedup_window=$(grep "deduplication_window_seconds:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
    dedup_window="${dedup_window:-8}"

    # Check if deduplication is enabled
    local dedup_enabled=$(grep "deduplication_enabled:" "$AUDIO_CONFIG" 2>/dev/null | head -1 | sed 's/#.*//' | awk '{print $2}')
    if [ "$dedup_enabled" != "true" ]; then
        return 0  # Play audio (deduplication disabled)
    fi

    # Check cache file
    if [ ! -f "$AUDIO_CACHE_FILE" ]; then
        # No cache, play audio and create cache
        date +%s > "$AUDIO_CACHE_FILE"
        return 0
    fi

    # Read last audio timestamp
    local last_audio=$(cat "$AUDIO_CACHE_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_audio))

    # If within deduplication window, skip audio
    if [ "$time_diff" -lt "$dedup_window" ]; then
        return 1  # Skip audio (too recent)
    fi

    # Update cache with current time
    echo "$current_time" > "$AUDIO_CACHE_FILE"
    return 0  # Play audio
}

# Play audio alert for YubiKey tap request
play_audio_alert() {
    # Check deduplication before playing audio
    if ! should_play_audio; then
        print_info "🔇 Audio skipped (recent verification within deduplication window)"
        return 0
    fi

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

# Play state-based audio alert (completion, cached, errors)
play_state_audio() {
    local state_type="$1"  # completion, cached, timeout, no_yubikey, verification_failed, timing_violation

    if [ ! -f "$AUDIO_CONFIG" ]; then
        return 0
    fi

    # Parse state audio configuration from YAML
    # States section format:
    # states:
    #   completion:
    #     enabled: true
    #     sound: assets/audio/states/verification-complete.wav
    #     fallback_system_sound: Hero

    local config_section=""
    if [ "$state_type" = "completion" ] || [ "$state_type" = "cached" ]; then
        config_section="states.$state_type"
    else
        # Error states are nested under states.errors
        config_section="states.errors.$state_type"
    fi

    # Check if state audio is enabled (search for enabled: true under the state section)
    # We need to find the correct section and check its enabled flag
    local in_section=0
    local enabled="false"
    local sound_file=""
    local fallback_sound=""
    local use_completion_fallback="false"

    while IFS= read -r line; do
        # Detect if we're entering states section
        if [[ "$line" =~ ^states: ]]; then
            in_section=1
            continue
        fi

        # Exit states section if we hit another top-level section
        if [ $in_section -eq 1 ] && [[ "$line" =~ ^[a-z_]+: ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            break
        fi

        # Match state type subsection
        if [ $in_section -eq 1 ]; then
            if [ "$state_type" = "completion" ] && [[ "$line" =~ ^[[:space:]]+completion: ]]; then
                in_section=2
            elif [ "$state_type" = "cached" ] && [[ "$line" =~ ^[[:space:]]+cached: ]]; then
                in_section=2
            elif [[ "$line" =~ ^[[:space:]]+errors: ]]; then
                in_section=3
            elif [ $in_section -eq 3 ]; then
                if [ "$state_type" = "timeout" ] && [[ "$line" =~ ^[[:space:]]+timeout: ]]; then
                    in_section=4
                elif [ "$state_type" = "no_yubikey" ] && [[ "$line" =~ ^[[:space:]]+no_yubikey: ]]; then
                    in_section=4
                elif [ "$state_type" = "verification_failed" ] && [[ "$line" =~ ^[[:space:]]+verification_failed: ]]; then
                    in_section=4
                elif [ "$state_type" = "timing_violation" ] && [[ "$line" =~ ^[[:space:]]+timing_violation: ]]; then
                    in_section=4
                fi
            fi
        fi

        # Extract configuration values when in correct section
        if [ $in_section -eq 2 ] || [ $in_section -eq 4 ]; then
            if [[ "$line" =~ enabled:[[:space:]]*([a-z]+) ]]; then
                enabled="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ sound:[[:space:]]*(.+) ]]; then
                sound_file=$(echo "${BASH_REMATCH[1]}" | sed 's/#.*//' | xargs)
            elif [[ "$line" =~ fallback_system_sound:[[:space:]]*([A-Za-z]+) ]]; then
                fallback_sound=$(echo "${BASH_REMATCH[1]}" | sed 's/#.*//' | xargs)
            elif [[ "$line" =~ use_completion_fallback:[[:space:]]*([a-z]+) ]]; then
                use_completion_fallback="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$AUDIO_CONFIG"

    # If not enabled, return
    if [ "$enabled" != "true" ]; then
        return 0
    fi

    # Resolve sound file path (relative to TOMB_DIR)
    if [ -n "$sound_file" ]; then
        if [[ ! "$sound_file" =~ ^[/~] ]]; then
            sound_file="${TOMB_DIR}/${sound_file}"
        fi
        sound_file="${sound_file/#\~/$HOME}"
    fi

    # Play audio
    if [ -f "$sound_file" ]; then
        afplay "$sound_file" &>/dev/null &
    elif [ "$state_type" = "cached" ] && [ "$use_completion_fallback" = "true" ]; then
        # Try completion sound as fallback for cached
        local completion_sound="${TOMB_DIR}/assets/audio/states/verification-complete.wav"
        if [ -f "$completion_sound" ]; then
            afplay "$completion_sound" &>/dev/null &
        elif [ -n "$fallback_sound" ]; then
            afplay "/System/Library/Sounds/${fallback_sound}.aiff" &>/dev/null &
        fi
    elif [ -n "$fallback_sound" ]; then
        # Use system sound fallback
        afplay "/System/Library/Sounds/${fallback_sound}.aiff" &>/dev/null &
    fi
}

# Detect YubiKey presence
detect_yubikey() {
    # Uses global YKMAN_BIN variable set at script initialization
    if ! command -v "$YKMAN_BIN" &> /dev/null; then
        print_error "ykman not found. Install with: brew install ykman"
        return 1
    fi

    local yubikey_info
    if ! yubikey_info=$("$YKMAN_BIN" list 2>/dev/null); then
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

# Verify OTP slot 2 is configured with touch requirement
check_otp_touch_configured() {
    local otp_info
    if ! otp_info=$($YKMAN_BIN otp info 2>/dev/null); then
        return 1
    fi

    # Check if slot 2 has touch requirement configured
    # $YKMAN_BIN shows "configured" but doesn't explicitly show touch flag
    # We need to test with a challenge to verify touch behavior
    if echo "$otp_info" | grep -q "Slot 2: empty"; then
        return 1
    fi

    # Extract slot 2 info line
    local slot2_line=$(echo "$otp_info" | grep -A 1 "Slot 2:" | tail -1)

    # Check for touch indicators in the output
    # Note: $YKMAN_BIN doesn't always show touch flag explicitly
    # We'll do a timing check during actual verification
    return 0
}

# ============================================================================
# VERIFICATION CACHING FUNCTIONS (5-Second Window)
# ============================================================================
# These functions implement a short-lived verification cache to prevent
# double-tapping when both shell wrapper and git hook verify the same operation.
# Cache is valid for 5 seconds and includes operation context for security.

# Generate cryptographic hash for operation context
generate_verification_hash() {
    local repo_path="${PWD}"
    local operation="${OPERATION:-unknown}"
    local yubikey_serial="${YUBIKEY_SERIAL:-unknown}"

    # Get git remote URL if in a git repository (for context specificity)
    local remote_url="none"
    if git remote get-url origin &>/dev/null; then
        remote_url=$(git remote get-url origin 2>/dev/null || echo "none")
    fi

    # Create hash from: repo + operation + remote + serial
    # Different repos/operations won't reuse cache
    local context="${repo_path}|${operation}|${remote_url}|${yubikey_serial}"
    echo -n "$context" | shasum -a 256 | awk '{print $1}'
}

# Cleanup stale cache entries (older than cache window)
cleanup_verification_cache() {
    local cache_file="${1:-${HOME}/.tomb-verification-cache}"
    local cache_window="${2:-5}"  # Default 5 seconds

    if [ ! -f "$cache_file" ]; then
        return 0
    fi

    local current_time=$(date +%s)
    local temp_file="${cache_file}.tmp"

    # Filter out entries older than cache window
    while IFS='|' read -r timestamp hash operation serial; do
        local age=$((current_time - timestamp))
        if [ "$age" -lt "$cache_window" ]; then
            echo "${timestamp}|${hash}|${operation}|${serial}" >> "$temp_file"
        fi
    done < "$cache_file"

    # Replace cache file with cleaned version
    if [ -f "$temp_file" ]; then
        mv "$temp_file" "$cache_file"
        chmod 600 "$cache_file"  # Ensure user-only permissions
    else
        # No valid entries remain
        rm -f "$cache_file"
    fi
}

# Check if recent verification exists in cache
check_verification_cache() {
    # Read cache settings from config
    local cache_enabled=$(grep -A 10 "cache:" "$CONFIG_FILE" 2>/dev/null | grep "enabled:" | head -1 | sed 's/#.*//' | awk '{print $2}')
    if [ "$cache_enabled" != "true" ]; then
        return 1  # Cache disabled
    fi

    local cache_window=$(grep -A 10 "cache:" "$CONFIG_FILE" 2>/dev/null | grep "window_seconds:" | head -1 | sed 's/#.*//' | awk '{print $2}')
    cache_window="${cache_window:-5}"

    local cache_file=$(grep -A 10 "cache:" "$CONFIG_FILE" 2>/dev/null | grep "cache_file:" | head -1 | sed 's/#.*//' | awk '{print $2}')
    cache_file="${cache_file/#\~/$HOME}"
    cache_file="${cache_file:-${HOME}/.tomb-verification-cache}"

    # Cleanup stale entries first
    cleanup_verification_cache "$cache_file" "$cache_window"

    if [ ! -f "$cache_file" ]; then
        return 1  # No cache file exists
    fi

    # Generate hash for current operation
    local current_hash=$(generate_verification_hash)
    local current_time=$(date +%s)

    # Search for matching entry within time window
    while IFS='|' read -r timestamp hash operation serial; do
        local age=$((current_time - timestamp))

        # Check if entry matches current context and is within window
        if [ "$hash" = "$current_hash" ] && [ "$age" -lt "$cache_window" ]; then
            # Verify YubiKey serial matches (prevents key swap attacks)
            if [ "$serial" = "${YUBIKEY_SERIAL:-unknown}" ]; then
                print_success "Using cached verification (${age}s ago, ${cache_window}s window)"
                log_verification "SUCCESS" "CACHED" "$serial"
                return 0  # Cache hit
            fi
        fi
    done < "$cache_file"

    return 1  # No valid cache entry found
}

# Cache successful verification
cache_successful_verification() {
    # Read cache settings
    local cache_enabled=$(grep -A 10 "cache:" "$CONFIG_FILE" 2>/dev/null | grep "enabled:" | head -1 | sed 's/#.*//' | awk '{print $2}')
    if [ "$cache_enabled" != "true" ]; then
        return 0  # Cache disabled
    fi

    local cache_file=$(grep -A 10 "cache:" "$CONFIG_FILE" 2>/dev/null | grep "cache_file:" | head -1 | sed 's/#.*//' | awk '{print $2}')
    cache_file="${cache_file/#\~/$HOME}"
    cache_file="${cache_file:-${HOME}/.tomb-verification-cache}"

    # Generate verification hash
    local verification_hash=$(generate_verification_hash)
    local timestamp=$(date +%s)
    local serial="${YUBIKEY_SERIAL:-unknown}"

    # Append to cache file
    echo "${timestamp}|${verification_hash}|${OPERATION}|${serial}" >> "$cache_file"
    chmod 600 "$cache_file"  # Ensure user-only permissions

    print_info "Verification cached for 5 seconds"
}

# ============================================================================
# END VERIFICATION CACHING FUNCTIONS
# ============================================================================

# OTP Challenge-Response verification with REQUIRED physical touch
verify_otp_touch() {
    print_info "Verifying with OTP challenge-response (requires physical tap)..."

    # Check if OTP slot 2 is configured
    local otp_info
    if ! otp_info=$($YKMAN_BIN otp info 2>/dev/null); then
        print_warning "OTP not configured on this YubiKey"
        return 1
    fi

    # Check if slot 2 has a credential
    if echo "$otp_info" | grep -q "Slot 2: empty"; then
        print_warning "OTP Slot 2 is empty - needs configuration"
        print_info "Run: $YKMAN_BIN otp chalresp --generate --touch 2"
        return 1
    fi

    # SECURITY: Verify slot 2 is configured for challenge-response
    if ! echo "$otp_info" | grep -q "Slot 2:.*programmed"; then
        if ! echo "$otp_info" | grep -A 1 "Slot 2:" | grep -q "configured\|programmed\|HMAC-SHA1"; then
            print_warning "OTP Slot 2 not properly configured"
            print_info "Run: $YKMAN_BIN otp chalresp --generate --touch 2"
            return 1
        fi
    fi

    # Generate random challenge
    local challenge=$(openssl rand -hex 32)

    # Play audio alert to grab attention
    play_audio_alert

    print_info "👆 TAP YOUR YUBIKEY NOW to verify (timeout: ${TIMEOUT_SECONDS}s)"

    # Use $YKMAN_BIN otp calculate which works with configured slots
    # This will REQUIRE physical touch if the slot was configured with --touch
    local response
    local start_time=$(date +%s)
    local start_time_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')

    # Try the challenge-response
    if response=$(timeout "${TIMEOUT_SECONDS}s" $YKMAN_BIN otp calculate 2 "$challenge" 2>&1); then
        local end_time_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
        local elapsed=$(($(date +%s) - start_time))
        local elapsed_ms=$((end_time_ms - start_time_ms))

        # SECURITY CHECK: Verify response took long enough for human tap
        # Instant responses (< 800ms) indicate touch is NOT required
        # Human reaction time + YubiKey processing should be at least 800ms-1000ms
        if [ "$elapsed_ms" -lt 800 ]; then
            play_state_audio "timing_violation"
            print_error "⚠️  SECURITY VIOLATION: Response too fast (${elapsed_ms}ms)!"
            print_error "OTP Slot 2 is NOT configured to require physical touch"
            print_error "This allows auto-acceptance without hardware verification"
            echo "" >&2
            print_info "FIX REQUIRED:" >&2
            echo "  1. Reconfigure slot 2 WITH touch requirement:" >&2
            echo "     cd ${TOMB_DIR}" >&2
            echo "     ./scripts/yubikey-configure-otp.sh configure" >&2
            echo "  2. Verify touch is working:" >&2
            echo "     ./scripts/yubikey-git-setup.sh test" >&2
            log_verification "FAILURE" "NO-TOUCH-CONFIGURED" "$YUBIKEY_SERIAL"
            return 1
        fi

        # Response timing is acceptable - touch was likely required
        print_success "YubiKey tap verified! (${elapsed}s / ${elapsed_ms}ms)"
        log_verification "SUCCESS" "OTP-TOUCH" "$YUBIKEY_SERIAL"
        return 0
    else
        # Check if it was a timeout or other error
        if [[ "$response" =~ "timeout" ]] || [ $(($(date +%s) - start_time)) -ge $TIMEOUT_SECONDS ]; then
            play_state_audio "timeout"
            print_error "Timeout waiting for YubiKey tap"
            log_verification "TIMEOUT" "OTP-TOUCH" "$YUBIKEY_SERIAL"
        else
            play_state_audio "verification_failed"
            print_error "YubiKey verification failed: $response"
            log_verification "FAILURE" "OTP-TOUCH" "$YUBIKEY_SERIAL"
        fi
        return 1
    fi
}

# REMOVED: Legacy FIDO2 presence check
# This was insecure (no tap required) and has been removed
# YubiKey verification now requires OTP configuration

# OTP Challenge-Response verification (fallback - with timing check)
verify_otp() {
    print_info "Attempting OTP challenge-response verification..."

    # Check if OTP is configured
    local otp_info
    if ! otp_info=$($YKMAN_BIN otp info 2>/dev/null); then
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
    local start_time_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')

    if response=$(timeout "$TIMEOUT_SECONDS" $YKMAN_BIN otp chalresp 2 "$challenge" 2>/dev/null); then
        local end_time_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
        local elapsed_ms=$((end_time_ms - start_time_ms))

        # SECURITY CHECK: Same timing validation as verify_otp_touch
        if [ "$elapsed_ms" -lt 800 ]; then
            play_state_audio "timing_violation"
            print_error "⚠️  SECURITY VIOLATION: Response too fast (${elapsed_ms}ms)!"
            print_error "OTP Slot 2 is NOT configured to require physical touch"
            print_error "This allows auto-acceptance without hardware verification"
            echo "" >&2
            print_info "FIX REQUIRED:" >&2
            echo "  1. Reconfigure slot 2 WITH touch requirement:" >&2
            echo "     cd ${TOMB_DIR}" >&2
            echo "     ./scripts/yubikey-configure-otp.sh configure" >&2
            echo "  2. Verify touch is working:" >&2
            echo "     ./scripts/yubikey-git-setup.sh test" >&2
            log_verification "FAILURE" "NO-TOUCH-CONFIGURED-FALLBACK" "$YUBIKEY_SERIAL"
            return 1
        fi

        print_success "YubiKey verified via OTP challenge-response! (${elapsed_ms}ms)"
        print_warning "⚠️  Used OTP without guaranteed touch - consider configuring slot 2 with --touch"
        log_verification "SUCCESS" "OTP" "$YUBIKEY_SERIAL"
        return 0
    else
        play_state_audio "timeout"
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
        play_state_audio "no_yubikey"
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

    # Check verification cache (5-second window)
    if check_verification_cache; then
        # Cache hit - verification from recent tap
        print_success "✅ Verification successful (cached)! Proceeding with ${OPERATION}"
        play_state_audio "cached"
        exit 0
    fi

    # Cache miss - need fresh verification
    print_info "No recent verification in cache, requesting YubiKey tap..."

    # Try verification methods in priority order (most secure first)
    # 1. OTP with required physical touch (SECURE - REQUIRED)
    if verify_otp_touch; then
        cache_successful_verification
        print_success "✅ Verification successful! Proceeding with ${OPERATION}"
        play_state_audio "completion"
        exit 0
    fi

    # 2. OTP without guaranteed touch (LESS SECURE but acceptable)
    print_warning "OTP touch verification not available, trying OTP without touch..."
    if verify_otp; then
        cache_successful_verification
        print_warning "⚠️  Used OTP without guaranteed touch - consider configuring slot 2 with --touch"
        print_success "Verification successful! Proceeding with ${OPERATION}"
        play_state_audio "completion"
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
