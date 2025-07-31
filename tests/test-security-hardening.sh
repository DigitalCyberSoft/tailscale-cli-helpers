#!/bin/bash
# Security hardening test script for tailscale-cli-helpers
# Tests all security improvements and validates they prevent vulnerabilities

# Note: Not using 'set -e' to allow test failures without script exit

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TEMP_DIR="/tmp/tailscale-cli-helpers-security-test-$$"
TEST_LOG="$TEST_TEMP_DIR/security-test.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Setup test environment
setup_test_env() {
    echo -e "${BLUE}Setting up test environment...${RESET}"
    mkdir -p "$TEST_TEMP_DIR"
    cd "$PROJECT_DIR"
    
    # Check for new binary structure
    if [[ -f "bin/tssh" ]] && [[ -f "lib/tailscale-resolver.sh" ]]; then
        echo "Testing new modular structure..."
        
        # Add bin directory to PATH for testing
        export PATH="$PROJECT_DIR/bin:$PATH"
        
        # Source the resolver library to test validation functions
        source "lib/tailscale-resolver.sh" 2>/dev/null || {
            echo -e "${RED}ERROR: Failed to source tailscale-resolver.sh${RESET}"
            exit 1
        }
        
        # Test if our security functions are available
        if ! declare -f _validate_hostname >/dev/null 2>&1; then
            echo -e "${RED}ERROR: Security functions not loaded properly${RESET}"
            exit 1
        fi
        echo "Security functions loaded successfully"
    else
        echo -e "${RED}ERROR: New modular structure not found in $(pwd)${RESET}"
        echo "Expected bin/tssh and lib/tailscale-resolver.sh"
        exit 1
    fi
    
    # Create test log
    touch "$TEST_LOG"
}

# Cleanup test environment
cleanup_test_env() {
    echo -e "${BLUE}Cleaning up test environment...${RESET}"
    rm -rf "$TEST_TEMP_DIR"
}

# Test result reporter
report_test() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    ((TESTS_TOTAL++))
    
    if [[ "$result" == "PASS" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}✓ $test_name${RESET}"
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}✗ $test_name${RESET}"
        if [[ -n "$details" ]]; then
            echo -e "    ${YELLOW}Details: $details${RESET}"
        fi
    fi
}

# Test hostname validation
test_hostname_validation() {
    echo -e "\n${BLUE}Testing hostname validation...${RESET}"
    
    # Valid hostnames
    local valid_hostnames=(
        "server1"
        "web-server"
        "db_server"
        "host.example.com"
        "192.168.1.1"
        "user@server"
        "root@web-01"
    )
    
    for hostname in "${valid_hostnames[@]}"; do
        if _validate_hostname "$hostname"; then
            report_test "Valid hostname: $hostname" "PASS"
        else
            report_test "Valid hostname: $hostname" "FAIL" "Should accept valid hostname"
        fi
    done
    
    # Invalid hostnames
    local invalid_hostnames=(
        "server1; rm -rf /"
        "host\$(whoami)"
        "server\`id\`"
        "host&command"
        "server|pipe"
        "../../../etc/passwd"
        "host\ncommand"
        "server>output"
        "host<input"
        "a_very_long_hostname_that_exceeds_the_maximum_allowed_length_of_253_characters_which_should_be_rejected_by_the_validation_function_to_prevent_buffer_overflow_attacks_and_other_security_issues_that_could_arise_from_processing_excessively_long_hostnames_in_the_system_aaaaaaaaaaaaa"
    )
    
    for hostname in "${invalid_hostnames[@]}"; do
        if ! _validate_hostname "$hostname"; then
            report_test "Invalid hostname rejected: ${hostname:0:30}..." "PASS"
        else
            report_test "Invalid hostname rejected: ${hostname:0:30}..." "FAIL" "Should reject malicious input"
        fi
    done
}

# Test command injection prevention
test_command_injection() {
    echo -e "\n${BLUE}Testing command injection prevention...${RESET}"
    
    # Test various command injection attempts
    local injection_attempts=(
        "host; echo INJECTED"
        "host && echo INJECTED"
        "host || echo INJECTED"
        "host \$(echo INJECTED)"
        "host \`echo INJECTED\`"
        "host | echo INJECTED"
        "host > /tmp/injected"
        "host < /etc/passwd"
        "host & echo INJECTED"
        "host\necho INJECTED"
        "host\r\necho INJECTED"
    )
    
    for attempt in "${injection_attempts[@]}"; do
        # Try to use the attempt as a hostname with tssh
        output=$(bin/tssh "$attempt" 2>&1 || true)
        
        # Check if injection was prevented
        if [[ "$output" != *"INJECTED"* ]] && [[ "$output" != *"echo"* ]]; then
            report_test "Command injection blocked: ${attempt:0:30}..." "PASS"
        else
            report_test "Command injection blocked: ${attempt:0:30}..." "FAIL" "Injection not prevented"
        fi
    done
}

