#!/bin/bash
# =============================================================================
# 1PASSWORD TOUCH ID MONITOR
# =============================================================================
# Background service that monitors for 1Password Touch ID prompts and plays
# audio alerts when they appear, helping you notice prompts on other screens
#
# Usage:
#   ./1password-touchid-monitor.sh start   # Start monitoring
#   ./1password-touchid-monitor.sh stop    # Stop monitoring
#   ./1password-touchid-monitor.sh status  # Check status
#
# The monitor runs in the background and plays a system sound whenever
# 1Password's Touch ID authentication dialog appears

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$REPO_DIR/configs/audio-alerts.yml"
PID_FILE="$HOME/.1password-touchid-monitor.pid"
LOG_FILE="$HOME/.1password-touchid-monitor.log"

# Default audio settings
ALERT_SOUND="Glass"  # macOS system sound (alternatives: Glass, Tink, Pop, Purr, Hero)
CHECK_INTERVAL=0.5    # Check every 0.5 seconds for prompt

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Load configuration from audio-alerts.yml
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Check if 1password section exists
        local op_enabled=$(grep -A 2 "^onepassword:" "$CONFIG_FILE" 2>/dev/null | grep "enabled:" | awk '{print $2}' || echo "true")
        local op_sound=$(grep -A 2 "^onepassword:" "$CONFIG_FILE" 2>/dev/null | grep "touchid_alert_sound:" | awk '{print $2}' || echo "")

        if [[ "$op_enabled" == "false" ]]; then
            print_warning "1Password audio alerts disabled in config"
            return 1
        fi

        if [[ -n "$op_sound" ]]; then
            ALERT_SOUND="$op_sound"
        fi
    fi
    return 0
}

# Check if 1Password Touch ID prompt is currently visible
check_for_touchid_prompt() {
    # Check if 1Password authentication window is visible
    # This uses AppleScript to check for the Touch ID prompt window
    osascript -e '
        tell application "System Events"
            set appName to "1Password"
            if exists process appName then
                tell process appName
                    if exists (windows whose name contains "Touch ID" or description contains "Touch ID" or description contains "Unlock")
                        return "true"
                    end if
                end tell
            end if
        end tell
        return "false"
    ' 2>/dev/null
}

# Play notification sound
play_alert() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] 1Password Touch ID prompt detected - playing alert" >> "$LOG_FILE"

    # Play macOS system sound
    afplay "/System/Library/Sounds/${ALERT_SOUND}.aiff" 2>/dev/null || {
        # Fallback to simpler notification
        osascript -e "beep" 2>/dev/null
    }
}

# Monitor loop (runs in background)
monitor_loop() {
    local last_prompt_state="false"

    print_info "Starting 1Password Touch ID monitor..."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Monitor started (PID: $$)" >> "$LOG_FILE"

    while true; do
        local prompt_visible=$(check_for_touchid_prompt)

        # Only play sound on state transition (false -> true)
        # This prevents repeated sounds while prompt is open
        if [[ "$prompt_visible" == "true" && "$last_prompt_state" == "false" ]]; then
            play_alert
            last_prompt_state="true"
        elif [[ "$prompt_visible" == "false" ]]; then
            last_prompt_state="false"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Start monitoring in background
start_monitor() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            print_warning "Monitor already running (PID: $pid)"
            return 0
        else
            print_warning "Removing stale PID file"
            rm "$PID_FILE"
        fi
    fi

    # Load configuration
    if ! load_config; then
        print_error "1Password audio alerts disabled in config"
        return 1
    fi

    print_info "Starting background monitor (sound: $ALERT_SOUND)..."

    # Start monitor in background
    nohup bash -c "
        $(declare -f check_for_touchid_prompt)
        $(declare -f play_alert)
        ALERT_SOUND='$ALERT_SOUND'
        CHECK_INTERVAL='$CHECK_INTERVAL'
        LOG_FILE='$LOG_FILE'
        $(declare -f monitor_loop)
        monitor_loop
    " > /dev/null 2>&1 &

    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Give it a moment to start
    sleep 1

    if ps -p "$pid" > /dev/null 2>&1; then
        print_success "Monitor started (PID: $pid)"
        print_info "Log file: $LOG_FILE"
        print_info "Alert sound: $ALERT_SOUND"
        return 0
    else
        print_error "Failed to start monitor"
        rm "$PID_FILE" 2>/dev/null
        return 1
    fi
}

