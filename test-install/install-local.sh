#!/usr/bin/env bash
#
# Local test version of install.sh
# This script is for testing the installation process locally
#

set -euo pipefail

# Get the parent directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# Show usage
usage() {
    echo "Tailscale CLI Helpers Local Test Installer"
    echo ""
    echo "This script tests the installation process using local files."
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "    --user       Install for current user only (default)"
    echo "    --system     Install system-wide (requires sudo)"
    echo "    --uninstall  Remove installation"
    echo "    --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "    $0              # Install for current user"
    echo "    $0 --user       # Install for current user"
    echo "    sudo $0 --system    # Install system-wide"
    echo "    $0 --uninstall      # Remove user installation"
    echo "    sudo $0 --uninstall # Remove system installation"
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
    
    # For system-wide operations, check if we need sudo
    if [[ "$mode" == "system" ]] && [[ $EUID -ne 0 ]]; then
        print_error "System-wide installation requires root privileges"
        echo "Please run with sudo: sudo $0 --system"
        exit 1
    fi
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Run setup.sh with appropriate arguments
    print_info "Running setup script from local project..."
    
    if [[ "$action" == "uninstall" ]]; then
        ./setup.sh --uninstall
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