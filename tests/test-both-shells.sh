#!/bin/bash
# Comprehensive test script for tailscale-cli-helpers
# Tests both bash and zsh functionality including completions

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"  # 0 for success, 1 for failure
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -n "  Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        local result=0
    else
        local result=1
    fi
    
    if [[ $result -eq $expected_result ]]; then
        echo -e "${GREEN}✓ PASS${RESET}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${RESET}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

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

# Function to test basic functionality
test_basic_functions() {
    local shell_name="$1"
    
    echo -e "${CYAN}  Basic Function Tests:${RESET}"
    
    # Test function existence
    run_test "_tssh_main function exists" "type _tssh_main" 0
    run_test "ts function exists" "type ts" 0
    run_test "tssh_copy_id function exists" "type tssh_copy_id" 0
    
    # Test ts command usage output
    run_test "ts command shows usage" "ts 2>&1 | grep -q 'Usage:'" 0
    run_test "ts -v shows verbose flag" "ts 2>&1 | grep -q '\-v'" 0
    
    # Test that ts fails with no args (expected behavior)
    run_test "ts fails with no args (expected)" "ts" 1
}

# Function to test completion system
test_completion_system() {
    local shell_name="$1"
    
    echo -e "${CYAN}  Completion System Tests:${RESET}"
    
    if [[ "$shell_name" == "bash" ]]; then
        # Test bash completion
        run_test "bash completion registered" "complete -p ts" 0
        run_test "_tssh_completions function exists" "type _tssh_completions" 0
        
        # Test completion function doesn't crash
        run_test "completion function callable" "_tssh_completions" 0
        
    elif [[ "$shell_name" == "zsh" ]]; then
        # Test zsh completion (more complex due to zsh completion system)
        run_test "_tssh_completions function exists" "type _tssh_completions" 0
        run_test "_ts_zsh_completion function exists" "type _ts_zsh_completion" 0
        
        # Test completion function doesn't crash
        run_test "completion function callable" "_tssh_completions" 0
    fi
}

# Function to test helper functions
test_helper_functions() {
    local shell_name="$1"
    
    echo -e "${CYAN}  Helper Function Tests:${RESET}"
    
    # Test internal helper functions exist
    run_test "_dcs_find_host_in_json exists" "type _dcs_find_host_in_json" 0
    run_test "_dcs_find_hosts_matching exists" "type _dcs_find_hosts_matching" 0
    run_test "_dcs_find_multiple_hosts_matching exists" "type _dcs_find_multiple_hosts_matching" 0
    run_test "_dcs_levenshtein exists" "type _dcs_levenshtein" 0
    run_test "_dcs_is_magicdns_enabled exists" "type _dcs_is_magicdns_enabled" 0
    
    # Test Levenshtein function with known inputs
    run_test "Levenshtein distance calculation" "test \$(_dcs_levenshtein 'test' 'test') -eq 0" 0
    run_test "Levenshtein different strings" "test \$(_dcs_levenshtein 'abc' 'def') -gt 0" 0
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
    
    # Create a comprehensive test script for the shell
    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
# Set up the environment
if [[ -n "\$ZSH_VERSION" ]]; then
    # Ensure zsh compatibility
    setopt SH_WORD_SPLIT
    
    # Mock compdef for testing (since completion system may not be fully loaded)
    if ! type compdef &>/dev/null; then
        compdef() { return 0; }
    fi
fi

# Source the main script
SCRIPT_PATH="$script_path"
if [[ -f "\$SCRIPT_PATH" ]]; then
    source "\$SCRIPT_PATH"
else
    echo "Error: Could not find script at \$SCRIPT_PATH"
    exit 1
fi

# Display shell version
if [[ -n "\$ZSH_VERSION" ]]; then
    echo "Running tests in zsh version: \$ZSH_VERSION"
else
    echo "Running tests in bash version: \$BASH_VERSION"
fi
echo

# Source the test functions
$(declare -f run_test)
$(declare -f test_basic_functions)
$(declare -f test_completion_system)
$(declare -f test_helper_functions)

# Initialize counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Export color variables
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
CYAN='\\033[0;36m'
RESET='\\033[0m'

# Run all tests
test_basic_functions "$shell_name"
test_completion_system "$shell_name"
test_helper_functions "$shell_name"

# Show shell-specific results
echo
echo -e "\\${BLUE}$shell_name Results: \\$PASSED_TESTS/\\$TOTAL_TESTS tests passed\\${RESET}"
if [[ \\$FAILED_TESTS -gt 0 ]]; then
    echo -e "\\${RED}\\$FAILED_TESTS tests failed\\${RESET}"
    exit 1
else
    echo -e "\\${GREEN}All tests passed!\\${RESET}"
    exit 0
fi
EOF
    
    # Run the test in the specified shell
    if "$shell_cmd" "$temp_script"; then
        local shell_result=0
    else
        local shell_result=1
    fi
    
    # Clean up
    rm -f "$temp_script"
    
    echo
    return $shell_result
}

