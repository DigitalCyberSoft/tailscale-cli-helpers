#!/bin/bash
# Test script for new tssh, tscp, and tmussh commands

set -e

# Source the functions
source ../tailscale-ssh-helper.sh

echo "=== Testing tssh command ==="
echo "1. Testing tssh is available"
if type tssh >/dev/null 2>&1; then
    echo "✓ tssh command found"
else
    echo "✗ tssh command not found"
    exit 1
fi

echo ""
echo "2. Testing ts alias is available"
if type ts >/dev/null 2>&1; then
    echo "✓ ts alias found"
else
    echo "✗ ts alias not found"
    exit 1
fi

echo ""
echo "3. Testing tscp command"
if type tscp >/dev/null 2>&1; then
    echo "✓ tscp command found"
else
    echo "✗ tscp command not found"
    exit 1
fi

echo ""
echo "4. Testing trsync command"
if type trsync >/dev/null 2>&1; then
    echo "✓ trsync command found"
else
    echo "✗ trsync command not found"
    exit 1
fi

echo ""
echo "5. Testing tsftp command"
if [[ "$_HAS_SFTP" == "true" ]]; then
    if type tsftp >/dev/null 2>&1; then
        echo "✓ tsftp command found (sftp is installed)"
    else
        echo "✗ tsftp command not found (but sftp is installed)"
        exit 1
    fi
else
    echo "ℹ sftp not installed, skipping tsftp test"
fi

echo ""
echo "6. Testing tmussh command"
if [[ "$_HAS_MUSSH" == "true" ]]; then
    if type tmussh >/dev/null 2>&1; then
        echo "✓ tmussh command found (mussh is installed)"
    else
        echo "✗ tmussh command not found (but mussh is installed)"
        exit 1
    fi
else
    echo "ℹ mussh not installed, skipping tmussh test"
fi

echo ""
echo "7. Testing tssh usage output"
tssh_output=$(tssh 2>&1 || true)
if echo "$tssh_output" | grep -q "Usage: tssh"; then
    echo "✓ tssh shows correct usage"
else
    echo "✗ tssh usage incorrect"
    echo "Output: $tssh_output"
    exit 1
fi

echo ""
echo "8. Testing ts dispatcher usage"
ts_output=$(ts 2>&1 || true)
if echo "$ts_output" | grep -q "Usage: ts \[command\]"; then
    echo "✓ ts dispatcher shows correct usage"
else
    echo "✗ ts dispatcher usage incorrect"
    echo "Output: $ts_output"
    exit 1
fi

echo ""
echo "9. Testing ts dispatcher subcommands"
if echo "$ts_output" | grep -q "ssh.*SSH to host"; then
    echo "✓ ts shows ssh subcommand"
else
    echo "✗ ts missing ssh subcommand"
    exit 1
fi

if echo "$ts_output" | grep -q "scp.*Copy files"; then
    echo "✓ ts shows scp subcommand"
else
    echo "✗ ts missing scp subcommand"
    exit 1
fi

if echo "$ts_output" | grep -q "rsync.*Sync files"; then
    echo "✓ ts shows rsync subcommand"
else
    echo "✗ ts missing rsync subcommand"
    exit 1
fi

if [[ "$_HAS_SFTP" == "true" ]]; then
    if echo "$ts_output" | grep -q "sftp.*Interactive file transfer"; then
        echo "✓ ts shows sftp subcommand"
    else
        echo "✗ ts missing sftp subcommand"
        exit 1
    fi
fi

echo ""
echo "10. Testing command exports"
if declare -f tssh_main >/dev/null; then
    echo "✓ tssh_main function exported"
else
    echo "✗ tssh_main function not exported"
    exit 1
fi

if declare -f tscp_main >/dev/null; then
    echo "✓ tscp_main function exported"
else
    echo "✗ tscp_main function not exported"
    exit 1
fi

if declare -f trsync_main >/dev/null; then
    echo "✓ trsync_main function exported"
else
    echo "✗ trsync_main function not exported"
    exit 1
fi

if [[ "$_HAS_SFTP" == "true" ]]; then
    if declare -f tsftp_main >/dev/null; then
        echo "✓ tsftp_main function exported"
    else
        echo "✗ tsftp_main function not exported"
        exit 1
    fi
fi

echo ""
echo "=== All tests passed! ==="