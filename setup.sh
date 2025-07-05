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
                if [[ "$(uname)" == "Darwin" ]]; then
                    shell_rc="$HOME/.bash_profile"
                else
                    shell_rc="$HOME/.bashrc"
                fi
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
    cp tailscale-functions.sh "$install_dir/"
    cp tailscale-completion.sh "$install_dir/"
    
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
    
    # Create directories
    local install_dir="/usr/share/tailscale-cli-helpers"
    mkdir -p "$install_dir"
    mkdir -p "/etc/profile.d"
    mkdir -p "/etc/bash_completion.d"
    
    # Copy files to /usr/share
    cp tailscale-ssh-helper.sh "$install_dir/"
    cp tailscale-functions.sh "$install_dir/"
    cp tailscale-completion.sh "$install_dir/"
    chmod 644 "$install_dir/tailscale-ssh-helper.sh"
    chmod 644 "$install_dir/tailscale-functions.sh"
    chmod 644 "$install_dir/tailscale-completion.sh"
    
    # Create profile.d script for all shells
    cat > /etc/profile.d/tailscale-cli-helpers.sh << 'EOF'
# Tailscale CLI helpers
if [ -f /usr/share/tailscale-cli-helpers/tailscale-ssh-helper.sh ]; then
    . /usr/share/tailscale-cli-helpers/tailscale-ssh-helper.sh
fi
EOF
    
    chmod 644 /etc/profile.d/tailscale-cli-helpers.sh
    
    # Create bash completion script
    cat > /etc/bash_completion.d/tailscale-cli-helpers << 'EOF'
# Tailscale CLI helpers bash completion
if [ -f /usr/share/tailscale-cli-helpers/tailscale-ssh-helper.sh ]; then
    . /usr/share/tailscale-cli-helpers/tailscale-ssh-helper.sh
fi
EOF
    
    chmod 644 /etc/bash_completion.d/tailscale-cli-helpers
    
    echo "System-wide installation complete!"
    echo "Files installed to: $install_dir"
    echo "Profile script: /etc/profile.d/tailscale-cli-helpers.sh"
    echo "Bash completion: /etc/bash_completion.d/tailscale-cli-helpers"
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
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
        if [[ -f "$rc_file" ]]; then
            # Create temp file without the source lines
            grep -v "tailscale-cli-helpers/tailscale-ssh-helper.sh" "$rc_file" > "$rc_file.tmp" || true
            mv "$rc_file.tmp" "$rc_file"
            echo "Removed from $rc_file"
        fi
    done
    
    # Remove system-wide installation (requires root)
    if [[ $EUID -eq 0 ]]; then
        # Remove new standard locations
        if [[ -d "/usr/share/tailscale-cli-helpers" ]]; then
            rm -rf "/usr/share/tailscale-cli-helpers"
            echo "Removed /usr/share/tailscale-cli-helpers"
        fi
        
        if [[ -f "/etc/profile.d/tailscale-cli-helpers.sh" ]]; then
            rm -f "/etc/profile.d/tailscale-cli-helpers.sh"
            echo "Removed /etc/profile.d/tailscale-cli-helpers.sh"
        fi
        
        if [[ -f "/etc/bash_completion.d/tailscale-cli-helpers" ]]; then
            rm -f "/etc/bash_completion.d/tailscale-cli-helpers"
            echo "Removed /etc/bash_completion.d/tailscale-cli-helpers"
        fi
        
        # Remove old locations for backward compatibility
        if [[ -d "/etc/tailscale-cli-helpers" ]]; then
            rm -rf "/etc/tailscale-cli-helpers"
            echo "Removed old /etc/tailscale-cli-helpers"
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
    --user      Install for current user only
    --system    Install system-wide (requires root)
    --uninstall Remove installation
    --help      Show this help message

EXAMPLES:
    $0              # Install for current user (prompts for system-wide option)
    $0 --user       # Install for current user only
    sudo $0 --system # Install system-wide
    $0 --uninstall  # Remove installation
    
After installation, use:
    ts <hostname>       # Connect to Tailscale node
    ts user@hostname    # Connect as specific user
    ts -v hostname      # Verbose mode
EOF
}

# Main
main() {
    local mode=""
    
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
            # Auto-detect based on privileges
            if [[ $EUID -eq 0 ]]; then
                mode="system"
                echo "Running as root - installing system-wide"
            else
                mode="user"
                echo "Running as user - installing for current user only"
                echo ""
                read -p "Would you like to install system-wide instead? This requires sudo. (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo "Re-running with sudo for system-wide installation..."
                    exec sudo "$0" --system
                fi
            fi
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