# Function to test completion functionality interactively
test_completion_interactive() {
    echo -e "${YELLOW}=== Interactive Completion Tests ===${RESET}"
    echo "These tests require manual verification:"
    echo
    
    local script_path=$(find_script)
    echo -e "${CYAN}Test in Bash:${RESET}"
    echo "  bash"
    echo "  source $script_path"
    echo "  ts <TAB>              # Should show completions"
    echo "  ts root@<TAB>         # Should show hostnames"
    echo "  ts -<TAB>             # Should show -v flag"
    echo "  exit"
    echo
    
    echo -e "${CYAN}Test in Zsh:${RESET}"
    echo "  zsh"
    echo "  source $script_path"
    echo "  ts <TAB>              # Should show completions"
    echo "  ts root@<TAB>         # Should show hostnames" 
    echo "  ts -<TAB>             # Should show -v flag"
    echo "  exit"
    echo
}

# Function to test actual tailscale functionality (requires tailscale)
test_tailscale_integration() {
    echo -e "${YELLOW}=== Tailscale Integration Tests ===${RESET}"
    
    # Check if tailscale is installed
    if ! command -v tailscale &> /dev/null; then
        echo -e "${YELLOW}! Tailscale not installed - skipping integration tests${RESET}"
        return 0
    fi
    
    # Check if tailscale is running
    if ! tailscale status &> /dev/null; then
        echo -e "${YELLOW}! Tailscale not running - skipping integration tests${RESET}"
        return 0
    fi
    
    echo -e "${CYAN}Tailscale Integration:${RESET}"
    
    # Source the script in current shell for testing
    local script_path=$(find_script)
    source "$script_path"
    
    # Test that ts command can query tailscale
    run_test "ts can query tailscale status" "ts nonexistent-host 2>&1 | grep -q 'Tailscale'" 0
    
    echo
}

# Main test execution
main() {
    echo -e "${BLUE}Comprehensive tailscale-cli-helpers Test Suite${RESET}"
    echo "=============================================="
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
    
    # Initialize overall results
    local bash_result=1
    local zsh_result=1
    
    # Test bash
    if test_shell "bash" "Bash"; then
        bash_result=0
    fi
    
    # Test zsh
    if test_shell "zsh" "Zsh"; then
        zsh_result=0
    fi
    
    # Test tailscale integration
    test_tailscale_integration
    
    # Show final results
    echo -e "${BLUE}=== Final Results ===${RESET}"
    
    if [[ $bash_result -eq 0 ]]; then
        echo -e "${GREEN}✓ Bash tests passed${RESET}"
    else
        echo -e "${RED}✗ Bash tests failed${RESET}"
    fi
    
    if [[ $zsh_result -eq 0 ]]; then
        echo -e "${GREEN}✓ Zsh tests passed${RESET}"
    else
        echo -e "${RED}✗ Zsh tests failed${RESET}"
    fi
    
    echo
    
    # Show interactive test instructions
    test_completion_interactive
    
    # Overall success/failure
    if [[ $bash_result -eq 0 && $zsh_result -eq 0 ]]; then
        echo -e "${GREEN}🎉 All automated tests passed!${RESET}"
        echo "Both bash and zsh functionality verified."
        exit 0
    else
        echo -e "${RED}❌ Some tests failed${RESET}"
        exit 1
    fi
}

# Run main function
main "$@"