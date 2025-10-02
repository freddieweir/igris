#!/bin/bash

# Git Hardware Verification Wrapper
# Intercepts git commands and requires hardware verification for network operations
# Part of Igris security enforcement system

set -euo pipefail

# Get the actual git binary (not this wrapper)
GIT_BINARY="/usr/bin/git"
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERIFY_SCRIPT="${TOMB_DIR}/scripts/hardware-verify.sh"

# Network operations that require hardware verification
NETWORK_OPERATIONS=(
    "push"
    "pull"
    "fetch"
    "clone"
)

# Operations with subcommands that may require verification
COMPLEX_OPERATIONS=(
    "remote"
    "submodule"
)

# Check if this is a network operation
is_network_operation() {
    local cmd="$1"

    # Direct network operations
    for op in "${NETWORK_OPERATIONS[@]}"; do
        if [ "$cmd" = "$op" ]; then
            return 0
        fi
    done

    # Complex operations - check subcommands
    case "$cmd" in
        remote)
            # remote add, update may fetch
            if [[ "$*" =~ (add|update|set-url) ]]; then
                return 0
            fi
            ;;
        submodule)
            # submodule update --remote requires network
            if [[ "$*" =~ update.*--remote ]]; then
                return 0
            fi
            ;;
    esac

    return 1
}

# Main wrapper logic
main() {
    # If no arguments, pass through
    if [ $# -eq 0 ]; then
        exec "$GIT_BINARY"
    fi

    local git_command="$1"

    # Check if this is a network operation
    if is_network_operation "$git_command" "$@"; then
        # Verify hardware before proceeding
        if [ -x "$VERIFY_SCRIPT" ]; then
            if ! "$VERIFY_SCRIPT" "git $*"; then
                echo "❌ Hardware verification failed. Operation aborted." >&2
                exit 1
            fi
        else
            echo "⚠️  Warning: Hardware verification script not found at: $VERIFY_SCRIPT" >&2
            echo "⚠️  Proceeding without verification - this is a security risk!" >&2
        fi
    fi

    # Execute the actual git command
    exec "$GIT_BINARY" "$@"
}

main "$@"
