#!/bin/bash

# Docker Protection Integration Tests
# Tests the Docker YubiKey wrapper with mock Docker binary
# Part of igris security enforcement system

set -euo pipefail

TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WRAPPER="${TOMB_DIR}/scripts/docker-yubikey-wrapper.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local desc="$1"
    local expected_exit="$2"
    shift 2

    local actual_exit=0
    "$@" >/dev/null 2>&1 || actual_exit=$?

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo -e "  ${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $desc (expected exit=$expected_exit, got=$actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Docker Protection Integration Tests ==="
echo ""

# Common env for tests
export TOMB_DIR
export IGRIS_DOCKER_BINARY=echo
export TOMB_YUBIKEY_ENABLED=true
export IGRIS_DOCKER_ENABLED=true

# --- Auto-approve tests (should pass through without YubiKey) ---
echo "Auto-approve (should pass through):"
check "docker ps" 0 "$WRAPPER" ps
check "docker logs container" 0 "$WRAPPER" logs mycontainer
check "docker images" 0 "$WRAPPER" images
check "docker info" 0 "$WRAPPER" info
check "docker version" 0 "$WRAPPER" version
check "docker inspect container" 0 "$WRAPPER" inspect mycontainer
check "docker compose ps" 0 "$WRAPPER" compose ps
check "docker compose logs" 0 "$WRAPPER" compose logs
check "docker stats" 0 "$WRAPPER" stats
check "docker top container" 0 "$WRAPPER" top mycontainer
check "docker container ls" 0 "$WRAPPER" container ls
check "docker image ls" 0 "$WRAPPER" image ls
check "docker network ls" 0 "$WRAPPER" network ls
check "docker volume ls" 0 "$WRAPPER" volume ls
echo ""

# --- Enforcement disabled tests ---
echo "Enforcement disabled (should pass through):"
IGRIS_DOCKER_ENABLED=false check "IGRIS_DOCKER_ENABLED=false bypasses exec" 0 "$WRAPPER" exec container bash
TOMB_YUBIKEY_ENABLED=false IGRIS_DOCKER_ENABLED=true check "TOMB_YUBIKEY_ENABLED=false bypasses exec" 0 "$WRAPPER" exec container bash

# Restore
export TOMB_YUBIKEY_ENABLED=true
export IGRIS_DOCKER_ENABLED=true
echo ""

# --- VM bypass tests ---
echo "VM bypass:"
if [[ "$(whoami)" == *vm ]]; then
    check "VM user passes through exec" 0 "$WRAPPER" exec container bash
    check "VM user passes through rm" 0 "$WRAPPER" rm container
    check "VM user passes through system prune" 0 "$WRAPPER" system prune
else
    echo -e "  ${YELLOW}SKIP${NC} Not running on VM (user=$(whoami))"
fi

echo ""

# --- Summary ---
echo "=== Results ==="
echo -e "  ${GREEN}Passed: $PASS${NC}"
if [ $FAIL -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAIL${NC}"
    exit 1
else
    echo -e "  Failed: $FAIL"
    echo ""
    echo "All tests passed!"
fi
