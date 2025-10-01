#!/bin/bash

# GitHub CLI YubiKey Wrapper
# Intercepts gh commands and requires YubiKey verification for state-changing operations
# Part of tomb-of-nazarick security enforcement system

set -euo pipefail

# Get the actual gh binary (not this wrapper)
GH_BINARY="/usr/local/bin/gh"
TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERIFY_SCRIPT="${TOMB_DIR}/scripts/yubikey-verify.sh"

# Check if this is a state-changing operation
requires_verification() {
    local resource="$1"
    local action="${2:-}"

    case "$resource" in
        pr)
            # PR operations that modify state
            case "$action" in
                create|merge|close|reopen|edit|ready|review)
                    return 0
                    ;;
            esac
            ;;
        issue)
            # Issue operations that modify state
            case "$action" in
                create|close|reopen|edit|delete|transfer)
                    return 0
                    ;;
            esac
            ;;
        release)
            # All release operations modify state
            case "$action" in
                create|delete|edit|upload)
                    return 0
                    ;;
            esac
            ;;
        repo)
            # Repo operations that modify state
            case "$action" in
                create|delete|clone|fork|archive|rename)
                    return 0
                    ;;
            esac
            ;;
        workflow)
            # Running workflows modifies state
            case "$action" in
                run|enable|disable)
                    return 0
                    ;;
            esac
            ;;
        secret)
            # All secret operations are sensitive
            case "$action" in
                set|delete|remove)
                    return 0
                    ;;
            esac
            ;;
        auth)
            # Authentication state changes
            case "$action" in
                login|logout|refresh|setup-git)
                    return 0
                    ;;
            esac
            ;;
    esac

    return 1
}

# Main wrapper logic
main() {
    # If no arguments, pass through
    if [ $# -eq 0 ]; then
        exec "$GH_BINARY"
    fi

    local gh_resource="$1"
    local gh_action="${2:-}"

    # Check if this requires verification
    if requires_verification "$gh_resource" "$gh_action"; then
        # Verify YubiKey before proceeding
        if [ -x "$VERIFY_SCRIPT" ]; then
            if ! "$VERIFY_SCRIPT" "gh $*"; then
                echo "❌ YubiKey verification failed. Operation aborted." >&2
                exit 1
            fi
        else
            echo "⚠️  Warning: YubiKey verification script not found at: $VERIFY_SCRIPT" >&2
            echo "⚠️  Proceeding without verification - this is a security risk!" >&2
        fi
    fi

    # Execute the actual gh command
    exec "$GH_BINARY" "$@"
}

main "$@"