# Stop monitoring
stop_monitor() {
    if [[ ! -f "$PID_FILE" ]]; then
        print_warning "Monitor not running (no PID file)"
        return 0
    fi

    local pid=$(cat "$PID_FILE")

    if ! ps -p "$pid" > /dev/null 2>&1; then
        print_warning "Monitor not running (stale PID)"
        rm "$PID_FILE"
        return 0
    fi

    print_info "Stopping monitor (PID: $pid)..."
    kill "$pid" 2>/dev/null || {
        print_warning "Process already stopped"
    }

    # Wait for process to stop
    local count=0
    while ps -p "$pid" > /dev/null 2>&1 && [[ $count -lt 10 ]]; do
        sleep 0.5
        ((count++))
    done

    if ps -p "$pid" > /dev/null 2>&1; then
        print_warning "Process not stopping, forcing..."
        kill -9 "$pid" 2>/dev/null
    fi

    rm "$PID_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Monitor stopped" >> "$LOG_FILE"
    print_success "Monitor stopped"
}

# Check monitor status
check_status() {
    if [[ ! -f "$PID_FILE" ]]; then
        print_info "Monitor: NOT RUNNING"
        return 1
    fi

    local pid=$(cat "$PID_FILE")

    if ps -p "$pid" > /dev/null 2>&1; then
        print_success "Monitor: RUNNING (PID: $pid)"
        print_info "Alert sound: $ALERT_SOUND"
        print_info "Check interval: ${CHECK_INTERVAL}s"
        print_info "Log file: $LOG_FILE"

        # Show recent log entries
        if [[ -f "$LOG_FILE" ]]; then
            echo ""
            print_info "Recent alerts (last 5):"
            tail -5 "$LOG_FILE" | sed 's/^/  /'
        fi
        return 0
    else
        print_warning "Monitor: NOT RUNNING (stale PID file)"
        rm "$PID_FILE"
        return 1
    fi
}

# Test alert sound
test_alert() {
    print_info "Testing alert sound: $ALERT_SOUND"
    play_alert
    print_success "Alert sound test complete"
}

# Install as launch agent (auto-start on login)
install_launch_agent() {
    local plist_file="$HOME/Library/LaunchAgents/com.igris.1password-touchid-monitor.plist"

    print_info "Creating LaunchAgent plist..."

    cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.igris.1password-touchid-monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/1password-touchid-monitor.sh</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.1password-touchid-monitor-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.1password-touchid-monitor-stderr.log</string>
</dict>
</plist>
EOF

    print_success "LaunchAgent plist created: $plist_file"
    print_info "Loading LaunchAgent..."

    launchctl load "$plist_file"

    print_success "LaunchAgent installed and loaded"
    print_info "Monitor will now start automatically on login"
}

# Uninstall launch agent
uninstall_launch_agent() {
    local plist_file="$HOME/Library/LaunchAgents/com.igris.1password-touchid-monitor.plist"

    if [[ ! -f "$plist_file" ]]; then
        print_warning "LaunchAgent not installed"
        return 0
    fi

    print_info "Unloading LaunchAgent..."
    launchctl unload "$plist_file" 2>/dev/null || true

    print_info "Removing LaunchAgent plist..."
    rm "$plist_file"

    print_success "LaunchAgent uninstalled"
}

# Show help
show_help() {
    cat << EOF
${BLUE}1Password Touch ID Monitor${NC}

Monitors for 1Password Touch ID authentication prompts and plays audio alerts
to help you notice them when they appear on other screens.

${YELLOW}Commands:${NC}
  start                 Start monitoring in background
  stop                  Stop monitoring
  status                Check monitor status
  restart               Restart monitor
  test                  Test alert sound
  install               Install as LaunchAgent (auto-start on login)
  uninstall             Remove LaunchAgent
  help                  Show this help

${YELLOW}Configuration:${NC}
  Edit: $CONFIG_FILE

  Add this section to configure:
    onepassword:
      enabled: true
      touchid_alert_sound: Glass  # macOS system sound

  Available sounds: Glass, Tink, Pop, Purr, Hero, Ping, Blow, Bottle

${YELLOW}Examples:${NC}
  $0 start              # Start monitoring
  $0 status             # Check if running
  $0 test               # Test sound
  $0 install            # Auto-start on login

${YELLOW}Files:${NC}
  PID file: $PID_FILE
  Log file: $LOG_FILE
  Config:   $CONFIG_FILE

EOF
}

# Main command handler
main() {
    local command="${1:-help}"

    case "$command" in
        start)
            start_monitor
            ;;
        stop)
            stop_monitor
            ;;
        status)
            check_status
            ;;
        restart)
            stop_monitor
            sleep 1
            start_monitor
            ;;
        test)
            test_alert
            ;;
        install)
            install_launch_agent
            ;;
        uninstall)
            uninstall_launch_agent
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Load config on script load
load_config

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