# Test path traversal prevention
test_path_traversal() {
    echo -e "\n${BLUE}Testing path traversal prevention...${RESET}"
    
    local traversal_attempts=(
        "../../../etc/passwd"
        "..\\..\\..\\windows\\system32"
        "....//....//....//etc//passwd"
        "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd"
        "..%252f..%252f..%252fetc%252fpasswd"
    )
    
    for attempt in "${traversal_attempts[@]}"; do
        if ! _validate_hostname "$attempt"; then
            report_test "Path traversal blocked: ${attempt:0:30}..." "PASS"
        else
            report_test "Path traversal blocked: ${attempt:0:30}..." "FAIL" "Should reject path traversal"
        fi
    done
}

# Test JSON validation
test_json_validation() {
    echo -e "\n${BLUE}Testing JSON validation...${RESET}"
    
    # Valid JSON structure (minimal Tailscale status)
    local valid_json='{
        "Self": {"HostName": "test", "TailscaleIPs": ["100.64.0.1"]},
        "Peer": {},
        "CurrentTailnet": {"Name": "test"}
    }'
    
    if _validate_tailscale_json "$valid_json"; then
        report_test "Valid JSON accepted" "PASS"
    else
        report_test "Valid JSON accepted" "FAIL" "Should accept valid Tailscale JSON"
    fi
    
    # Invalid JSON structures
    local invalid_jsons=(
        '{"malformed": json}'
        '{"Self": "not an object"}'
        '{"missing": "required fields"}'
        'not json at all'
        '{"Self": {"HostName": "test; echo INJECTED"}}'
    )
    
    for json in "${invalid_jsons[@]}"; do
        if ! _validate_tailscale_json "$json" 2>/dev/null; then
            report_test "Invalid JSON rejected: ${json:0:30}..." "PASS"
        else
            report_test "Invalid JSON rejected: ${json:0:30}..." "FAIL" "Should reject invalid JSON"
        fi
    done
}

# Test environment variable safety
test_env_safety() {
    echo -e "\n${BLUE}Testing environment variable safety...${RESET}"
    
    # Set potentially dangerous environment variables
    export PATH="/tmp/malicious:$PATH"
    export LD_PRELOAD="/tmp/evil.so"
    export BASH_ENV="/tmp/evil.sh"
    
    # Commands should still work safely
    if bin/tssh --help >/dev/null 2>&1; then
        report_test "Commands work with modified environment" "PASS"
    else
        report_test "Commands work with modified environment" "FAIL" "Should handle modified env safely"
    fi
    
    # Clean up
    unset LD_PRELOAD
    unset BASH_ENV
}

# Test handling of special characters
test_special_characters() {
    echo -e "\n${BLUE}Testing special character handling...${RESET}"
    
    local special_inputs=(
        "host'name"
        'host"name'
        "host\$name"
        "host\*name"
        "host?name"
        "host[name]"
        "host{name}"
        "host\\name"
    )
    
    for input in "${special_inputs[@]}"; do
        # These should be properly escaped/handled
        output=$(bin/tssh "$input" 2>&1 || true)
        
        # Check that no shell expansion occurred
        if [[ "$output" != *"syntax error"* ]] && [[ "$output" != *"unexpected"* ]]; then
            report_test "Special chars handled: $input" "PASS"
        else
            report_test "Special chars handled: $input" "FAIL" "Improper handling"
        fi
    done
}

# Test resource limits
test_resource_limits() {
    echo -e "\n${BLUE}Testing resource limits...${RESET}"
    
    # Test with very long hostname (should be rejected)
    local long_hostname=$(python3 -c "print('a' * 300)")
    if ! _validate_hostname "$long_hostname"; then
        report_test "Long hostname rejected (300 chars)" "PASS"
    else
        report_test "Long hostname rejected (300 chars)" "FAIL" "Should enforce length limits"
    fi
    
    # Test with maximum allowed length (253 chars)
    local max_hostname=$(python3 -c "print('a' * 253)")
    if _validate_hostname "$max_hostname"; then
        report_test "Max length hostname accepted (253 chars)" "PASS"
    else
        report_test "Max length hostname accepted (253 chars)" "FAIL" "Should accept max valid length"
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}=== Tailscale CLI Helpers Security Test Suite ===${RESET}"
    echo -e "${BLUE}Testing security hardening implementations...${RESET}"
    
    # Setup
    setup_test_env
    
    # Run all security tests
    test_hostname_validation
    test_command_injection
    test_path_traversal
    test_json_validation
    test_env_safety
    test_special_characters
    test_resource_limits
    
    # Summary
    echo -e "\n${BLUE}=== Test Summary ===${RESET}"
    echo -e "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${RESET}"
    echo -e "${RED}Failed: $TESTS_FAILED${RESET}"
    
    # Cleanup
    cleanup_test_env
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All security tests passed!${RESET}"
        exit 0
    else
        echo -e "\n${RED}Some security tests failed!${RESET}"
        exit 1
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_test_env EXIT

# Run main
main "$@"