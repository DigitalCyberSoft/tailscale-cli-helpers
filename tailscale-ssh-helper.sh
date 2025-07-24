# Tailscale CLI helpers - Main loader script
# This script loads both the functions and completion components

# Get the directory where this script is located (compatible with both bash and zsh)
if [[ -n "$ZSH_VERSION" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source the main functions
if [[ -f "$SCRIPT_DIR/tailscale-functions.sh" ]]; then
    source "$SCRIPT_DIR/tailscale-functions.sh"
elif [[ -f "/usr/share/tailscale-cli-helpers/tailscale-functions.sh" ]]; then
    source "/usr/share/tailscale-cli-helpers/tailscale-functions.sh"
else
    echo "Warning: Could not find tailscale-functions.sh" >&2
fi

# Source the completion functions
if [[ -f "$SCRIPT_DIR/tailscale-completion.sh" ]]; then
    source "$SCRIPT_DIR/tailscale-completion.sh"
elif [[ -f "/usr/share/tailscale-cli-helpers/tailscale-completion.sh" ]]; then
    source "/usr/share/tailscale-cli-helpers/tailscale-completion.sh"
else
    echo "Warning: Could not find tailscale-completion.sh" >&2
fi

# Source mussh integration if mussh is available
if command -v mussh &> /dev/null; then
    if [[ -f "$SCRIPT_DIR/tailscale-mussh.sh" ]]; then
        source "$SCRIPT_DIR/tailscale-mussh.sh"
    elif [[ -f "/usr/share/tailscale-cli-helpers/tailscale-mussh.sh" ]]; then
        source "/usr/share/tailscale-cli-helpers/tailscale-mussh.sh"
    fi
fi

# Source ts dispatcher (always loaded for packages, optional for manual installs)
if [[ -f "$SCRIPT_DIR/tailscale-ts-dispatcher.sh" ]]; then
    source "$SCRIPT_DIR/tailscale-ts-dispatcher.sh"
elif [[ -f "/usr/share/tailscale-cli-helpers/tailscale-ts-dispatcher.sh" ]]; then
    source "/usr/share/tailscale-cli-helpers/tailscale-ts-dispatcher.sh"
fi