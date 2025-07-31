#!/usr/bin/env bash
#
# setup.sh - Universal installer for Tailscale CLI helpers
#
# This script can install the tools for either a single user or system-wide
#

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Detect OS and package manager
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_FAMILY=$ID_LIKE
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    elif [[ -f /etc/debian_version ]]; then
        OS=debian
    elif [[ -f /etc/redhat-release ]]; then
        OS=rhel
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
    
    # Determine package manager
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v brew >/dev/null 2>&1; then
        PKG_MANAGER="brew"
    else
        PKG_MANAGER="unknown"
    fi
}

# Install bash completion file
install_bash_completion() {
    local dest_file="$1"
    local source_file="bash-completion/tailscale-completion.sh"
    
    # Try to find the completion file
    if [[ -f "$source_file" ]]; then
        cp "$source_file" "$dest_file"
        chmod 644 "$dest_file"
        return 0
    elif [[ -f "$SCRIPT_DIR/$source_file" ]]; then
        cp "$SCRIPT_DIR/$source_file" "$dest_file"
        chmod 644 "$dest_file"
        return 0
    else
        # Fallback: create minimal completion
        cat > "$dest_file" << 'EOF'
# Minimal fallback completion for Tailscale CLI helpers
complete -W "ssh scp sftp rsync ssh_copy_id mussh help" ts
complete -W "-v -h --help -V --version" tssh tscp tsftp trsync tssh_copy_id
EOF
        echo "Warning: Using minimal completion. Full completion file not found." >&2
    fi
}

# Clean up old function-based installation
cleanup_old_installation() {
    local mode="$1"  # "user" or "system"
    
    if [[ "$mode" == "user" ]]; then
        # Remove old sourcing from shell rc files
        local rc_files=("$HOME/.bashrc" "$HOME/.zshrc")
        for rc in "${rc_files[@]}"; do
            if [[ -f "$rc" ]]; then
                # Remove old sourcing lines
                sed -i.bak '/tailscale-ssh-helper\.sh/d' "$rc" 2>/dev/null || true
                sed -i.bak '/tailscale-cli-helpers.*profile\.d/d' "$rc" 2>/dev/null || true
                # Clean up backup if changes were made
                if ! diff -q "$rc" "$rc.bak" >/dev/null 2>&1; then
                    echo "Removed old configuration from $rc"
                fi
                rm -f "$rc.bak"
            fi
        done
        
        # Remove old user completion files
        if [[ -f "$HOME/.local/share/bash-completion/completions/tailscale-ssh-helper" ]]; then
            rm -f "$HOME/.local/share/bash-completion/completions/tailscale-ssh-helper"
        fi
        
        # Remove old function files from user directory
        local old_install_dir="$HOME/.local/share/tailscale-cli-helpers"
        if [[ -d "$old_install_dir" ]] && [[ ! -d "$old_install_dir/lib" ]]; then
            echo "Removing old function-based installation from $old_install_dir..."
            # Only remove if it doesn't have the new lib/ structure
            local old_files=("tailscale-ssh-helper.sh" "tailscale-functions.sh" "tailscale-completion.sh" "tailscale-mussh.sh" "tailscale-ts-dispatcher.sh")
            for file in "${old_files[@]}"; do
                [[ -f "$old_install_dir/$file" ]] && rm -f "$old_install_dir/$file"
            done
            # Remove directory if empty
            rmdir "$old_install_dir" 2>/dev/null || true
        fi
    else
        # System-wide cleanup
        if [[ -f "/etc/profile.d/tailscale-cli-helpers.sh" ]]; then
            # Check if it's the old version (contains source commands)
            if grep -q "tailscale-ssh-helper.sh" "/etc/profile.d/tailscale-cli-helpers.sh" 2>/dev/null; then
                echo "Removing old system-wide profile script..."
                rm -f "/etc/profile.d/tailscale-cli-helpers.sh"
            fi
        fi
        
        # Remove old bash completion if it contains function loading
        if [[ -f "/etc/bash_completion.d/tailscale-cli-helpers" ]]; then
            if grep -q "tailscale-ssh-helper.sh" "/etc/bash_completion.d/tailscale-cli-helpers" 2>/dev/null; then
                echo "Removing old bash completion script..."
                rm -f "/etc/bash_completion.d/tailscale-cli-helpers"
            fi
        fi
    fi
}

