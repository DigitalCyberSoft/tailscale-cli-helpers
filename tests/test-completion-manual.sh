#!/bin/bash
# Manual completion test script
# This script demonstrates completion functionality working

echo "=== Manual Completion Test ==="
echo

# Source the main script
if [[ -f ../tailscale-ssh-helper.sh ]]; then
    source ../tailscale-ssh-helper.sh
else
    echo "Error: Could not find ../tailscale-ssh-helper.sh"
    exit 1
fi

echo "✓ Script sourced successfully"
echo

# Test bash completion is registered
if complete -p ts &>/dev/null; then
    echo "✓ Bash completion is registered for 'ts' command"
    complete -p ts
else
    echo "✗ Bash completion is NOT registered"
fi
echo

# Test completion function exists
if type _tssh_completions &>/dev/null; then
    echo "✓ Completion function _tssh_completions exists"
else
    echo "✗ Completion function is missing"
    exit 1
fi
echo

# Test that completion function can be called without errors
echo "Testing completion function..."
export COMP_WORDS=("ts" "")
export COMP_CWORD=1
if _tssh_completions 2>/dev/null; then
    echo "✓ Completion function executes without errors"
else
    echo "✗ Completion function has errors"
fi
echo

# Test flag completion
echo "Testing flag completion..."
export COMP_WORDS=("ts" "-")
export COMP_CWORD=1
_tssh_completions 2>/dev/null
if [[ ${#COMPREPLY[@]} -gt 0 ]]; then
    echo "✓ Flag completion returned results: ${COMPREPLY[*]}"
else
    echo "! No flag completions found (this is OK if tailscale isn't running)"
fi
echo

# Show ts command functionality
echo "Testing ts command functionality:"
echo "$ ts"
ts
echo

echo "✓ Manual completion test completed!"
echo
echo "To test interactively:"
echo "1. Make sure you've sourced the script: source ../tailscale-ssh-helper.sh"
echo "2. Try typing: ts <TAB>"
echo "3. Try typing: ts root@<TAB>"
echo "4. Try typing: ts -<TAB>"