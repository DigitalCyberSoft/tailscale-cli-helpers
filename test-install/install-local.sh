#!/bin/bash
# One-line installer for tailscale-cli-helpers
# Usage: curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash
# Options: curl -fsSL ... | bash -s -- --system    (for system-wide install)
#          curl -fsSL ... | bash -s -- --uninstall (to remove)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# GitHub repository details
REPO_URL="https://github.com/DigitalCyberSoft/tailscale-cli-helpers"
RAW_URL="/home/user/tailscale-cli-helpers"

# Temp directory for download
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo -e "${BLUE}Tailscale CLI Helpers Installer${RESET}"
echo "==============================="
echo

# Parse arguments
INSTALL_MODE="user"
INSTALL_DISPATCHER="prompt"
UNINSTALL=false

for arg in "$@"; do
    case $arg in
        --system)
            INSTALL_MODE="system"
            INSTALL_DISPATCHER="yes"
            ;;
        --uninstall)
            UNINSTALL=true
            ;;
        --no-dispatcher)
            INSTALL_DISPATCHER="no"
            ;;
        --with-dispatcher)
            INSTALL_DISPATCHER="yes"
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "OPTIONS:"
            echo "    --system           Install system-wide (requires sudo)"
            echo "    --uninstall        Remove installation"
            echo "    --with-dispatcher  Install ts dispatcher (default: prompt)"
            echo "    --no-dispatcher    Skip ts dispatcher"
            echo "    --help             Show this help"
            echo
            echo "EXAMPLES:"
            echo "    # Quick install (prompts for ts dispatcher)"
            echo "    curl -fsSL $RAW_URL/install.sh | bash"
            echo
            echo "    # System-wide install"
            echo "    curl -fsSL $RAW_URL/install.sh | sudo bash -s -- --system"
            echo
            echo "    # Install without ts dispatcher"
            echo "    curl -fsSL $RAW_URL/install.sh | bash -s -- --no-dispatcher"
            echo
            echo "    # Uninstall"
            echo "    curl -fsSL $RAW_URL/install.sh | bash -s -- --uninstall"
            exit 0
            ;;
    esac
done

# Function to download files
download_file() {
    local url="$1"
    local dest="$2"
    local optional="${3:-false}"
    echo "  Downloading $(basename "$dest")..."
    if ! cp "/home/user/tailscale-cli-helpers/$(basename "$dest")" "$dest"; then
        if [[ "$optional" == "true" ]]; then
            echo -e "${YELLOW}    Warning: Optional file not available${RESET}"
            return 0
        else
            echo -e "${RED}Error: Failed to download $url${RESET}"
            exit 1
        fi
    fi
}

# Function to check dependencies
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
        echo -e "${YELLOW}Warning: Missing dependencies: ${missing[*]}${RESET}"
        echo "Please install them for full functionality:"
        echo "  Fedora/RHEL: sudo dnf install jq tailscale"
        echo "  Ubuntu/Debian: sudo apt-get install jq tailscale"
        echo "  macOS: brew install jq tailscale"
        echo
        read -p "Continue anyway? [y/N]: " continue_install
        if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to perform uninstall
uninstall() {
    echo -e "${YELLOW}Uninstalling tailscale-cli-helpers...${RESET}"
    
    # Remove user installation
    if [[ -d "$HOME/.config/tailscale-cli-helpers" ]]; then
        rm -rf "$HOME/.config/tailscale-cli-helpers"
        echo "  Removed user installation"
    fi
    
    # Remove from shell rc files
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
        if [[ -f "$rc_file" ]]; then
            # Create temp file without the source lines
            grep -v "tailscale-cli-helpers/tailscale-ssh-helper.sh" "$rc_file" > "$rc_file.tmp" 2>/dev/null || cp "$rc_file" "$rc_file.tmp"
            mv "$rc_file.tmp" "$rc_file"
            echo "  Cleaned $rc_file"
        fi
    done
    
    # Remove system-wide installation (if running as root)
    if [[ $EUID -eq 0 ]]; then
        if [[ -d "/usr/share/tailscale-cli-helpers" ]]; then
            rm -rf "/usr/share/tailscale-cli-helpers"
            echo "  Removed /usr/share/tailscale-cli-helpers"
        fi
        
        if [[ -f "/etc/profile.d/tailscale-cli-helpers.sh" ]]; then
            rm -f "/etc/profile.d/tailscale-cli-helpers.sh"
            echo "  Removed /etc/profile.d/tailscale-cli-helpers.sh"
        fi
        
        if [[ -f "/etc/bash_completion.d/tailscale-cli-helpers" ]]; then
            rm -f "/etc/bash_completion.d/tailscale-cli-helpers"
            echo "  Removed bash completion"
        fi
    else
        echo -e "${YELLOW}  Note: Run with sudo to remove system-wide installation${RESET}"
    fi
    
    echo -e "${GREEN}Uninstall complete!${RESET}"
    echo "Please restart your shell or source your shell config to complete removal."
    exit 0
}

