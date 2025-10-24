#!/bin/bash

# Test script for audio deduplication
# Simulates rapid git operations to verify deduplication works

set -euo pipefail

TOMB_DIR="${TOMB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
AUDIO_CACHE_FILE="${HOME}/.tomb-audio-cache"

echo "🧪 Testing Audio Deduplication System"
echo "======================================"
echo ""

# Clean cache before test
if [ -f "$AUDIO_CACHE_FILE" ]; then
    echo "🗑️  Removing old cache file..."
    rm "$AUDIO_CACHE_FILE"
fi

# Test 1: First call should play audio
echo "Test 1: First verification (should play audio)"
echo "-----------------------------------------------"
source "${TOMB_DIR}/scripts/yubikey-verify.sh"
if should_play_audio; then
    echo "✅ PASS: Audio will play (first call)"
else
    echo "❌ FAIL: Audio skipped incorrectly"
fi
echo ""

# Test 2: Immediate second call should skip audio
echo "Test 2: Immediate second verification (should skip audio)"
echo "-----------------------------------------------------------"
if should_play_audio; then
    echo "❌ FAIL: Audio played when it should be skipped"
else
    echo "✅ PASS: Audio correctly skipped (within deduplication window)"
fi
echo ""

# Test 3: Third call immediately after should also skip
echo "Test 3: Third rapid verification (should skip audio)"
echo "------------------------------------------------------"
if should_play_audio; then
    echo "❌ FAIL: Audio played when it should be skipped"
else
    echo "✅ PASS: Audio correctly skipped (within deduplication window)"
fi
echo ""

# Test 4: Wait for deduplication window to expire
echo "Test 4: Waiting 9 seconds for deduplication window to expire..."
echo "----------------------------------------------------------------"
sleep 9

if should_play_audio; then
    echo "✅ PASS: Audio will play (outside deduplication window)"
else
    echo "❌ FAIL: Audio skipped incorrectly"
fi
echo ""

# Test 5: Check cache file
echo "Test 5: Verifying cache file behavior"
echo "---------------------------------------"
if [ -f "$AUDIO_CACHE_FILE" ]; then
    CACHE_TIME=$(cat "$AUDIO_CACHE_FILE")
    CURRENT_TIME=$(date +%s)
    AGE=$((CURRENT_TIME - CACHE_TIME))
    echo "✅ Cache file exists"
    echo "   Last audio: ${CACHE_TIME} (${AGE}s ago)"
else
    echo "❌ Cache file missing"
fi
echo ""

echo "======================================"
echo "🎉 Deduplication test complete!"
echo ""
echo "Expected behavior:"
echo "  - First call: Play audio ✓"
echo "  - Rapid calls within 8s: Skip audio ✓"
echo "  - After 8s window: Play audio again ✓"
