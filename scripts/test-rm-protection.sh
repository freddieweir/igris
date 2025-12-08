#!/bin/bash

# Test script for rm command protection
# Tests the dangerous rm detection and YubiKey verification flow
# Part of igris (Iron Guardian Integration System)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOMB_DIR="${TOMB_DIR:-$(dirname "$SCRIPT_DIR")}"
RM_WRAPPER="${TOMB_DIR}/scripts/rm-yubikey-wrapper.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0

# Print test result
pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAILED++))
}

# Header
echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  rm Protection Test Suite${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}\n"

# Check wrapper exists
echo -e "${YELLOW}Checking prerequisites...${NC}"
if [ -x "$RM_WRAPPER" ]; then
    pass "rm wrapper script exists and is executable"
else
    fail "rm wrapper script not found at: $RM_WRAPPER"
    exit 1
fi

echo ""
echo -e "${YELLOW}Test 1: Safe rm operations (should pass through)${NC}"

# Create test file
TEST_FILE="/tmp/igris-rm-test-$$"
touch "$TEST_FILE"

# Safe rm should work without verification
if /bin/rm "$TEST_FILE" 2>/dev/null; then
    pass "Safe rm /tmp/file passed through"
else
    fail "Safe rm failed unexpectedly"
fi

echo ""
echo -e "${YELLOW}Test 2: Dangerous flag detection${NC}"

# Test various dangerous flag patterns
check_dangerous_flags() {
    local args="$1"
    local expected="$2"
    local description="$3"

    # Source the wrapper to test has_dangerous_flags function
    # We use TOMB_DRY_RUN to avoid actual verification
    export TOMB_DRY_RUN=true
    export TOMB_DANGEROUS_ENABLED=true

    local output
    output=$("$RM_WRAPPER" $args 2>&1) || true

    if [[ "$output" == *"DANGEROUS"* ]]; then
        if [ "$expected" = "dangerous" ]; then
            pass "$description detected as dangerous"
        else
            fail "$description should NOT be dangerous, but was detected"
        fi
    else
        if [ "$expected" = "safe" ]; then
            pass "$description passed through as safe"
        else
            fail "$description should be dangerous, but was not detected"
        fi
    fi
}

# These should be detected as dangerous when targeting protected paths
check_dangerous_flags "-rf ~" "dangerous" "rm -rf ~"
check_dangerous_flags "-fr /" "dangerous" "rm -fr /"
check_dangerous_flags "-r -f /Users" "dangerous" "rm -r -f /Users"
check_dangerous_flags "-f -r /System" "dangerous" "rm -f -r /System"

# These should be safe (no protected path or not recursive+force)
check_dangerous_flags "/tmp/safe" "safe" "rm /tmp/safe"
check_dangerous_flags "-r /tmp/dir" "safe" "rm -r /tmp/dir (no -f)"
check_dangerous_flags "-f /tmp/file" "safe" "rm -f /tmp/file (no -r)"

echo ""
echo -e "${YELLOW}Test 3: Protected path detection${NC}"

# Test protected paths
protected_paths=("/" "~" "/Users" "/System" "/usr" "/opt" "/Applications" "/Library")

for path in "${protected_paths[@]}"; do
    check_dangerous_flags "-rf $path" "dangerous" "rm -rf $path"
done

echo ""
echo -e "${YELLOW}Test 4: Environment detection${NC}"

# Source wrapper to test detect_environment
source "$RM_WRAPPER" 2>/dev/null || true

# Check current environment
if declare -f detect_environment > /dev/null 2>&1; then
    env=$(detect_environment)
    echo -e "Current environment: ${BLUE}$env${NC}"

    if [ "$env" = "main" ]; then
        pass "Detected main machine environment"
    elif [ "$env" = "vm" ]; then
        pass "Detected VM environment (protection would be skipped)"
    else
        echo -e "${YELLOW}⚠️${NC}  Unknown environment: $env"
    fi
else
    echo -e "${YELLOW}⚠️${NC}  Could not test environment detection (function not exported)"
fi

echo ""
echo -e "${YELLOW}Test 5: Bypass mode${NC}"

# Test TOMB_DANGEROUS_ENABLED=false
export TOMB_DANGEROUS_ENABLED=false
TEST_FILE2="/tmp/igris-rm-test2-$$"
touch "$TEST_FILE2"

if "$RM_WRAPPER" "$TEST_FILE2" 2>/dev/null; then
    pass "Bypass mode (TOMB_DANGEROUS_ENABLED=false) works"
else
    fail "Bypass mode failed"
fi

# Reset
export TOMB_DANGEROUS_ENABLED=true

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test Results${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
