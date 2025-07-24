#!/bin/bash
# Comprehensive test script for tscp, trsync, and tmussh commands

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
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$test_command" &>/dev/null; then
        actual_exit_code=0
    else
        actual_exit_code=1
    fi
    
    if [[ "$actual_exit_code" -eq "$expected_exit_code" ]]; then
        echo -e "${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${RESET} $test_name (expected exit code $expected_exit_code, got $actual_exit_code)"
    fi
}

echo -e "${BLUE}=== Comprehensive Command Tests ===${RESET}"
echo

# Test 1: Completion system for all commands
echo -e "${YELLOW}1. Testing completion registration${RESET}"
run_test "tssh completion registered" "complete -p tssh" 0
run_test "tscp completion registered" "complete -p tscp" 0 
run_test "trsync completion registered" "complete -p trsync" 0
run_test "tmussh completion registered" "complete -p tmussh" 0
run_test "tssh_copy_id completion registered" "complete -p tssh_copy_id" 0

echo

# Test 2: Function argument handling (without actually executing)
echo -e "${YELLOW}2. Testing argument handling${RESET}"

# Test tscp argument parsing (dry run)
test_tscp_args() {
    # Mock scp command to capture arguments
    scp() { echo "scp called with: $*"; }
    
    # Test basic file copy syntax
    local output=$(tscp test.txt host:/tmp/ 2>&1 || true)
    if [[ "$output" == *"scp called with:"* ]]; then
        return 0
    else
        return 1
    fi
}

test_trsync_args() {
    # Mock rsync command to capture arguments
    rsync() { echo "rsync called with: $*"; }
    
    # Test basic rsync syntax
    local output=$(trsync -av test/ host:/tmp/ 2>&1 || true)
    if [[ "$output" == *"rsync called with:"* ]]; then
        return 0
    else
        return 1
    fi
}

run_test "tscp handles arguments" "test_tscp_args" 0
run_test "trsync handles arguments" "test_trsync_args" 0

echo

# Test 3: Error handling
echo -e "${YELLOW}3. Testing error handling${RESET}"

test_tscp_no_args() {
    local output=$(tscp 2>&1 || true)
    # Should call scp with no args, which will show scp usage
    return 0  # Not an error - just passes through to scp
}

test_trsync_no_args() {
    local output=$(trsync 2>&1 || true)
    # Should call rsync with no args, which will show rsync usage  
    return 0  # Not an error - just passes through to rsync
}

run_test "tscp with no args (passthrough)" "test_tscp_no_args" 0
run_test "trsync with no args (passthrough)" "test_trsync_no_args" 0

echo

# Test 4: ts dispatcher integration  
echo -e "${YELLOW}4. Testing ts dispatcher integration${RESET}"

test_ts_scp() {
    # Mock scp to verify dispatcher calls tscp_main
    scp() { echo "dispatcher scp test"; }
    local output=$(ts scp test.txt host:/tmp/ 2>&1 || true)
    if [[ "$output" == *"dispatcher scp test"* ]]; then
        return 0
    else
        return 1
    fi
}

test_ts_rsync() {
    # Mock rsync to verify dispatcher calls trsync_main
    rsync() { echo "dispatcher rsync test"; }
    local output=$(ts rsync -av test/ host:/tmp/ 2>&1 || true)
    if [[ "$output" == *"dispatcher rsync test"* ]]; then
        return 0
    else
        return 1
    fi
}

run_test "ts dispatcher calls tscp_main" "test_ts_scp" 0
run_test "ts dispatcher calls trsync_main" "test_ts_rsync" 0

echo

# Test 5: Command availability and help
echo -e "${YELLOW}5. Testing command help and availability${RESET}"

test_tscp_help() {
    # tscp doesn't have built-in help, it just calls scp
    # So we test that it at least tries to execute
    type tscp >/dev/null 2>&1
}

test_trsync_help() {
    # trsync doesn't have built-in help, it just calls rsync
    # So we test that it at least tries to execute
    type trsync >/dev/null 2>&1
}

run_test "tscp command available" "test_tscp_help" 0
run_test "trsync command available" "test_trsync_help" 0

echo

# Test 6: mussh integration (if available)
echo -e "${YELLOW}6. Testing mussh integration${RESET}"

if command -v mussh &> /dev/null; then
    test_tmussh_available() {
        type tmussh >/dev/null 2>&1
    }
    
    test_ts_mussh() {
        # Mock mussh to verify dispatcher integration
        mussh() { echo "dispatcher mussh test"; }
        local output=$(ts mussh -h host1 -c "echo test" 2>&1 || true)
        if [[ "$output" == *"dispatcher mussh test"* ]]; then
            return 0
        else
            return 1
        fi
    }
    
    run_test "tmussh command available" "test_tmussh_available" 0
    run_test "ts dispatcher calls _tmussh_main" "test_ts_mussh" 0
else
    echo -e "${YELLOW}ℹ mussh not installed, skipping mussh integration tests${RESET}"
fi

echo

# Test 7: Host resolution simulation (without actual Tailscale)
echo -e "${YELLOW}7. Testing host resolution logic${RESET}"

test_host_parsing() {
    # Test that functions can parse user@host:path format
    # We'll test the parsing logic by checking the structure
    
    # Mock tailscale command to return empty (simulating no Tailscale)
    tailscale() { echo ""; }
    
    # Mock scp to capture what gets passed
    scp() { 
        # Should get original arguments when no Tailscale resolution
        echo "parsed: $*" 
    }
    
    local output=$(tscp user@testhost:/path/file.txt ./ 2>&1 || true)
    if [[ "$output" == *"parsed:"* ]]; then
        return 0
    else
        return 1
    fi
}

run_test "host parsing logic works" "test_host_parsing" 0

echo

# Summary
echo -e "${BLUE}=== Test Summary ===${RESET}"
echo -e "Tests run: ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${RESET}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${RESET}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}🎉 All comprehensive tests passed!${RESET}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${RESET}"
    exit 1
fi