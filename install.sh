#!/usr/bin/env bash
#
# Usage: curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash
#
# This script downloads and runs the setup.sh installer for Tailscale CLI helpers
#

set -euo pipefail

# Configuration
REPO_URL="https://github.com/DigitalCyberSoft/tailscale-cli-helpers"
BRANCH="${BRANCH:-main}"
TEMP_DIR=""

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

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

# Cleanup function
cleanup() {
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Show usage
usage() {
    echo "Tailscale CLI Helpers Remote Installer"
    echo ""
    echo "This script downloads and installs the Tailscale CLI helpers."
    echo ""
    echo "Usage:"
    echo "    curl -fsSL $REPO_URL/raw/$BRANCH/install.sh | bash"
    echo "    curl -fsSL $REPO_URL/raw/$BRANCH/install.sh | bash -s -- [options]"
    echo ""
    echo "Options:"
    echo "    --user       Install for current user only (default)"
    echo "    --system     Install system-wide (requires sudo)"
    echo "    --uninstall  Remove installation"
    echo "    --branch     Use specific branch (default: main)"
    echo "    --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "    # Install for current user"
    echo "    curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash"
    echo ""
    echo "    # Install system-wide"
    echo "    curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | sudo bash -s -- --system"
    echo ""
    echo "    # Uninstall"
    echo "    curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash -s -- --uninstall"
}

# Check for required commands
check_requirements() {
    local missing=()
    
    for cmd in curl tar; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing[*]}"
        echo "Please install the missing commands and try again."
        return 1
    fi
    
    return 0
}

# Download and extract the project
download_project() {
    local archive_url="$REPO_URL/archive/refs/heads/$BRANCH.tar.gz"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    
    print_info "Downloading Tailscale CLI helpers..."
    
    # Download archive
    if ! curl -fsSL "$archive_url" -o "$TEMP_DIR/archive.tar.gz"; then
        print_error "Failed to download project archive"
        return 1
    fi
    
    # Extract archive
    if ! tar -xzf "$TEMP_DIR/archive.tar.gz" -C "$TEMP_DIR"; then
        print_error "Failed to extract project archive"
        return 1
    fi
    
    # Find extracted directory (it will be named tailscale-cli-helpers-$BRANCH)
    local extracted_dir
    extracted_dir=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "tailscale-cli-helpers-*" | head -n1)
    
    if [[ -z "$extracted_dir" ]]; then
        print_error "Failed to find extracted project directory"
        return 1
    fi
    
    echo "$extracted_dir"
}

# Main function
main() {
    local mode="user"
    local action="install"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --system|-s)
                mode="system"
                shift
                ;;
            --user|-u)
                mode="user"
                shift
                ;;
            --uninstall)
                action="uninstall"
                shift
                ;;
            --branch)
                BRANCH="$2"
                shift 2
                ;;
            --help|-h|help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Check requirements
    if ! check_requirements; then
        exit 1
    fi
    
    # For system-wide operations, check if we need sudo
    if [[ "$mode" == "system" ]] && [[ $EUID -ne 0 ]]; then
        print_error "System-wide installation requires root privileges"
        echo "Please run with sudo:"
        echo "  curl -fsSL $REPO_URL/raw/$BRANCH/install.sh | sudo bash -s -- --system"
        exit 1
    fi
    
    # Download project
    local project_dir
    project_dir=$(download_project)
    
    if [[ -z "$project_dir" ]]; then
        print_error "Failed to download project"
        exit 1
    fi
    
    # Change to project directory
    cd "$project_dir"
    
    # Run setup.sh with appropriate arguments
    print_info "Running setup script..."
    
    if [[ "$action" == "uninstall" ]]; then
        if [[ "$mode" == "system" ]]; then
            ./setup.sh --uninstall
        else
            ./setup.sh --uninstall
        fi
    else
        if [[ "$mode" == "system" ]]; then
            ./setup.sh --system
        else
            ./setup.sh --user
        fi
    fi
}

# Run main function with all arguments
main "$@"