#!/bin/bash

# YubiKey Git Enforcement Setup Script
# Part of tomb-of-nazarick security system
# Manages installation, configuration, and removal of YubiKey enforcement

set -euo pipefail

# Configuration
TOMB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_SCRIPT="${TOMB_DIR}/scripts/yubikey-verify.sh"
GIT_WRAPPER="${TOMB_DIR}/scripts/git-yubikey-wrapper.sh"
GH_WRAPPER="${TOMB_DIR}/scripts/gh-yubikey-wrapper.sh"
PRE_PUSH_HOOK="${TOMB_DIR}/hooks/git-hooks/pre-push"
CONFIG_FILE="${TOMB_DIR}/configs/yubikey-enforcement.yml"
BACKUP_DIR="${HOME}/.tomb-yubikey-backup"
TEMPLATE_DIR="${HOME}/.git-templates"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Print functions
print_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

# Show usage
show_usage() {
    cat << EOF
YubiKey Git Enforcement Setup

USAGE:
    $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
    setup       Install YubiKey enforcement system (interactive)
    enable      Activate enforcement
    disable     Temporarily disable enforcement
    remove      Uninstall system completely
    status      Show enforcement status
    test        Test YubiKey verification

OPTIONS:
    --global        Apply to user shell config (default)
    --all-repos     Install hooks in all workspace repos
    --repo <path>   Target specific repository
    --non-interactive  Skip prompts and use defaults

EXAMPLES:
    $(basename "$0") setup              # Interactive setup with prompts
    $(basename "$0") setup --all-repos  # Install + add hooks to all repos
    $(basename "$0") status             # Check current status
    $(basename "$0") disable            # Temporarily disable (keep config)
    $(basename "$0") test               # Test YubiKey verification

EOF
}

# Reload shell configuration
reload_shell_config() {
    local shell_config="$1"

    print_info "Reloading shell configuration..."

    # Temporarily disable strict error handling for reload
    # (some shell configs may have unbound variables that are okay)
    set +u

    # Detect current shell
    if [ -n "${ZSH_VERSION:-}" ]; then
        # Running in zsh
        if [ -f "$shell_config" ]; then
            source "$shell_config" 2>/dev/null || {
                set -u
                print_warning "Shell config reload had warnings (this is usually okay)"
                print_info "Configuration changes will take effect in new terminals"
                return 1
            }
            set -u
            print_success "Shell configuration reloaded (zsh)"
            return 0
        fi
    elif [ -n "${BASH_VERSION:-}" ]; then
        # Running in bash
        if [ -f "$shell_config" ]; then
            source "$shell_config" 2>/dev/null || {
                set -u
                print_warning "Shell config reload had warnings (this is usually okay)"
                print_info "Configuration changes will take effect in new terminals"
                return 1
            }
            set -u
            print_success "Shell configuration reloaded (bash)"
            return 0
        fi
    fi

    set -u
    print_warning "Could not reload shell config automatically"
    print_info "Please restart your terminal or run: source $shell_config"
    return 1
}

# Interactive confirmation
confirm_action() {
    local prompt="$1"
    local default="${2:-no}"

    local yn
    if [ "$default" = "yes" ]; then
        read -p "$prompt [Y/n]: " yn
        yn=${yn:-y}
    else
        read -p "$prompt [y/N]: " yn
        yn=${yn:-n}
    fi

    case "$yn" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    local missing=0

    if ! command -v ykman &> /dev/null; then
        print_error "ykman not found. Install with: brew install ykman"
        missing=1
    fi

    if ! ykman list 2>/dev/null | grep -q "YubiKey"; then
        print_warning "No YubiKey detected. Please connect your YubiKey."
        missing=1
    fi

    if ! command -v git &> /dev/null; then
        print_error "git not found"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        return 1
    fi

    return 0
}

# Detect shell config file
detect_shell_config() {
    if [ -n "${ZSH_VERSION:-}" ] || [ -f "$HOME/.zshrc" ]; then
        echo "$HOME/.zshrc"
    elif [ -n "${BASH_VERSION:-}" ]; then
        if [ "$(uname)" = "Darwin" ]; then
            echo "$HOME/.bash_profile"
        else
            echo "$HOME/.bashrc"
        fi
    else
        echo "$HOME/.profile"
    fi
}

