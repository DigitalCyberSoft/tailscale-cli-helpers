#!/bin/bash
# Test the installer locally by copying files instead of downloading

set -e

# Copy the installer and modify it for local testing
cp /home/user/tailscale-cli-helpers/install.sh test-install/install-local.sh

# Replace the download function with local copy
sed -i 's|curl -fsSL "$url" -o "$dest"|cp "/home/user/tailscale-cli-helpers/$(basename "$dest")" "$dest"|g' test-install/install-local.sh

# Replace the RAW_URL with local path
sed -i 's|RAW_URL=".*"|RAW_URL="/home/user/tailscale-cli-helpers"|g' test-install/install-local.sh

echo "Modified installer created for local testing"
echo "You can now run: cd test-install && ./install-local.sh --help"