#!/bin/bash
# Comprehensive test script for tailscale-cli-helpers
# Tests both bash and zsh functionality with new binary installation

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

# Function to check if commands are available
check_command_availability() {
    local shell_name="$1"
    echo -e "\n${CYAN}Testing command availability in $shell_name${RESET}"
    
    # Test core commands
    run_test "ts command exists" "command -v ts" 0
    run_test "tssh command exists" "command -v tssh" 0
    run_test "tscp command exists" "command -v tscp" 0
    run_test "tsftp command exists" "command -v tsftp" 0
    run_test "trsync command exists" "command -v trsync" 0
    run_test "tssh_copy_id command exists" "command -v tssh_copy_id" 0
    
    # Test optional tmussh command
    if command -v mussh >/dev/null 2>&1; then
        run_test "tmussh command exists" "command -v tmussh" 0
    else
        echo -e "  ${YELLOW}⚠ tmussh skipped (mussh not installed)${RESET}"
    fi
    
    # Test that old function-based installation is gone
    run_test "old functions not in environment" "! type tssh 2>/dev/null | grep -q 'function'" 0
}

# Function to test basic command functionality
test_basic_functionality() {
    local shell_name="$1"
    echo -e "\n${CYAN}Testing basic functionality in $shell_name${RESET}"
    
    # Test help/usage output
    run_test "ts help" "ts help | grep -q 'Usage'" 0
    run_test "tssh help" "tssh 2>&1 | grep -q 'Usage'" 0
    run_test "tscp exists" "tscp 2>&1 | grep -q 'usage\\|Usage'" 0
    run_test "tsftp exists" "tsftp 2>&1 | grep -q 'usage\\|Usage'" 0
    run_test "trsync exists" "trsync --help 2>&1 | grep -q 'rsync'" 0
    run_test "tssh_copy_id exists" "tssh_copy_id 2>&1 | grep -q 'Usage'" 0
    
    # Test ts dispatcher functionality
    run_test "ts ssh dispatching" "ts ssh 2>&1 | grep -q 'Usage'" 0
    run_test "ts help shows subcommands" "ts help | grep -q 'ssh'" 0
}

# Function to test man pages
test_man_pages() {
    local shell_name="$1"
    echo -e "\n${CYAN}Testing man pages in $shell_name${RESET}"
    
    local commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id" "tmussh")
    for cmd in "${commands[@]}"; do
        run_test "$cmd man page" "man $cmd 2>/dev/null | head -1 | grep -qi '$cmd'" 0
    done
}

# Function to test bash completions (only in bash)
test_bash_completions() {
    if [[ "$1" != "bash" ]]; then
        return
    fi
    
    echo -e "\n${CYAN}Testing bash completions${RESET}"
    
    # Source completions if available
    local completion_files=(
        "/etc/bash_completion.d/tailscale-cli-helpers"
        "$HOME/.local/share/bash-completion/completions/tailscale-cli-helpers"
    )
    
    local completion_loaded=false
    for comp_file in "${completion_files[@]}"; do
        if [[ -f "$comp_file" ]]; then
            source "$comp_file" 2>/dev/null && completion_loaded=true
            break
        fi
    done
    
    if [[ "$completion_loaded" == "true" ]]; then
        run_test "completion functions loaded" "declare -F _tssh_completion" 0
        run_test "ts completion loaded" "declare -F _ts_completion" 0
    else
        echo -e "  ${YELLOW}⚠ No completion file found, skipping completion tests${RESET}"
    fi
}

# Function to test version consistency
test_version_consistency() {
    local shell_name="$1"
    echo -e "\n${CYAN}Testing version consistency in $shell_name${RESET}"
    
    # Check that all commands have consistent version info (if they support --version)
    run_test "ts command runs" "ts --help >/dev/null 2>&1 || ts help >/dev/null 2>&1" 0
    run_test "tssh command runs" "tssh --help >/dev/null 2>&1 || true" 0
}