# Function to install for user
install_user() {
    echo -e "${GREEN}Installing for current user...${RESET}"
    
    # Detect shell
    local shell_rc=""
    local shell_name=""
    
    if [[ -n "$BASH_VERSION" ]]; then
        shell_rc="$HOME/.bashrc"
        shell_name="bash"
    elif [[ -n "$ZSH_VERSION" ]]; then
        shell_rc="$HOME/.zshrc"
        shell_name="zsh"
    else
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
                echo -e "${RED}Error: Unsupported shell: $SHELL${RESET}"
                exit 1
                ;;
        esac
    fi
    
    # Create directory
    local install_dir="$HOME/.config/tailscale-cli-helpers"
    mkdir -p "$install_dir"
    
    # Download files
    echo "Downloading files to $install_dir..."
    download_file "$RAW_URL/tailscale-ssh-helper.sh" "$install_dir/tailscale-ssh-helper.sh"
    download_file "$RAW_URL/tailscale-functions.sh" "$install_dir/tailscale-functions.sh"
    download_file "$RAW_URL/tailscale-completion.sh" "$install_dir/tailscale-completion.sh"
    download_file "$RAW_URL/tailscale-mussh.sh" "$install_dir/tailscale-mussh.sh" "true"
    
    # Handle ts dispatcher
    if [[ "$INSTALL_DISPATCHER" == "prompt" ]]; then
        echo
        echo "The 'ts' command can work as a dispatcher for all tailscale operations:"
        echo "  ts hostname        # SSH (default)"
        echo "  ts scp file host:/ # File copy"
        echo "  ts rsync -av dir/ host:/ # Directory sync"
        echo
        read -p "Install ts dispatcher? [Y/n]: " install_dispatcher
        install_dispatcher=${install_dispatcher:-Y}
        
        if [[ "$install_dispatcher" =~ ^[Yy]$ ]]; then
            INSTALL_DISPATCHER="yes"
        else
            INSTALL_DISPATCHER="no"
        fi
    fi
    
    if [[ "$INSTALL_DISPATCHER" == "yes" ]]; then
        download_file "$RAW_URL/tailscale-ts-dispatcher.sh" "$install_dir/tailscale-ts-dispatcher.sh"
        echo -e "${GREEN}  ✓ ts dispatcher will be installed${RESET}"
    else
        echo -e "${YELLOW}  ✗ ts dispatcher skipped (you can still use tssh, tscp, trsync, tmussh directly)${RESET}"
    fi
    
    # Add to shell rc file
    local source_line="# Tailscale CLI helpers
if [ -f \$HOME/.config/tailscale-cli-helpers/tailscale-ssh-helper.sh ]; then
    . \$HOME/.config/tailscale-cli-helpers/tailscale-ssh-helper.sh
fi"
    
    # Check if already installed
    if grep -q "tailscale-cli-helpers/tailscale-ssh-helper.sh" "$shell_rc" 2>/dev/null; then
        echo -e "${YELLOW}Already installed in $shell_rc${RESET}"
    else
        echo "" >> "$shell_rc"
        echo "$source_line" >> "$shell_rc"
        echo "Added to $shell_rc"
    fi
    
    echo
    echo -e "${GREEN}Installation complete for $shell_name!${RESET}"
    echo -e "To activate immediately, run: ${BLUE}source $shell_rc${RESET}"
}

# Function to install system-wide
install_system() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: System-wide installation requires root privileges.${RESET}"
        echo "Please run: curl -fsSL $RAW_URL/install.sh | sudo bash -s -- --system"
        exit 1
    fi
    
    echo -e "${GREEN}Installing system-wide...${RESET}"
    
    # Create directories
    local install_dir="/usr/share/tailscale-cli-helpers"
    mkdir -p "$install_dir"
    mkdir -p "/etc/profile.d"
    mkdir -p "/etc/bash_completion.d"
    
    # Download files
    echo "Downloading files to $install_dir..."
    download_file "$RAW_URL/tailscale-ssh-helper.sh" "$install_dir/tailscale-ssh-helper.sh"
    download_file "$RAW_URL/tailscale-functions.sh" "$install_dir/tailscale-functions.sh"
    download_file "$RAW_URL/tailscale-completion.sh" "$install_dir/tailscale-completion.sh"
    download_file "$RAW_URL/tailscale-mussh.sh" "$install_dir/tailscale-mussh.sh" "true"
    download_file "$RAW_URL/tailscale-ts-dispatcher.sh" "$install_dir/tailscale-ts-dispatcher.sh"
    
    # Set permissions
    chmod 644 "$install_dir"/*.sh
    
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
    
    echo
    echo -e "${GREEN}System-wide installation complete!${RESET}"
    echo "Files installed to: $install_dir"
    echo "Profile script: /etc/profile.d/tailscale-cli-helpers.sh"
    echo "Bash completion: /etc/bash_completion.d/tailscale-cli-helpers"
    echo "New shell sessions will automatically load the helpers."
}

# Main execution
if [[ "$UNINSTALL" == true ]]; then
    uninstall
fi

echo "Checking dependencies..."
check_dependencies

if [[ "$INSTALL_MODE" == "system" ]]; then
    install_system
else
    install_user
fi

echo
echo -e "${GREEN}🎉 Installation successful!${RESET}"
echo
echo "Available commands:"
echo -e "  ${BLUE}tssh hostname${RESET}             # SSH to Tailscale host"
echo -e "  ${BLUE}tscp file.txt host:/path${RESET}  # Copy files"
echo -e "  ${BLUE}trsync -av dir/ host:/${RESET}    # Sync directories"
if command -v mussh &> /dev/null; then
    echo -e "  ${BLUE}tmussh -h host1 host2 -c cmd${RESET} # Parallel SSH"
fi
if [[ "$INSTALL_DISPATCHER" == "yes" ]] || [[ "$INSTALL_MODE" == "system" ]]; then
    echo -e "  ${BLUE}ts hostname${RESET}               # Dispatcher (SSH by default)"
    echo -e "  ${BLUE}ts scp file host:/path${RESET}    # Dispatcher for file copy"
    echo -e "  ${BLUE}ts rsync -av dir/ host:/${RESET}  # Dispatcher for sync"
fi
echo
echo -e "For more information: ${BLUE}$REPO_URL${RESET}"