# Setup command
cmd_setup() {
    local interactive=true
    local install_all_repos=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive)
                interactive=false
                shift
                ;;
            --all-repos)
                install_all_repos=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    print_header "YubiKey Git Enforcement Setup"

    # Interactive welcome
    if [ "$interactive" = true ]; then
        echo "This setup will:"
        echo "  • Install YubiKey verification scripts"
        echo "  • Add git/gh command wrappers to your shell config"
        echo "  • Configure git hooks for all repositories"
        echo "  • Enable enforcement requiring physical YubiKey tap for network operations"
        echo ""

        if ! confirm_action "Do you want to proceed with setup?" "yes"; then
            print_info "Setup cancelled"
            exit 0
        fi
        echo ""
    fi

    # Check prerequisites
    print_info "Checking prerequisites..."
    if ! check_prerequisites; then
        print_error "Prerequisites not met. Please resolve issues above."
        exit 1
    fi
    print_success "Prerequisites met"

    # Create backup directory
    print_info "Creating backup directory..."
    mkdir -p "$BACKUP_DIR"
    print_success "Backup directory created: $BACKUP_DIR"

    # Detect shell config
    local shell_config
    shell_config=$(detect_shell_config)
    print_info "Detected shell config: $shell_config"

    # Backup existing config
    if [ -f "$shell_config" ]; then
        cp "$shell_config" "${BACKUP_DIR}/$(basename "$shell_config").backup.$(date +%Y%m%d-%H%M%S)"
        print_success "Backed up existing shell config"
    fi

    # Add shell aliases
    print_info "Installing shell wrappers..."

    # Check if already installed
    if grep -q "YubiKey Git Enforcement" "$shell_config" 2>/dev/null; then
        print_warning "Wrappers already installed in $shell_config"
        if [ "$interactive" = true ]; then
            if confirm_action "Reinstall wrappers?" "no"; then
                # Remove old installation
                sed -i.bak '/# YubiKey Git Enforcement/,/^$/d' "$shell_config"
            else
                print_info "Skipping wrapper installation"
                return 0
            fi
        fi
    fi

    if ! grep -q "YubiKey Git Enforcement" "$shell_config" 2>/dev/null; then
        cat >> "$shell_config" << EOF

# YubiKey Git Enforcement (managed by tomb-of-nazarick)
# Added on: $(date +%Y-%m-%d)
# DO NOT EDIT - Use 'yubikey-git-setup.sh' commands to manage

export TOMB_DIR="$TOMB_DIR"
export TOMB_YUBIKEY_ENABLED=true

# Wrapper functions
git() {
    "$GIT_WRAPPER" "\$@"
}

gh() {
    "$GH_WRAPPER" "\$@"
}

EOF

        # Add shell-specific completion preservation
        if [[ "$shell_config" == *"zshrc"* ]]; then
            cat >> "$shell_config" << 'EOF'
# Preserve completions for wrapped commands
compdef _git git=git
compdef _gh gh=gh

