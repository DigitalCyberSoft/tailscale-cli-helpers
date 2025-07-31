#!/usr/bin/env bash
#
# common.sh - Shared utilities for Tailscale CLI helpers
#

# Version information
TAILSCALE_CLI_HELPERS_VERSION="0.2.3"

# Common help and version handling
handle_common_args() {
    local script_name="$1"
    local script_description="$2"
    
    for arg in "$@"; do
        case "$arg" in
            --version|-V)
                echo "$script_name $TAILSCALE_CLI_HELPERS_VERSION"
                exit 0
                ;;
            --help|-h)
                show_help_for_script "$script_name" "$script_description"
                exit 0
                ;;
        esac
    done
}

# Script-specific help function (to be overridden)
show_help_for_script() {
    local script_name="$1"
    local script_description="$2"
    
    echo "$script_name - $script_description"
    echo ""
    echo "Usage: $script_name [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -V, --version    Show version information"
}

# Check for early help/version args before hostname resolution
check_early_args() {
    for arg in "$@"; do
        case "$arg" in
            --version|-V|--help|-h)
                return 0  # Found early arg
                ;;
        esac
    done
    return 1  # No early args found
}