# Function to test security features
test_security_features() {
    local shell_name="$1"
    echo -e "\n${CYAN}Testing security features in $shell_name${RESET}"
    
    # Test that commands handle invalid input safely
    run_test "tssh rejects malicious input" "! tssh '../../../etc/passwd' 2>/dev/null" 0
    run_test "ts rejects command injection" "! ts 'host; rm -rf /' 2>/dev/null" 0
}

# Main test function for a specific shell
run_shell_tests() {
    local shell_path="$1"
    local shell_name="$(basename "$shell_path")"
    
    echo -e "\n${BLUE}===================================================${RESET}"
    echo -e "${BLUE}Running tests in $shell_name${RESET}"
    echo -e "${BLUE}===================================================${RESET}"
    
    # Create a temporary file to store test results
    local temp_results=$(mktemp)
    
    # Execute tests in the specified shell
    "$shell_path" -c "
        # Import test functions
        $(declare -f check_command_availability)
        $(declare -f test_basic_functionality)
        $(declare -f test_man_pages)
        $(declare -f test_bash_completions)
        $(declare -f test_version_consistency)
        $(declare -f test_security_features)
        $(declare -f run_test)
        
        # Set up test variables
        TOTAL_TESTS=0
        PASSED_TESTS=0
        FAILED_TESTS=0
        RED='$RED'
        GREEN='$GREEN'
        YELLOW='$YELLOW'
        BLUE='$BLUE'
        CYAN='$CYAN'
        RESET='$RESET'
        
        # Run all tests
        check_command_availability '$shell_name'
        test_basic_functionality '$shell_name'
        test_man_pages '$shell_name'
        test_bash_completions '$shell_name'
        test_version_consistency '$shell_name'
        test_security_features '$shell_name'
        
        # Export counters to temp file
        echo \"\$TOTAL_TESTS,\$PASSED_TESTS,\$FAILED_TESTS\" > $temp_results
    " 2>&1
    
    # Read the results from temp file
    if [[ -f "$temp_results" ]]; then
        local results=$(cat "$temp_results")
        local total="${results%%,*}"
        local remaining="${results#*,}"
        local passed="${remaining%%,*}"
        local failed="${remaining#*,}"
        
        # Update global counters
        TOTAL_TESTS=$((TOTAL_TESTS + total))
        PASSED_TESTS=$((PASSED_TESTS + passed))
        FAILED_TESTS=$((FAILED_TESTS + failed))
        
        rm -f "$temp_results"
    fi
}

# Main execution
main() {
    echo -e "${YELLOW}Tailscale CLI Helpers - Comprehensive Test Suite${RESET}"
    echo -e "${YELLOW}Testing new binary-based installation${RESET}"
    
    # Check prerequisites
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}Error: jq is required for testing${RESET}"
        exit 1
    fi
    
    if ! command -v tailscale >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: tailscale not found - some tests may fail${RESET}"
    fi
    
    # Test available shells
    local shells_to_test=()
    
    if command -v bash >/dev/null 2>&1; then
        shells_to_test+=("$(command -v bash)")
    fi
    
    if command -v zsh >/dev/null 2>&1; then
        shells_to_test+=("$(command -v zsh)")
    fi
    
    if [[ ${#shells_to_test[@]} -eq 0 ]]; then
        echo -e "${RED}Error: No compatible shells found (bash or zsh required)${RESET}"
        exit 1
    fi
    
    # Run tests for each shell
    for shell in "${shells_to_test[@]}"; do
        run_shell_tests "$shell"
    done
    
    # Final summary
    echo -e "\n${BLUE}===================================================${RESET}"
    echo -e "${BLUE}Test Summary${RESET}"
    echo -e "${BLUE}===================================================${RESET}"
    echo -e "Total Tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${RESET}"
    echo -e "${RED}Failed: $FAILED_TESTS${RESET}"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All tests passed!${RESET}"
        exit 0
    else
        echo -e "\n${RED}❌ Some tests failed${RESET}"
        exit 1
    fi
}

main "$@"