EOF
        fi

        print_success "Shell wrappers installed"
    fi

    # Setup git global hooks
    print_info "Setting up git global hooks..."

    # Create template directory
    mkdir -p "${TEMPLATE_DIR}/hooks"

    # Install pre-push hook
    cp "$PRE_PUSH_HOOK" "${TEMPLATE_DIR}/hooks/pre-push"
    chmod +x "${TEMPLATE_DIR}/hooks/pre-push"

    # Configure git to use template directory
    git config --global init.templateDir "$TEMPLATE_DIR"

    print_success "Git global hooks configured"

    # Optionally install in all repos
    if [ "$install_all_repos" = true ]; then
        print_info "Installing hooks in workspace repositories..."
        install_hooks_in_repos
    elif [ "$interactive" = true ]; then
        echo ""
        if confirm_action "Install hooks in all workspace repositories now?" "yes"; then
            install_hooks_in_repos
        else
            print_info "Skipped workspace hooks (you can run with --all-repos later)"
        fi
    fi

    # CRITICAL: YubiKey tap verification (proves physical access)
    print_header "Security Verification"
    echo "To ensure you have physical access to your YubiKey,"
    echo "you must tap it now to complete setup."
    echo ""
    print_warning "If this fails, setup will be automatically reverted!"
    echo ""

    if [ "$interactive" = true ]; then
        if ! confirm_action "Ready to verify YubiKey?" "yes"; then
            print_warning "Setup verification cancelled - reverting installation..."
            cmd_remove --non-interactive --force
            exit 1
        fi
    fi

    # Verify YubiKey tap
    echo ""
    print_info "Testing YubiKey verification..."
    if ! "$VERIFY_SCRIPT" "setup-verification"; then
        echo ""
        print_error "YubiKey verification failed!"
        print_error "This could mean:"
        echo "  • YubiKey not configured (run: $TOMB_DIR/scripts/yubikey-configure-otp.sh)"
        echo "  • YubiKey not connected"
        echo "  • Tap timeout (you must tap within ${YUBIKEY_TIMEOUT:-10} seconds)"
        echo ""
        print_warning "Automatically reverting installation for security..."
        cmd_remove --non-interactive --force
        echo ""
        print_error "Setup failed and has been reverted"
        print_info "Fix the issue and run setup again"
        exit 1
    fi

    # Verification successful!
    echo ""
    print_success "YubiKey verification successful!"

    # Show completion
    print_header "Setup Complete!"
    echo -e "${GREEN}✅ YubiKey enforcement is now installed${NC}"
    echo -e "${GREEN}✅ Physical access verified${NC}\n"

    # Interactive: offer to reload shell config
    if [ "$interactive" = true ]; then
        echo ""
        if confirm_action "Reload shell configuration now?" "yes"; then
            if reload_shell_config "$shell_config"; then
                echo ""
                print_success "Configuration active in this session!"
                print_info "YubiKey tap will be required for all git/gh network operations"
            fi
        else
            echo ""
            print_info "Manual reload required: source $shell_config"
            print_info "Or restart your terminal"
        fi
    else
        # Non-interactive: show manual steps
        echo "Next steps:"
        echo "  1. Restart your terminal or run: source $shell_config"
        echo "  2. Try a git operation: git push (will require tap)"
    fi

    echo ""
    print_info "To check status anytime: $(basename "$0") status"
    print_info "To remove completely: $(basename "$0") remove"
    echo ""
}

# Install hooks in workspace repos
install_hooks_in_repos() {
    # Read repos from config file
    local repos
    if [ -f "$CONFIG_FILE" ]; then
        # Parse YAML more carefully - only lines under workspace_repos that start with "    -"
        # Stop at the next top-level key (starts with no indent or "devices:")
        repos=$(awk '/workspace_repos:/,/^[a-z]/ {
            if ($0 ~ /^    - /) {
                sub(/^    - /, "");
                print
            }
        }' "$CONFIG_FILE")
    else
        # Default repos
        repos=$(cat << EOF
/Users/fweir/git/internal/repos/tomb-of-nazarick
/Users/fweir/git/internal/repos/carian-observatory
/Users/fweir/git/internal/repos/fifth-symphony
/Users/fweir/git/internal/repos/EchoLink-Reborn
EOF
)
    fi

    while IFS= read -r repo; do
        # Skip empty lines
        [ -z "$repo" ] && continue

        if [ -d "$repo/.git" ]; then
            cp "$PRE_PUSH_HOOK" "$repo/.git/hooks/pre-push"
            chmod +x "$repo/.git/hooks/pre-push"
            print_success "Installed hook in: $(basename "$repo")"
        else
            print_warning "Skipping non-git directory: $repo"
        fi
    done <<< "$repos"
}

# Enable command
cmd_enable() {
    print_header "Enabling YubiKey Enforcement"

    local shell_config
    shell_config=$(detect_shell_config)

    # Update shell config
    if grep -q "TOMB_YUBIKEY_ENABLED=false" "$shell_config" 2>/dev/null; then
        sed -i.bak 's/TOMB_YUBIKEY_ENABLED=false/TOMB_YUBIKEY_ENABLED=true/' "$shell_config"
        print_success "Enforcement enabled in shell config"
    else
        print_info "Enforcement already enabled"
    fi

    # Update config file
    if [ -f "$CONFIG_FILE" ]; then
        sed -i.bak 's/enabled: false/enabled: true/' "$CONFIG_FILE"
    fi

    print_success "YubiKey enforcement is now ACTIVE"
    print_info "Restart your terminal or run: source $shell_config"
}

