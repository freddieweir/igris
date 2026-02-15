#!/bin/bash

# Docker Hardware Verification Wrapper
# Intercepts docker commands and requires YubiKey verification based on policy
# Part of Igris security enforcement system

set -euo pipefail

# Get the actual Docker binary (not this wrapper)
DOCKER_BINARY="${IGRIS_DOCKER_BINARY:-}"
if [ -z "$DOCKER_BINARY" ]; then
    # Search PATH for the real docker binary, skipping shell functions
    DOCKER_BINARY=$(command -v docker 2>/dev/null || true)
    if [ -z "$DOCKER_BINARY" ]; then
        echo "❌ Docker binary not found" >&2
        exit 1
    fi
fi

TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERIFY_SCRIPT="${TOMB_DIR}/scripts/hardware-verify.sh"

# VM environment detection — pass through without verification
if [[ "$(whoami)" == *vm ]]; then
    exec "$DOCKER_BINARY" "$@"
fi

# Enforcement toggle — pass through if disabled
if [ "${IGRIS_DOCKER_ENABLED:-true}" = "false" ]; then
    exec "$DOCKER_BINARY" "$@"
fi

# Master enforcement toggle
if [ "${TOMB_YUBIKEY_ENABLED:-true}" = "false" ]; then
    exec "$DOCKER_BINARY" "$@"
fi

# If no arguments, pass through
if [ $# -eq 0 ]; then
    exec "$DOCKER_BINARY"
fi

# ============================================================================
# FAST PATH: Regex pre-check for obvious auto-approve commands
# Avoids Python startup latency on read-only operations
# ============================================================================

# Skip global flags to find the actual command
args=("$@")
idx=0
while [ $idx -lt ${#args[@]} ] && [[ "${args[$idx]}" == -* ]]; do
    # Flags that take a value
    case "${args[$idx]}" in
        -H|--host|--context|--config|--log-level|-l)
            idx=$((idx + 2))
            ;;
        *)
            idx=$((idx + 1))
            ;;
    esac
done

first_cmd="${args[$idx]:-}"
second_cmd="${args[$((idx + 1))]:-}"

# Auto-approve patterns (no YubiKey needed)
case "$first_cmd" in
    ps|logs|images|info|version|inspect|events|search|stats|top|diff|port|wait|history)
        exec "$DOCKER_BINARY" "$@"
        ;;
    container)
        case "$second_cmd" in
            ls|list|logs|inspect|top|stats|diff|port|wait)
                exec "$DOCKER_BINARY" "$@"
                ;;
        esac
        ;;
    image)
        case "$second_cmd" in
            ls|list|inspect|history)
                exec "$DOCKER_BINARY" "$@"
                ;;
        esac
        ;;
    network|volume)
        case "$second_cmd" in
            ls|list|inspect)
                exec "$DOCKER_BINARY" "$@"
                ;;
        esac
        ;;
    compose)
        case "$second_cmd" in
            ps|logs|config|ls|list)
                exec "$DOCKER_BINARY" "$@"
                ;;
        esac
        ;;
esac

# ============================================================================
# POLICY ENGINE: Classify remaining commands via Python
# ============================================================================

# Build Python command to classify
classification=$(python3 -c "
import sys
sys.path.insert(0, '${TOMB_DIR}/src')
from igris.docker.policy import classify_docker_command, PolicyConfig, AuthLevel
from pathlib import Path

policy_path = Path.home() / '.config' / 'igris' / 'policy.yaml'
policy = PolicyConfig.load(policy_path)
args = sys.argv[1:]
operation, level = classify_docker_command(args, policy)
print(f'{operation}|{level.value}')
" "$@" 2>/dev/null) || true

if [ -z "$classification" ]; then
    # Python classification failed — default to single_tap (safe)
    classification="unknown|single_tap"
fi

operation="${classification%%|*}"
auth_level="${classification##*|}"

# ============================================================================
# ENFORCEMENT
# ============================================================================

audit_entry() {
    local outcome="$1"
    python3 -c "
import sys
sys.path.insert(0, '${TOMB_DIR}/src')
from igris.docker.audit import log_entry
log_entry(
    operation='${operation}',
    auth_level='${auth_level}',
    outcome='${outcome}',
    raw_command='docker $*',
)
" 2>/dev/null || true
}

case "$auth_level" in
    auto_approve)
        audit_entry "approved"
        exec "$DOCKER_BINARY" "$@"
        ;;

    single_tap)
        if [ -x "$VERIFY_SCRIPT" ]; then
            if ! "$VERIFY_SCRIPT" "docker ${operation}"; then
                audit_entry "denied"
                echo "❌ Hardware verification failed. Docker operation aborted." >&2
                exit 1
            fi
        else
            echo "⚠️  Warning: Hardware verification script not found at: $VERIFY_SCRIPT" >&2
            echo "⚠️  Proceeding without verification — this is a security risk!" >&2
        fi
        audit_entry "approved"
        exec "$DOCKER_BINARY" "$@"
        ;;

    dual_tap)
        echo "🔒 Dual-tap required for: docker ${operation}" >&2
        if [ -x "$VERIFY_SCRIPT" ]; then
            # First tap (can use cache)
            echo "👆 First YubiKey tap..." >&2
            if ! "$VERIFY_SCRIPT" "docker ${operation} [tap 1/2]"; then
                audit_entry "denied"
                echo "❌ First tap failed. Docker operation aborted." >&2
                exit 1
            fi

            # Second tap (cache disabled — forces fresh verification)
            echo "" >&2
            echo "👆 Second YubiKey tap required (confirmation)..." >&2
            sleep 1  # Brief pause between taps
            if ! TOMB_VERIFICATION_CACHE_ENABLED=false "$VERIFY_SCRIPT" "docker ${operation} [tap 2/2]"; then
                audit_entry "denied"
                echo "❌ Second tap failed. Docker operation aborted." >&2
                exit 1
            fi
        else
            echo "⚠️  Warning: Hardware verification script not found at: $VERIFY_SCRIPT" >&2
            echo "⚠️  Proceeding without verification — this is a security risk!" >&2
        fi
        audit_entry "approved"
        exec "$DOCKER_BINARY" "$@"
        ;;

    *)
        # Unknown auth level — default to single_tap
        if [ -x "$VERIFY_SCRIPT" ]; then
            if ! "$VERIFY_SCRIPT" "docker ${operation}"; then
                audit_entry "denied"
                echo "❌ Hardware verification failed. Docker operation aborted." >&2
                exit 1
            fi
        fi
        audit_entry "approved"
        exec "$DOCKER_BINARY" "$@"
        ;;
esac
