#!/bin/bash
# Universal setup script for tailscale-cli-helpers

set -e

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/fedora-release ]]; then
        echo "fedora"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        if [[ -f /etc/lsb-release ]]; then
            source /etc/lsb-release
            if [[ "$DISTRIB_ID" == "Ubuntu" ]]; then
                echo "ubuntu"
            else
                echo "debian"
            fi
        else
            echo "debian"
        fi
    else
        echo "unknown"
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    # Check for tailscale
    if ! command -v tailscale &> /dev/null; then
        missing+=("tailscale")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing dependencies: ${missing[*]}"
        echo "Please install them before running this setup."
        return 1
    fi
    
    return 0
}

# Install for user
install_for_user() {
    local shell_rc=""
    local shell_name=""
    
    # Detect shell
    if [[ -n "$BASH_VERSION" ]]; then
        shell_rc="$HOME/.bashrc"
        shell_name="bash"
    elif [[ -n "$ZSH_VERSION" ]]; then
        shell_rc="$HOME/.zshrc"
        shell_name="zsh"
    else
        # Try to detect from SHELL variable
        case "$SHELL" in
            */bash)
                shell_rc="$HOME/.bashrc"
                shell_name="bash"
                ;;
            */zsh)
                shell_rc="$HOME/.zshrc"
                shell_name="zsh"
                ;;
            *)
                echo "Unsupported shell: $SHELL"
                return 1
                ;;
        esac
    fi
    
    # Create directory
    local install_dir="$HOME/.config/tailscale-cli-helpers"
    mkdir -p "$install_dir"
    
    # Copy files
    cp tailscale-ssh-helper.sh "$install_dir/"
    cp test-tailscale-helper.sh "$install_dir/"
    chmod +x "$install_dir/test-tailscale-helper.sh"
    
    # Add to shell rc file
    local source_line="# Tailscale CLI helpers
if [ -f \$HOME/.config/tailscale-cli-helpers/tailscale-ssh-helper.sh ]; then
    . \$HOME/.config/tailscale-cli-helpers/tailscale-ssh-helper.sh
fi"
    
    # Check if already installed
    if grep -q "tailscale-cli-helpers/tailscale-ssh-helper.sh" "$shell_rc" 2>/dev/null; then
        echo "Already installed in $shell_rc"
    else
        echo "" >> "$shell_rc"
        echo "$source_line" >> "$shell_rc"
        echo "Added to $shell_rc"
    fi
    
    echo "Installation complete for $shell_name!"
    echo "To activate immediately, run: source $shell_rc"
}

# Install system-wide
install_system_wide() {
    if [[ $EUID -ne 0 ]]; then
        echo "System-wide installation requires root privileges."
        echo "Please run with sudo: sudo $0 --system"
        return 1
    fi
    
    # Create directory
    local install_dir="/etc/tailscale-cli-helpers"
    mkdir -p "$install_dir"
    
    # Copy files
    cp tailscale-ssh-helper.sh "$install_dir/"
    cp test-tailscale-helper.sh "$install_dir/"
    chmod +x "$install_dir/test-tailscale-helper.sh"
    chmod 644 "$install_dir/tailscale-ssh-helper.sh"
    
    # Create profile.d script
    cat > /etc/profile.d/tailscale-cli-helpers.sh << 'EOF'
# Tailscale CLI helpers
if [ -f /etc/tailscale-cli-helpers/tailscale-ssh-helper.sh ]; then
    . /etc/tailscale-cli-helpers/tailscale-ssh-helper.sh
fi
EOF
    
    chmod 644 /etc/profile.d/tailscale-cli-helpers.sh
    
    echo "System-wide installation complete!"
    echo "New shell sessions will automatically load the helpers."
}

# Uninstall
uninstall() {
    echo "Uninstalling tailscale-cli-helpers..."
    
    # Remove user installation
    if [[ -d "$HOME/.config/tailscale-cli-helpers" ]]; then
        rm -rf "$HOME/.config/tailscale-cli-helpers"
        echo "Removed user installation"
    fi
    
    # Remove from shell rc files
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc_file" ]]; then
            # Create temp file without the source lines
            grep -v "tailscale-cli-helpers/tailscale-ssh-helper.sh" "$rc_file" > "$rc_file.tmp" || true
            mv "$rc_file.tmp" "$rc_file"
            echo "Removed from $rc_file"
        fi
    done
    
    # Remove system-wide installation (requires root)
    if [[ $EUID -eq 0 ]]; then
        if [[ -d "/etc/tailscale-cli-helpers" ]]; then
            rm -rf "/etc/tailscale-cli-helpers"
            echo "Removed system-wide installation"
        fi
        
        if [[ -f "/etc/profile.d/tailscale-cli-helpers.sh" ]]; then
            rm -f "/etc/profile.d/tailscale-cli-helpers.sh"
            echo "Removed from /etc/profile.d"
        fi
    else
        echo "Note: Run with sudo to remove system-wide installation"
    fi
    
    echo "Uninstall complete!"
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install tailscale-cli-helpers for easy SSH access to Tailscale nodes.

OPTIONS:
    --user      Install for current user only (default)
    --system    Install system-wide (requires root)
    --uninstall Remove installation
    --help      Show this help message

EXAMPLES:
    $0              # Install for current user
    $0 --user       # Install for current user
    sudo $0 --system # Install system-wide
    $0 --uninstall  # Remove user installation
    
After installation, use:
    ts <hostname>       # Connect to Tailscale node
    ts user@hostname    # Connect as specific user
    ts -v hostname      # Verbose mode
EOF
}

# Main
main() {
    local mode="user"
    
    # Parse arguments
    case "${1:-}" in
        --user)
            mode="user"
            ;;
        --system)
            mode="system"
            ;;
        --uninstall)
            mode="uninstall"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        "")
            mode="user"
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    
    # Check OS
    local os=$(detect_os)
    echo "Detected OS: $os"
    
    # Check dependencies (except for uninstall)
    if [[ "$mode" != "uninstall" ]]; then
        if ! check_dependencies; then
            exit 1
        fi
    fi
    
    # Execute based on mode
    case "$mode" in
        user)
            install_for_user
            ;;
        system)
            install_system_wide
            ;;
        uninstall)
            uninstall
            ;;
    esac
}

main "$@"