# Disable command
cmd_disable() {
    print_header "Disabling YubiKey Enforcement"

    local shell_config
    shell_config=$(detect_shell_config)

    # Update shell config
    if grep -q "TOMB_YUBIKEY_ENABLED=true" "$shell_config" 2>/dev/null; then
        sed -i.bak 's/TOMB_YUBIKEY_ENABLED=true/TOMB_YUBIKEY_ENABLED=false/' "$shell_config"
        print_success "Enforcement disabled in shell config"
    else
        print_info "Enforcement already disabled"
    fi

    # Update config file
    if [ -f "$CONFIG_FILE" ]; then
        sed -i.bak 's/enabled: true/enabled: false/' "$CONFIG_FILE"
    fi

    print_warning "YubiKey enforcement is now DISABLED"
    print_info "To re-enable: $(basename "$0") enable"
    print_info "Restart your terminal or run: source $shell_config"
}

# Status command
cmd_status() {
    print_header "YubiKey Git Enforcement Status"

    # Check enforcement state
    local enabled="false"
    local shell_config
    shell_config=$(detect_shell_config)

    if grep -q "TOMB_YUBIKEY_ENABLED=true" "$shell_config" 2>/dev/null; then
        enabled="true"
    fi

    if [ "$enabled" = "true" ]; then
        echo -e "Enforcement: ${GREEN}✅ ENABLED${NC}"
    else
        echo -e "Enforcement: ${RED}❌ DISABLED${NC}"
    fi

    # Check YubiKey
    if ykman list 2>/dev/null | grep -q "YubiKey"; then
        local yubikey_info=$(ykman list 2>/dev/null)
        echo -e "YubiKey:     ${GREEN}✅ Connected${NC}"
        echo "             $yubikey_info"
    else
        echo -e "YubiKey:     ${RED}❌ Not detected${NC}"
    fi

    # Check wrappers
    if grep -q "git-yubikey-wrapper" "$shell_config" 2>/dev/null; then
        echo -e "Wrappers:    ${GREEN}✅ Installed${NC} (git, gh)"
    else
        echo -e "Wrappers:    ${RED}❌ Not installed${NC}"
    fi

    # Check hooks
    if [ -f "${TEMPLATE_DIR}/hooks/pre-push" ]; then
        echo -e "Hooks:       ${GREEN}✅ Configured${NC} (global template)"
    else
        echo -e "Hooks:       ${YELLOW}⚠️  Not configured${NC}"
    fi

    # Show config file
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "\nConfiguration: $CONFIG_FILE"
    fi

    # Show recent verifications
    if [ -f "${HOME}/.tomb-yubikey-verifications.log" ]; then
        echo -e "\nRecent verifications (last 5):"
        tail -5 "${HOME}/.tomb-yubikey-verifications.log" | while read -r line; do
            if [[ "$line" =~ SUCCESS ]]; then
                echo -e "  ${GREEN}✅${NC} $line"
            elif [[ "$line" =~ FAILURE|TIMEOUT ]]; then
                echo -e "  ${RED}❌${NC} $line"
            else
                echo -e "  ${YELLOW}⚠️${NC} $line"
            fi
        done
    fi

    echo ""
}

# Test command
cmd_test() {
    print_header "Testing YubiKey Verification"

    if [ ! -x "$VERIFY_SCRIPT" ]; then
        print_error "Verification script not found: $VERIFY_SCRIPT"
        exit 1
    fi

    print_info "Running verification test..."
    echo ""

    if "$VERIFY_SCRIPT" "test-operation"; then
        echo ""
        print_success "YubiKey verification test PASSED"
        return 0
    else
        echo ""
        print_error "YubiKey verification test FAILED"
        return 1
    fi
}