# Validate destination directory is writable and safe
validate_destination_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]] || [[ ! -w "$dir" ]]; then
        print_error "Directory $dir is not writable"
        return 1
    fi
    return 0
}

# Install for current user
install_user() {
    echo "Installing Tailscale CLI helpers for current user..."
    
    # Clean up old installation first
    cleanup_old_installation "user"
    
    # Setup directories
    local bin_dir="$HOME/.local/bin"
    local lib_dir="$HOME/.local/share/tailscale-cli-helpers/lib"
    local man_dir="$HOME/.local/share/man/man1"
    local completion_dir="$HOME/.local/share/bash-completion/completions"
    
    mkdir -p "$bin_dir" "$lib_dir" "$man_dir" "$completion_dir"
    
    # Security: Validate destination directories
    validate_destination_dir "$bin_dir" || return 1
    validate_destination_dir "$lib_dir" || return 1
    validate_destination_dir "$man_dir" || return 1
    validate_destination_dir "$completion_dir" || return 1
    
    # Install executables (excluding tmussh - optional)
    local commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id")
    for cmd in "${commands[@]}"; do
        if [[ -f "$SCRIPT_DIR/bin/$cmd" ]]; then
            install -m 755 "$SCRIPT_DIR/bin/$cmd" "$bin_dir/"
            echo "Installed: $cmd"
        else
            print_warning "Skipping $cmd - not found"
        fi
    done
    
    # Check if tmussh exists and install if available
    if [[ -f "$SCRIPT_DIR/bin/tmussh" ]]; then
        if command -v mussh >/dev/null 2>&1; then
            install -m 755 "$SCRIPT_DIR/bin/tmussh" "$bin_dir/"
            echo "Installed: tmussh (mussh found)"
        else
            print_warning "Skipping tmussh - mussh not installed"
            echo "To enable tmussh, install mussh first"
        fi
    fi
    
    # Install shared libraries
    install -m 644 "$SCRIPT_DIR/lib/tailscale-resolver.sh" "$lib_dir/"
    install -m 644 "$SCRIPT_DIR/lib/common.sh" "$lib_dir/"
    echo "Installed: shared libraries"
    
    # Install man pages
    for man in "$SCRIPT_DIR"/man/man1/*.1; do
        if [[ -f "$man" ]]; then
            # Skip tmussh man page if mussh not installed
            if [[ "$(basename "$man")" == "tmussh.1" ]] && ! command -v mussh >/dev/null 2>&1; then
                continue
            fi
            gzip -c "$man" > "$man_dir/$(basename "$man").gz"
        fi
    done
    echo "Installed: man pages"
    
    # Install bash completion
    install_bash_completion "$completion_dir/tailscale-cli-helpers"
    echo "Installed: bash completions"
    
    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        print_warning "~/.local/bin is not in your PATH"
        echo ""
        echo "Add to your shell configuration file:"
        echo '  export PATH="$HOME/.local/bin:$PATH"'
        echo ""
        echo "For bash (~/.bashrc):"
        echo '  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.bashrc'
        echo ""
        echo "For zsh (~/.zshrc):"
        echo '  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.zshrc'
    else
        print_success "Installation complete!"
        echo "Commands are available in your current PATH."
    fi
    echo ""
    echo "To enable bash completions in current shell:"
    echo "  source $completion_dir/tailscale-cli-helpers"
}

# Install system-wide (requires root/sudo)
install_system() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "System-wide installation requires root privileges"
        echo "Please run with sudo: sudo $0 --system"
        exit 1
    fi
    
    echo "Installing Tailscale CLI helpers system-wide..."
    
    # Clean up old installation first
    cleanup_old_installation "system"
    
    # Setup directories
    local bin_dir="/usr/bin"
    local lib_dir="/usr/share/tailscale-cli-helpers/lib"
    local man_dir="/usr/share/man/man1"
    local completion_dir="/etc/bash_completion.d"
    
    mkdir -p "$lib_dir" "$completion_dir"
    
    # Security: Validate destination directories
    validate_destination_dir "$bin_dir" || return 1
    validate_destination_dir "$lib_dir" || return 1
    validate_destination_dir "$man_dir" || return 1
    validate_destination_dir "$completion_dir" || return 1
    
    # Install executables
    local commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id")
    for cmd in "${commands[@]}"; do
        if [[ -f "$SCRIPT_DIR/bin/$cmd" ]]; then
            install -m 755 "$SCRIPT_DIR/bin/$cmd" "$bin_dir/"
            echo "Installed: $cmd"
        fi
    done
    
    # Install tmussh if mussh is available
    if [[ -f "$SCRIPT_DIR/bin/tmussh" ]] && command -v mussh >/dev/null 2>&1; then
        install -m 755 "$SCRIPT_DIR/bin/tmussh" "$bin_dir/"
        echo "Installed: tmussh"
    fi
    
    # Install shared libraries
    install -m 644 "$SCRIPT_DIR/lib/tailscale-resolver.sh" "$lib_dir/"
    install -m 644 "$SCRIPT_DIR/lib/common.sh" "$lib_dir/"
    echo "Installed: shared libraries"
    
    # Install man pages
    for man in "$SCRIPT_DIR"/man/man1/*.1; do
        if [[ -f "$man" ]]; then
            # Skip tmussh man page if mussh not installed  
            if [[ "$(basename "$man")" == "tmussh.1" ]] && ! command -v mussh >/dev/null 2>&1; then
                continue
            fi
            gzip -c "$man" > "$man_dir/$(basename "$man").gz"
        fi
    done
    echo "Installed: man pages"
    
    # Install bash completion
    install_bash_completion "$completion_dir/tailscale-cli-helpers"
    echo "Installed: bash completions"
    
    echo ""
    print_success "System-wide installation complete!"
    
    # Check if this is a package-managed installation
    if [[ -f "/usr/bin/tailscale-cli-helpers-setup" ]] && [[ "$0" == "/usr/bin/tailscale-cli-helpers-setup" ]]; then
        echo "Note: This appears to be a package-managed installation."
        echo "Updates should be done through your package manager."
    fi
    echo "Commands are immediately available in all shells."
    echo "Bash completions will be available in new bash sessions."
}

# Uninstall function
uninstall() {
    local mode="$1"
    
    if [[ "$mode" == "user" ]]; then
        echo "Removing user installation..."
        
        # Remove executables
        local commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id" "tmussh")
        for cmd in "${commands[@]}"; do
            [[ -f "$HOME/.local/bin/$cmd" ]] && rm -f "$HOME/.local/bin/$cmd" && echo "Removed: $cmd"
        done
        
        # Remove libraries
        if [[ -d "$HOME/.local/share/tailscale-cli-helpers" ]]; then
            rm -rf "$HOME/.local/share/tailscale-cli-helpers"
            echo "Removed: shared libraries"
        fi
        
        # Remove man pages
        for man in "$HOME"/.local/share/man/man1/ts*.1.gz; do
            [[ -f "$man" ]] && rm -f "$man"
        done
        
        # Remove user bash completion
        if [[ -f "$HOME/.local/share/bash-completion/completions/tailscale-cli-helpers" ]]; then
            rm -f "$HOME/.local/share/bash-completion/completions/tailscale-cli-helpers"
            echo "Removed user bash completions"
        fi
        
        print_success "User installation removed"
    else
        # System-wide uninstall
        if [[ $EUID -ne 0 ]]; then
            print_error "System-wide uninstall requires root privileges"
            echo "Please run with sudo: sudo $0 --uninstall"
            exit 1
        fi
        
        echo "Removing system-wide installation..."
        
        local commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id" "tmussh")
        for cmd in "${commands[@]}"; do
            [[ -f "/usr/bin/$cmd" ]] && rm -f "/usr/bin/$cmd" && echo "Removed: $cmd"
        done
        
        if [[ -d "/usr/share/tailscale-cli-helpers" ]]; then
            rm -rf "/usr/share/tailscale-cli-helpers"
            echo "Removed: shared libraries"
        fi
        
        for man in /usr/share/man/man1/ts*.1.gz; do
            [[ -f "$man" ]] && rm -f "$man"
        done
        
        if [[ -f "/etc/bash_completion.d/tailscale-cli-helpers" ]]; then
            rm -f "/etc/bash_completion.d/tailscale-cli-helpers"
            echo "Removed system bash completions"
        fi
        
        # Clean up old files
        cleanup_old_installation "system"
        
        print_success "System-wide installation removed"
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    # Required dependencies
    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi
    
    if ! command -v tailscale >/dev/null 2>&1; then
        missing+=("tailscale")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Please install missing dependencies:"
        
        case "$PKG_MANAGER" in
            apt)
                echo "  sudo apt update && sudo apt install ${missing[*]}"
                ;;
            dnf)
                echo "  sudo dnf install ${missing[*]}"
                ;;
            yum)
                echo "  sudo yum install ${missing[*]}"
                ;;
            brew)
                echo "  brew install ${missing[*]}"
                ;;
            *)
                echo "  Install: ${missing[*]}"
                ;;
        esac
        return 1
    fi
    
    # Optional dependencies
    local optional=()
    if ! command -v scp >/dev/null 2>&1; then
        optional+=("openssh-clients (for scp)")
    fi
    
    if ! command -v rsync >/dev/null 2>&1; then
        optional+=("rsync")
    fi
    
    if ! command -v mussh >/dev/null 2>&1; then
        optional+=("mussh (for tmussh)")
    fi
    
    if [[ ${#optional[@]} -gt 0 ]]; then
        print_warning "Optional dependencies not installed:"
        for opt in "${optional[@]}"; do
            echo "  - $opt"
        done
        echo "Some features may not be available."
    fi
    
    return 0
}

# Show usage
usage() {
    echo "Tailscale CLI Helpers Setup"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  --user       Install for current user only (default)"
    echo "  --system     Install system-wide (requires sudo)"
    echo "  --uninstall  Remove installation"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Install for current user"
    echo "  $0 --user       # Install for current user"
    echo "  sudo $0 --system    # Install system-wide"
    echo "  $0 --uninstall      # Remove user installation"
    echo "  sudo $0 --uninstall # Remove system installation"
}

# Main
main() {
    detect_os
    
    # Default to user installation
    local mode="user"
    local action="install"
    
    # Parse arguments
    case "${1:-}" in
        --system|-s)
            mode="system"
            ;;
        --user|-u)
            mode="user"
            ;;
        --uninstall)
            action="uninstall"
            # Detect which type of installation exists
            if [[ $EUID -eq 0 ]] || [[ -f "/usr/bin/ts" ]]; then
                mode="system"
            else
                mode="user"
            fi
            ;;
        --help|-h|help)
            usage
            exit 0
            ;;
        "")
            # No argument, default to user install
            mode="user"
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    
    # Perform action
    if [[ "$action" == "uninstall" ]]; then
        uninstall "$mode"
    else
        # Check dependencies before installation
        if ! check_dependencies; then
            exit 1
        fi
        
        if [[ "$mode" == "system" ]]; then
            install_system
        else
            install_user
        fi
    fi
}

# Run main function
main "$@"