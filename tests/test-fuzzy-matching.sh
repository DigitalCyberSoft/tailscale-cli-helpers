#!/bin/bash
# Test fuzzy hostname matching functionality

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Check for required commands
check_requirements() {
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}✗ jq is required but not installed${RESET}"
        exit 1
    fi
    
    if ! command -v tailscale >/dev/null 2>&1; then
        echo -e "${RED}✗ tailscale is required but not installed${RESET}"
        exit 1
    fi
}

# Setup test environment
setup() {
    cd "$PROJECT_DIR"
    
    # Check for new binary structure
    if [[ -f "bin/tssh" ]] && [[ -f "lib/tailscale-resolver.sh" ]]; then
        echo -e "${GREEN}✓ Found new modular structure${RESET}"
        
        # Add bin directory to PATH
        export PATH="$PROJECT_DIR/bin:$PATH"
        
        # Source the resolver library
        source "lib/tailscale-resolver.sh" || {
            echo -e "${RED}✗ Could not source lib/tailscale-resolver.sh${RESET}"
            exit 1
        }
    else
        echo -e "${RED}✗ Could not find new modular structure${RESET}"
        exit 1
    fi
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

# Test Levenshtein distance calculation
test_levenshtein() {
    echo -e "\n${BLUE}Testing Levenshtein distance calculation...${RESET}"
    
    # Test exact match
    local distance=$(_levenshtein "test" "test")
    if [[ $distance -eq 0 ]]; then
        report_test "Exact match distance = 0" "PASS"
    else
        report_test "Exact match distance = 0" "FAIL" "Got distance: $distance"
    fi
    
    # Test one character difference
    distance=$(_levenshtein "test" "tests")
    if [[ $distance -eq 1 ]]; then
        report_test "One char difference = 1" "PASS"
    else
        report_test "One char difference = 1" "FAIL" "Got distance: $distance"
    fi
    
    # Test substitution
    distance=$(_levenshtein "kitten" "sitten")
    if [[ $distance -eq 1 ]]; then
        report_test "One substitution = 1" "PASS"
    else
        report_test "One substitution = 1" "FAIL" "Got distance: $distance"
    fi
    
    # Test multiple differences
    distance=$(_levenshtein "saturday" "sunday")
    if [[ $distance -eq 3 ]]; then
        report_test "Multiple differences = 3" "PASS"
    else
        report_test "Multiple differences = 3" "FAIL" "Got distance: $distance"
    fi
}

# Test hostname resolution
test_hostname_resolution() {
    echo -e "\n${BLUE}Testing hostname resolution...${RESET}"
    
    # Create mock Tailscale status
    local mock_status='{
        "Self": {
            "HostName": "myhost",
            "TailscaleIPs": ["100.64.0.1"],
            "DNSName": "myhost.tail1234.ts.net"
        },
        "Peer": {
            "peer1": {
                "HostName": "webserver",
                "TailscaleIPs": ["100.64.0.2"],
                "DNSName": "webserver.tail1234.ts.net",
                "Online": true,
                "OS": "linux"
            },
            "peer2": {
                "HostName": "database",
                "TailscaleIPs": ["100.64.0.3"],
                "DNSName": "database.tail1234.ts.net",
                "Online": false,
                "OS": "linux"
            },
            "peer3": {
                "HostName": "webserver2",
                "TailscaleIPs": ["100.64.0.4"],
                "DNSName": "webserver2.tail1234.ts.net",
                "Online": true,
                "OS": "linux"
            }
        },
        "CurrentTailnet": {"Name": "test"},
        "MagicDNSSuffix": ".tail1234.ts.net"
    }'
    
    # Test exact hostname match
    echo "$mock_status" > /tmp/ts-test-status.json
    local result=$(echo "$mock_status" | jq -r --arg hostname "webserver" '
        (.Peer | to_entries[] | .value | 
            if .HostName == $hostname then
                .TailscaleIPs[0]
            else empty end
        )' | head -1)
    
    if [[ "$result" == "100.64.0.2" ]]; then
        report_test "Exact hostname match" "PASS"
    else
        report_test "Exact hostname match" "FAIL" "Expected 100.64.0.2, got: $result"
    fi
    
    # Test partial hostname match
    local matches=$(echo "$mock_status" | jq -r --arg pattern "web" '
        (.Peer | to_entries[] | .value | 
            if (.HostName | ascii_downcase | contains($pattern | ascii_downcase)) then
                .HostName
            else empty end
        )')
    
    local match_count=$(echo "$matches" | grep -c "webserver")
    if [[ $match_count -eq 2 ]]; then
        report_test "Partial match finds multiple hosts" "PASS"
    else
        report_test "Partial match finds multiple hosts" "FAIL" "Expected 2 matches, got: $match_count"
    fi
}

# Test find_all_matching_hosts function
test_find_all_matching_hosts() {
    echo -e "\n${BLUE}Testing find_all_matching_hosts function...${RESET}"
    
    # Mock tailscale status command
    tailscale() {
        if [[ "$1" == "status" ]] && [[ "$2" == "--json" ]]; then
            cat <<'EOF'
{
    "Self": {
        "HostName": "myhost",
        "TailscaleIPs": ["100.64.0.1"],
        "DNSName": "myhost.tail1234.ts.net",
        "OS": "linux"
    },
    "Peer": {
        "peer1": {
            "HostName": "desktop",
            "TailscaleIPs": ["100.64.0.2"],
            "DNSName": "desktop.tail1234.ts.net",
            "Online": true,
            "OS": "linux"
        },
        "peer2": {
            "HostName": "laptop",
            "TailscaleIPs": ["100.64.0.3"],
            "DNSName": "laptop.tail1234.ts.net",
            "Online": true,
            "OS": "windows"
        },
        "peer3": {
            "HostName": "desktop2",
            "TailscaleIPs": ["100.64.0.4"],
            "DNSName": "desktop2.tail1234.ts.net",
            "Online": false,
            "OS": "linux"
        }
    },
    "CurrentTailnet": {"Name": "test"},
    "MagicDNSSuffix": ".tail1234.ts.net"
}
EOF
        fi
    }
    export -f tailscale
    
    # Test finding hosts with "desk" pattern
    local matches=$(find_all_matching_hosts "desk")
    local match_count=$(echo "$matches" | grep -c "desktop")
    
    if [[ $match_count -eq 2 ]]; then
        report_test "Pattern 'desk' finds desktop hosts" "PASS"
    else
        report_test "Pattern 'desk' finds desktop hosts" "FAIL" "Expected 2 matches, got: $match_count"
    fi
    
    # Test exact match
    matches=$(find_all_matching_hosts "laptop")
    if echo "$matches" | grep -q "100.64.0.3"; then
        report_test "Exact match for 'laptop'" "PASS"
    else
        report_test "Exact match for 'laptop'" "FAIL" "Should find laptop host"
    fi
    
    # Test no matches
    matches=$(find_all_matching_hosts "nonexistent")
    if [[ -z "$matches" ]]; then
        report_test "No matches returns empty" "PASS"
    else
        report_test "No matches returns empty" "FAIL" "Should return empty for nonexistent host"
    fi
    
    # Unset mock function
    unset -f tailscale
}

# Test wildcard pattern matching for mussh
test_wildcard_matching() {
    echo -e "\n${BLUE}Testing wildcard pattern matching...${RESET}"
    
    # Mock tailscale status command
    tailscale() {
        if [[ "$1" == "status" ]] && [[ "$2" == "--json" ]]; then
            cat <<'EOF'
{
    "Self": {
        "HostName": "controller",
        "TailscaleIPs": ["100.64.0.1"],
        "DNSName": "controller.tail1234.ts.net",
        "OS": "linux"
    },
    "Peer": {
        "peer1": {
            "HostName": "web1",
            "TailscaleIPs": ["100.64.0.10"],
            "DNSName": "web1.tail1234.ts.net",
            "Online": true,
            "OS": "linux"
        },
        "peer2": {
            "HostName": "web2",
            "TailscaleIPs": ["100.64.0.11"],
            "DNSName": "web2.tail1234.ts.net",
            "Online": true,
            "OS": "linux"
        },
        "peer3": {
            "HostName": "db1",
            "TailscaleIPs": ["100.64.0.20"],
            "DNSName": "db1.tail1234.ts.net",
            "Online": true,
            "OS": "linux"
        }
    },
    "CurrentTailnet": {"Name": "test"},
    "MagicDNSSuffix": ".tail1234.ts.net"
}
EOF
        fi
    }
    export -f tailscale
    
    # Test wildcard pattern
    local matches=$(find_multiple_hosts_matching "web*")
    local match_count=$(echo "$matches" | grep -c "web")
    
    if [[ $match_count -eq 2 ]]; then
        report_test "Wildcard 'web*' matches web hosts" "PASS"
    else
        report_test "Wildcard 'web*' matches web hosts" "FAIL" "Expected 2 matches, got: $match_count"
    fi
    
    # Test exact pattern without wildcard
    matches=$(find_multiple_hosts_matching "db1")
    if echo "$matches" | grep -q "100.64.0.20"; then
        report_test "Exact pattern 'db1' matches" "PASS"
    else
        report_test "Exact pattern 'db1' matches" "FAIL" "Should find db1 host"
    fi
    
    # Unset mock function
    unset -f tailscale
}

# Main test execution
main() {
    echo -e "${BLUE}=== Tailscale CLI Helpers Fuzzy Matching Tests ===${RESET}"
    
    # Check requirements
    check_requirements
    
    # Setup
    setup
    
    # Run tests
    test_levenshtein
    test_hostname_resolution
    test_find_all_matching_hosts
    test_wildcard_matching
    
    # Summary
    echo -e "\n${BLUE}=== Test Summary ===${RESET}"
    echo -e "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${RESET}"
    echo -e "${RED}Failed: $TESTS_FAILED${RESET}"
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All fuzzy matching tests passed!${RESET}"
        exit 0
    else
        echo -e "\n${RED}Some fuzzy matching tests failed!${RESET}"
        exit 1
    fi
}

# Run main
main "$@"