# Remove command
cmd_remove() {
    local interactive=true
    local force=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive)
                interactive=false
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    print_header "Removing YubiKey Enforcement"

    if [ "$interactive" = true ] && [ "$force" = false ]; then
        echo "This will completely remove:"
        echo "  • Shell wrappers (git/gh command interception)"
        echo "  • Git hooks (pre-push verification)"
        echo "  • Configuration files"
        echo ""
        print_warning "This is a destructive operation!"
        echo ""

        if ! confirm_action "Are you sure you want to remove YubiKey enforcement?" "no"; then
            print_info "Removal cancelled"
            exit 0
        fi
    fi

    local shell_config
    shell_config=$(detect_shell_config)

    print_info "Creating backups before removal..."

    # Create comprehensive backup
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local removal_backup_dir="${BACKUP_DIR}/removal-${backup_timestamp}"
    mkdir -p "$removal_backup_dir"

    # Backup shell config
    if grep -q "YubiKey Git Enforcement" "$shell_config" 2>/dev/null; then
        cp "$shell_config" "${removal_backup_dir}/$(basename "$shell_config")"
        print_success "Backed up shell config"
    fi

    # Backup git hooks from workspace repos
    if [ -f "$CONFIG_FILE" ]; then
        local repos=$(awk '/workspace_repos:/,/^[a-z]/ {
            if ($0 ~ /^    - /) {
                sub(/^    - /, "");
                print
            }
        }' "$CONFIG_FILE")

        while IFS= read -r repo; do
            [ -z "$repo" ] && continue
            if [ -f "$repo/.git/hooks/pre-push" ]; then
                local repo_name=$(basename "$repo")
                cp "$repo/.git/hooks/pre-push" "${removal_backup_dir}/pre-push.${repo_name}"
            fi
        done <<< "$repos"

        print_success "Backed up repository hooks"
    fi

    # Remove from shell config
    print_info "Removing shell wrappers..."
    if grep -q "YubiKey Git Enforcement" "$shell_config" 2>/dev/null; then
        # Remove the wrapper section and any blank lines it leaves
        sed -i.bak '/# YubiKey Git Enforcement/,/^$/d' "$shell_config"
        # Also remove the compdef lines if they exist
        sed -i.bak '/compdef _git git=git/d' "$shell_config"
        sed -i.bak '/compdef _gh gh=gh/d' "$shell_config"
        print_success "Removed wrappers from shell config"
    else
        print_info "No wrappers found in shell config"
    fi

    # Remove git hooks from template
    print_info "Removing global git hooks..."
    if [ -f "${TEMPLATE_DIR}/hooks/pre-push" ]; then
        rm -f "${TEMPLATE_DIR}/hooks/pre-push"
        print_success "Removed pre-push hook from git template"
    else
        print_info "No global hooks found"
    fi

    # Remove hooks from workspace repositories
    if [ -f "$CONFIG_FILE" ]; then
        print_info "Removing hooks from workspace repositories..."
        local repos=$(awk '/workspace_repos:/,/^[a-z]/ {
            if ($0 ~ /^    - /) {
                sub(/^    - /, "");
                print
            }
        }' "$CONFIG_FILE")

        while IFS= read -r repo; do
            [ -z "$repo" ] && continue
            if [ -f "$repo/.git/hooks/pre-push" ]; then
                rm -f "$repo/.git/hooks/pre-push"
                print_success "Removed hook from: $(basename "$repo")"
            fi
        done <<< "$repos"
    fi

    # Archive config file
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${removal_backup_dir}/yubikey-enforcement.yml"
        mv "$CONFIG_FILE" "${CONFIG_FILE}.disabled.${backup_timestamp}"
        print_success "Archived configuration file"
    fi

    # Clean up git template directory if empty
    if [ -d "${TEMPLATE_DIR}/hooks" ] && [ -z "$(ls -A "${TEMPLATE_DIR}/hooks")" ]; then
        rmdir "${TEMPLATE_DIR}/hooks" 2>/dev/null || true
        if [ -d "$TEMPLATE_DIR" ] && [ -z "$(ls -A "$TEMPLATE_DIR")" ]; then
            rmdir "$TEMPLATE_DIR" 2>/dev/null || true
            print_info "Removed empty git template directory"
        fi
    fi

    print_header "Removal Complete"
    print_success "YubiKey enforcement has been completely removed"
    echo ""
    print_info "Backups saved to: $removal_backup_dir"
    echo ""
    print_info "What was removed:"
    echo "  ✓ Shell wrappers from $shell_config"
    echo "  ✓ Git global hooks from $TEMPLATE_DIR"
    echo "  ✓ Repository-specific hooks"
    echo "  ✓ Configuration files"
    echo ""
    print_warning "Restart your terminal or run: source $shell_config"
    echo ""
    print_info "To restore, you can:"
    echo "  1. Run setup again: $(basename "$0") setup"
    echo "  2. Restore from backup: $removal_backup_dir"
    echo ""
}

# Main command router
main() {
    local command="${1:-}"

    case "$command" in
        setup)
            shift
            cmd_setup "$@"
            ;;
        enable)
            cmd_enable
            ;;
        disable)
            cmd_disable
            ;;
        status)
            cmd_status
            ;;
        test)
            cmd_test
            ;;
        remove)
            cmd_remove
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            if [ -z "$command" ]; then
                show_usage
            else
                print_error "Unknown command: $command"
                echo ""
                show_usage
                exit 1
            fi
            ;;
    esac
}

main "$@"
