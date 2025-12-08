#!/bin/bash

# rm Hardware Verification Wrapper
# Intercepts rm commands and requires hardware verification for dangerous operations
# Part of Igris security enforcement system
#
# Protects against catastrophic rm commands like:
#   rm -rf ~/
#   rm -rf /
#   rm -rf /Users/*
#
# Only enforces on main machine - VM environments pass through

set -euo pipefail

# Get the actual rm binary (not this wrapper)
RM_BINARY="/bin/rm"
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERIFY_SCRIPT="${TOMB_DIR}/scripts/hardware-verify.sh"
LOG_FILE="${HOME}/.tomb-yubikey-verifications.log"

# Protected paths - operations targeting these require verification
# Note: ~ is checked both literally and expanded
PROTECTED_PATHS=(
    "/"
    "$HOME"
    "/Users"
    "/System"
    "/usr"
    "/opt"
    "/Applications"
    "/Library"
    "/bin"
    "/sbin"
    "/var"
    "/private"
)

# Environment detection (main machine vs VM)
detect_environment() {
    if [[ "$HOME" == /Users/fweir ]]; then
        echo "main"
    elif [[ "$HOME" == /Users/fweirvm ]] || [[ "${PWD:-}" == /Volumes/* ]]; then
        echo "vm"
    else
        echo "unknown"
    fi
}

# Check if arguments contain dangerous flag patterns
has_dangerous_flags() {
    local args="$*"

    # Dangerous combinations: recursive + force
    # -rf, -fr, -r -f, -f -r (in any order)
    [[ "$args" =~ -rf ]] || [[ "$args" =~ -fr ]] || \
    [[ "$args" =~ -r[[:space:]]+-f ]] || [[ "$args" =~ -f[[:space:]]+-r ]] || \
    [[ "$args" =~ -r.*-f ]] || [[ "$args" =~ -f.*-r ]]
}

# Check if arguments target protected paths
targets_protected_path() {
    local args="$*"

    # Check for literal tilde
    if [[ "$args" == *"~"* ]]; then
        return 0
    fi

    for path in "${PROTECTED_PATHS[@]}"; do
        # Exact match or starts with protected path
        if [[ "$args" == *"$path"* ]] || [[ "$args" == *"$path/"* ]]; then
            # Exclude legitimate subdirectories deep within protected areas
            # e.g., /Users/fweir/git/project is OK, /Users alone is not
            local safe_depth=0
            for arg in $args; do
                # Skip flags
                [[ "$arg" == -* ]] && continue

                # Count path depth
                local depth=$(echo "$arg" | tr '/' '\n' | wc -l)

                # If targeting root-level protected paths (depth <= 3), it's dangerous
                # /Users = 2, /Users/fweir = 3, /Users/fweir/git = 4 (OK)
                case "$path" in
                    "/"|"/Users"|"/System"|"/usr"|"/opt"|"/Applications"|"/Library"|"/bin"|"/sbin"|"/var"|"/private")
                        if [[ "$arg" == "$path" ]] || [[ "$arg" == "$path/" ]]; then
                            return 0  # Dangerous: targeting protected path directly
                        fi
                        ;;
                    "$HOME")
                        if [[ "$arg" == "$HOME" ]] || [[ "$arg" == "$HOME/" ]]; then
                            return 0  # Dangerous: targeting home directory
                        fi
                        ;;
                esac
            done
        fi
    done

    return 1  # Safe path
}

# Log dangerous operation attempt
log_operation() {
    local status="$1"
    local operation="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S+0000")

    echo "$timestamp [$status] $operation" >> "$LOG_FILE"
}

# Main wrapper logic
main() {
    # If no arguments, pass through
    if [ $# -eq 0 ]; then
        exec "$RM_BINARY"
    fi

    # Check if dangerous command protection is enabled
    if [[ "${TOMB_DANGEROUS_ENABLED:-true}" != "true" ]]; then
        exec "$RM_BINARY" "$@"
    fi

    # Environment detection - VM passes through
    local env
    env=$(detect_environment)

    if [[ "$env" != "main" ]]; then
        # VM environment - pass through without verification
        exec "$RM_BINARY" "$@"
    fi

    # Check if operation is dangerous (flags + protected path)
    if has_dangerous_flags "$@" && targets_protected_path "$@"; then
        echo "" >&2
        echo "============================================" >&2
        echo "DANGEROUS OPERATION DETECTED" >&2
        echo "============================================" >&2
        echo "Command: rm $*" >&2
        echo "" >&2
        echo "This operation requires YubiKey verification." >&2
        echo "Please tap your YubiKey when it blinks." >&2
        echo "============================================" >&2
        echo "" >&2

        # Dry run mode for testing
        if [[ "${TOMB_DRY_RUN:-false}" == "true" ]]; then
            echo "[DRY RUN] Would require YubiKey verification" >&2
            log_operation "DRY_RUN" "rm $*"
            exit 0
        fi

        # Verify hardware before proceeding
        if [ -x "$VERIFY_SCRIPT" ]; then
            if ! "$VERIFY_SCRIPT" "rm: dangerous delete"; then
                echo "" >&2
                echo "Operation blocked - YubiKey verification failed" >&2
                log_operation "BLOCKED" "rm $*"
                exit 1
            fi

            echo "" >&2
            echo "YubiKey verified - proceeding with rm" >&2
            log_operation "VERIFIED" "rm $*"
        else
            echo "Warning: Hardware verification script not found at: $VERIFY_SCRIPT" >&2
            echo "Proceeding without verification - this is a security risk!" >&2
            log_operation "NO_VERIFY_SCRIPT" "rm $*"
        fi
    fi

    # Safe operation or verification passed - execute
    exec "$RM_BINARY" "$@"
}

main "$@"
