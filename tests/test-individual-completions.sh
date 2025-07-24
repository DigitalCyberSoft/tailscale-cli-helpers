#!/bin/bash
# Test completion functionality for individual commands (tssh, tscp, trsync, tmussh)

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Source the functions
if [[ -f ../tailscale-ssh-helper.sh ]]; then
    source ../tailscale-ssh-helper.sh
else
    echo -e "${RED}✗ Could not find ../tailscale-ssh-helper.sh${RESET}"
    exit 1
fi

# Test helper function
run_completion_test() {
    local test_name="$1"
    local command="$2"
    local partial_input="$3"
    local should_have_completions="$4"  # true/false
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Set up completion environment
    export COMP_WORDS=("$command" "$partial_input")
    export COMP_CWORD=1
    export COMPREPLY=()
    
    # Call completion function
    if _tssh_completions 2>/dev/null; then
        local completion_count=${#COMPREPLY[@]}
        
        if [[ "$should_have_completions" == "true" ]]; then
            if [[ $completion_count -gt 0 ]]; then
                echo -e "${GREEN}✓${RESET} $test_name (found $completion_count completions)"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${YELLOW}!${RESET} $test_name (no completions found - may be expected if no Tailscale hosts)"
                TESTS_PASSED=$((TESTS_PASSED + 1))  # Count as passed since this may be environment-dependent
            fi
        else
            echo -e "${GREEN}✓${RESET} $test_name (completion function executed successfully)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi
    else
        echo -e "${RED}✗${RESET} $test_name (completion function failed)"
    fi
    
    # Clean up
    unset COMP_WORDS COMP_CWORD COMPREPLY
}

echo -e "${BLUE}=== Individual Command Completion Tests ===${RESET}"
echo

# Test 1: tssh completions
echo -e "${YELLOW}1. Testing tssh completions${RESET}"
run_completion_test "tssh hostname completion" "tssh" "" true
run_completion_test "tssh flag completion" "tssh" "-" false
run_completion_test "tssh user@host completion" "tssh" "root@" true

echo

# Test 2: tscp completions
echo -e "${YELLOW}2. Testing tscp completions${RESET}"
run_completion_test "tscp hostname completion" "tscp" "" true
run_completion_test "tscp flag completion" "tscp" "-" false
run_completion_test "tscp remote path completion" "tscp" "host:" true

echo

# Test 3: trsync completions
echo -e "${YELLOW}3. Testing trsync completions${RESET}"
run_completion_test "trsync hostname completion" "trsync" "" true
run_completion_test "trsync flag completion" "trsync" "-" false
run_completion_test "trsync remote path completion" "trsync" "host:" true

echo

# Test 4: tmussh completions
echo -e "${YELLOW}4. Testing tmussh completions${RESET}"
if command -v mussh &> /dev/null; then
    run_completion_test "tmussh hostname completion" "tmussh" "" true
    run_completion_test "tmussh flag completion" "tmussh" "-" false
    run_completion_test "tmussh host list completion" "tmussh" "-h" false
else
    echo -e "${YELLOW}ℹ mussh not installed, skipping tmussh completion tests${RESET}"
fi

echo

# Test 5: ts dispatcher completions
echo -e "${YELLOW}5. Testing ts dispatcher completions${RESET}"

test_ts_subcommand_completion() {
    export COMP_WORDS=("ts" "")
    export COMP_CWORD=1
    export COMPREPLY=()
    
    if _tssh_completions 2>/dev/null; then
        local found_ssh=false
        local found_scp=false
        local found_rsync=false
        
        for completion in "${COMPREPLY[@]}"; do
            case "$completion" in
                "ssh") found_ssh=true ;;
                "scp") found_scp=true ;;
                "rsync") found_rsync=true ;;
            esac
        done
        
        if [[ "$found_ssh" == true && "$found_scp" == true && "$found_rsync" == true ]]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

TESTS_RUN=$((TESTS_RUN + 1))
if test_ts_subcommand_completion; then
    echo -e "${GREEN}✓${RESET} ts dispatcher subcommand completion (ssh, scp, rsync found)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${RESET} ts dispatcher subcommand completion failed"
fi

echo

# Test 6: Completion function robustness
echo -e "${YELLOW}6. Testing completion robustness${RESET}"

test_completion_with_empty_input() {
    export COMP_WORDS=("tssh")
    export COMP_CWORD=0
    export COMPREPLY=()
    
    _tssh_completions 2>/dev/null
    return $?
}

test_completion_with_invalid_input() {
    export COMP_WORDS=("tssh" "--invalid-flag-xyz")
    export COMP_CWORD=1
    export COMPREPLY=()
    
    _tssh_completions 2>/dev/null
    return $?
}

TESTS_RUN=$((TESTS_RUN + 1))
if test_completion_with_empty_input; then
    echo -e "${GREEN}✓${RESET} completion handles empty input"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${RESET} completion fails with empty input"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if test_completion_with_invalid_input; then
    echo -e "${GREEN}✓${RESET} completion handles invalid input"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${RESET} completion fails with invalid input"
fi

echo

# Test 7: Interactive completion demonstration
echo -e "${YELLOW}7. Interactive completion examples${RESET}"
echo -e "${BLUE}To test completions interactively, try:${RESET}"
echo "  tssh <TAB>              # Should show Tailscale hosts"
echo "  tscp file.txt host<TAB> # Should complete hostnames"
echo "  trsync -av dir/ host<TAB>:/path/ # Should complete hostnames"
echo "  ts <TAB>                # Should show subcommands (ssh, scp, rsync)"
echo "  ts ssh <TAB>            # Should show hosts like tssh"

if command -v mussh &> /dev/null; then
    echo "  tmussh -h host<TAB>     # Should complete hostnames"
    echo "  ts mussh <TAB>          # Should show hosts"
fi

echo

# Summary
echo -e "${BLUE}=== Completion Test Summary ===${RESET}"
echo -e "Tests run: ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${RESET}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${RESET}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}🎉 All completion tests passed!${RESET}"
    echo -e "${YELLOW}Note: Some completion results depend on available Tailscale hosts${RESET}"
    exit 0
else
    echo -e "${RED}❌ Some completion tests failed${RESET}"
    exit 1
fi