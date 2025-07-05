#!/bin/bash
# Test script for tailscale-ssh-helper.sh compatibility

echo "Testing tailscale-ssh-helper.sh compatibility..."
echo

# Detect shell
if [[ -n "$ZSH_VERSION" ]]; then
    echo "Running in zsh version: $ZSH_VERSION"
else
    echo "Running in bash version: $BASH_VERSION"
fi
echo

# Source the functions
echo "Sourcing tailscale-ssh-helper.sh..."
source ./tailscale-ssh-helper.sh
echo

# Test 1: Check if functions are defined
echo "Test 1: Checking if functions are defined..."
if type dcs_ts &>/dev/null; then
    echo "✓ dcs_ts function is defined"
else
    echo "✗ dcs_ts function is NOT defined"
fi

if type ts &>/dev/null; then
    echo "✓ ts function is defined"
else
    echo "✗ ts function is NOT defined"
fi

if type dcs_ssh_copy_id &>/dev/null; then
    echo "✓ dcs_ssh_copy_id function is defined"
else
    echo "✗ dcs_ssh_copy_id function is NOT defined"
fi
echo

# Test 2: Check completion registration
echo "Test 2: Checking completion registration..."
if [[ -n "$ZSH_VERSION" ]]; then
    if compdef -l 2>/dev/null | grep -q "ts"; then
        echo "✓ ts completion is registered in zsh"
    else
        echo "✗ ts completion is NOT registered in zsh"
    fi
else
    if complete -p ts 2>/dev/null; then
        echo "✓ ts completion is registered in bash"
    else
        echo "✗ ts completion is NOT registered in bash"
    fi
fi
echo

# Test 3: Test basic functionality (non-interactive)
echo "Test 3: Testing basic functionality..."
echo "Calling 'ts' without arguments (should show usage):"
ts 2>&1 | head -n 2
echo

echo "All tests completed!"
echo
echo "To fully test the interactive features:"
echo "1. Source the file in your shell: source ./tailscale-ssh-helper.sh"
echo "2. Try tab completion: ts <TAB>"
echo "3. Try connecting to a host: ts user@hostname"