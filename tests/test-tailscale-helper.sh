#!/bin/bash
# Test script for tailscale-ssh-helper.sh compatibility
# Tests both bash and zsh shells if available

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}Testing tailscale-ssh-helper.sh compatibility...${RESET}"
echo

# Function to find the script
find_script() {
    if [[ -f ../tailscale-ssh-helper.sh ]]; then
        echo "../tailscale-ssh-helper.sh"
    elif [[ -f /usr/share/tailscale-cli-helpers/tailscale-ssh-helper.sh ]]; then
        echo "/usr/share/tailscale-cli-helpers/tailscale-ssh-helper.sh"
    elif [[ -f ~/.config/tailscale-cli-helpers/tailscale-ssh-helper.sh ]]; then
        echo "~/.config/tailscale-cli-helpers/tailscale-ssh-helper.sh"
    else
        echo ""
    fi
}

# Function to test a specific shell
test_shell() {
    local shell_cmd="$1"
    local shell_name="$2"
    
    echo -e "${YELLOW}=== Testing $shell_name ===${RESET}"
    
    # Check if shell is available
    if ! command -v "$shell_cmd" &> /dev/null; then
        echo -e "${RED}✗ $shell_name is not installed${RESET}"
        echo
        return 1
    fi
    
    # Find the script
    local script_path=$(find_script)
    if [[ -z "$script_path" ]]; then
        echo -e "${RED}✗ Could not find tailscale-ssh-helper.sh${RESET}"
        echo
        return 1
    fi
    
    # Create a temporary test script for the shell
    local temp_script=$(mktemp)
    cat > "$temp_script" << 'EOF'
# Source the functions
SCRIPT_PATH="$1"
if [[ -f "$SCRIPT_PATH" ]]; then
    source "$SCRIPT_PATH"
else
    echo "Error: Could not find script at $SCRIPT_PATH"
    exit 1
fi

# Display shell version
if [[ -n "$ZSH_VERSION" ]]; then
    echo "Running in zsh version: $ZSH_VERSION"
else
    echo "Running in bash version: $BASH_VERSION"
fi
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

# Test 4: Test shell compatibility
echo "Test 4: Testing shell compatibility..."
if [[ -n "$ZSH_VERSION" ]]; then
    # Test zsh-specific features
    if [[ -o SH_WORD_SPLIT ]]; then
        echo "✓ SH_WORD_SPLIT is set for bash compatibility"
    else
        echo "! SH_WORD_SPLIT not set (may cause issues)"
    fi
else
    # Test bash-specific features
    if [[ ${BASH_VERSINFO[0]} -ge 4 ]]; then
        echo "✓ Bash version is 4.0 or higher"
    else
        echo "! Bash version is less than 4.0 (may cause issues)"
    fi
fi
echo

echo "Tests completed for this shell!"
EOF
    
    # Run the test in the specified shell
    if [[ "$shell_cmd" == "zsh" ]]; then
        # For zsh, we need to ensure SH_WORD_SPLIT is set
        "$shell_cmd" -c "setopt SH_WORD_SPLIT; source '$temp_script' '$script_path'"
    else
        "$shell_cmd" "$temp_script" "$script_path"
    fi
    
    # Clean up
    rm -f "$temp_script"
    echo
}

# Function to test completion interactively
test_completion() {
    echo -e "${YELLOW}=== Interactive Completion Test ===${RESET}"
    echo "This test requires manual verification:"
    echo
    echo "1. Source the script in your current shell:"
    echo "   source $(find_script)"
    echo
    echo "2. Test tab completion (press TAB after typing):"
    echo "   ts <TAB>              # Should show hostname completions"
    echo "   ts root@<TAB>         # Should show hostnames for root user"
    echo "   ts -<TAB>             # Should show -v flag"
    echo
    echo "3. Test the ts command:"
    echo "   ts                    # Should show usage"
    echo "   ts -v hostname        # Should show verbose output"
    echo
}

# Main test execution
main() {
    echo -e "${BLUE}Multi-shell compatibility test for tailscale-cli-helpers${RESET}"
    echo "======================================================"
    echo
    
    # Check if script exists
    local script_path=$(find_script)
    if [[ -z "$script_path" ]]; then
        echo -e "${RED}✗ Could not find tailscale-ssh-helper.sh in any expected location${RESET}"
        echo "Expected locations:"
        echo "  - ../tailscale-ssh-helper.sh"
        echo "  - /usr/share/tailscale-cli-helpers/tailscale-ssh-helper.sh"
        echo "  - ~/.config/tailscale-cli-helpers/tailscale-ssh-helper.sh"
        exit 1
    fi
    
    echo -e "Found script at: ${GREEN}$script_path${RESET}"
    echo
    
    # Test bash
    test_shell "bash" "Bash"
    
    # Test zsh
    test_shell "zsh" "Zsh"
    
    # Summary
    echo -e "${BLUE}=== Test Summary ===${RESET}"
    echo "✓ Tested script loading and function definition"
    echo "✓ Tested completion registration"
    echo "✓ Tested basic functionality"
    echo "✓ Tested shell-specific compatibility"
    echo
    
    # Interactive test instructions
    test_completion
    
    echo -e "${GREEN}All automated tests completed!${RESET}"
    echo
    echo "For full testing, manually verify tab completion works as expected."
}

# Run main function
main "$@"