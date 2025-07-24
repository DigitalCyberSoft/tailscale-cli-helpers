#!/bin/bash
# Functional behavior tests for tscp, trsync, tsftp, and tmussh commands
# Tests actual command behavior with mocked external dependencies

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
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if $test_function; then
        echo -e "${GREEN}✓${RESET} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${RESET} $test_name" 
    fi
}

echo -e "${BLUE}=== Functional Behavior Tests ===${RESET}"
echo

# Mock external commands for testing
setup_mocks() {
    # Mock scp to capture arguments
    scp() {
        echo "SCP_ARGS: $*" > /tmp/test_scp_output
        return 0
    }
    
    # Mock rsync to capture arguments
    rsync() {
        echo "RSYNC_ARGS: $*" > /tmp/test_rsync_output
        return 0
    }
    
    # Mock mussh to capture arguments
    mussh() {
        echo "MUSSH_ARGS: $*" > /tmp/test_mussh_output
        return 0
    }
    
    # Mock tailscale status to return test data
    tailscale() {
        if [[ "$1" == "status" && "$2" == "--json" ]]; then
            cat << 'EOF'
{
  "Self": {
    "HostName": "local-host",
    "DNSName": "local-host.tailnet.example.ts.net",
    "TailscaleIPs": ["100.64.0.1"],
    "OS": "linux"
  },
  "Peer": {
    "peer1": {
      "HostName": "test-host",
      "DNSName": "test-host.tailnet.example.ts.net",
      "TailscaleIPs": ["100.64.0.2"],
      "OS": "linux",
      "Online": true,
      "Active": true,
      "PublicKey": "key123"
    },
    "peer2": {
      "HostName": "backup-host", 
      "DNSName": "backup-host.tailnet.example.ts.net",
      "TailscaleIPs": ["100.64.0.3"],
      "OS": "linux",
      "Online": false,
      "Active": false,
      "PublicKey": "key456"
    }
  },
  "CurrentTailnet": {
    "MagicDNSEnabled": true
  }
}
EOF
        else
            return 1
        fi
    }
    
    # Mock jq (in case it's not available)
    if ! command -v jq &> /dev/null; then
        jq() {
            # Simple mock that handles basic queries used in the code
            case "$*" in
                *"MagicDNSEnabled"*) echo "true" ;;
                *) echo "mock-jq-output" ;;
            esac
        }
    fi
    
    # Export mocked functions
    export -f scp rsync mussh tailscale
    if ! command -v jq &> /dev/null; then
        export -f jq
    fi
}

cleanup_mocks() {
    rm -f /tmp/test_scp_output /tmp/test_rsync_output /tmp/test_mussh_output
    unset -f scp rsync mussh tailscale
    if ! command -v jq &> /dev/null; then
        unset -f jq
    fi
}

# Test 1: tscp basic functionality
echo -e "${YELLOW}1. Testing tscp functionality${RESET}"

test_tscp_local_to_remote() {
    setup_mocks
    
    # Test copying local file to remote host
    tscp test.txt test-host:/tmp/ >/dev/null 2>&1
    
    if [[ -f /tmp/test_scp_output ]]; then
        local output=$(cat /tmp/test_scp_output)
        # Should resolve test-host to its Tailscale address
        if [[ "$output" =~ "test.txt" && "$output" =~ "test-host" ]]; then
            cleanup_mocks
            return 0
        fi
    fi
    
    cleanup_mocks
    return 1
}

test_tscp_with_user() {
    setup_mocks
    
    # Test copying with specific user
    tscp test.txt user@test-host:/tmp/ >/dev/null 2>&1
    
    local result=1
    if [[ -f /tmp/test_scp_output ]]; then
        local output=$(cat /tmp/test_scp_output)
        if [[ "$output" =~ "test.txt" && "$output" =~ "user@" ]]; then
            result=0
        fi
    fi
    
    cleanup_mocks
    return $result
}

test_tscp_with_options() {
    setup_mocks
    
    # Test tscp with scp options
    tscp -r -P 2222 testdir/ test-host:/tmp/ >/dev/null 2>&1
    
    local result=1
    if [[ -f /tmp/test_scp_output ]]; then
        local output=$(cat /tmp/test_scp_output)
        if [[ "$output" =~ "-r" && "$output" =~ "-P 2222" ]]; then
            result=0
        fi
    fi
    
    cleanup_mocks
    return $result
}

run_test "tscp local to remote" "test_tscp_local_to_remote"
run_test "tscp with user specification" "test_tscp_with_user"
run_test "tscp with options" "test_tscp_with_options"

echo

# Test 2: trsync basic functionality
echo -e "${YELLOW}2. Testing trsync functionality${RESET}"

test_trsync_basic() {
    setup_mocks
    
    # Test basic rsync
    trsync -av testdir/ test-host:/tmp/ >/dev/null 2>&1
    
    local result=1
    if [[ -f /tmp/test_rsync_output ]]; then
        local output=$(cat /tmp/test_rsync_output)
        if [[ "$output" =~ "-av" && "$output" =~ "testdir/" && "$output" =~ "test-host" ]]; then
            result=0
        fi
    fi
    
    cleanup_mocks
    return $result
}

test_trsync_complex_options() {
    setup_mocks
    
    # Test rsync with complex options
    trsync -avz --delete --exclude='*.log' testdir/ test-host:/tmp/ >/dev/null 2>&1
    
    local result=1
    if [[ -f /tmp/test_rsync_output ]]; then
        local output=$(cat /tmp/test_rsync_output)
        if [[ "$output" =~ "--delete" && "$output" =~ "--exclude" ]]; then
            result=0
        fi
    fi
    
    cleanup_mocks
    return $result
}

run_test "trsync basic functionality" "test_trsync_basic"
run_test "trsync with complex options" "test_trsync_complex_options"

echo

# Test 3: tsftp functionality (if sftp available)
echo -e "${YELLOW}3. Testing tsftp functionality${RESET}"

if [[ "$_HAS_SFTP" == "true" ]]; then
    test_tsftp_basic() {
        setup_mocks
        
        # Mock sftp to capture arguments
        sftp() {
            echo "SFTP_ARGS: $*" > /tmp/test_sftp_output
        }
        export -f sftp
        
        # Test basic sftp command
        tsftp test-host >/dev/null 2>&1
        
        local result=1
        if [[ -f /tmp/test_sftp_output ]]; then
            local output=$(cat /tmp/test_sftp_output)
            if [[ "$output" =~ "test-host" ]]; then
                result=0
            fi
        fi
        
        cleanup_mocks
        rm -f /tmp/test_sftp_output
        unset -f sftp
        return $result
    }
    
    test_tsftp_with_user() {
        setup_mocks
        
        # Mock sftp to capture arguments
        sftp() {
            echo "SFTP_ARGS: $*" > /tmp/test_sftp_output
        }
        export -f sftp
        
        # Test sftp with user specification
        tsftp admin@test-host >/dev/null 2>&1
        
        local result=1
        if [[ -f /tmp/test_sftp_output ]]; then
            local output=$(cat /tmp/test_sftp_output)
            if [[ "$output" =~ "admin@" ]]; then
                result=0
            fi
        fi
        
        cleanup_mocks
        rm -f /tmp/test_sftp_output
        unset -f sftp
        return $result
    }
    
    run_test "tsftp basic functionality" "test_tsftp_basic"
    run_test "tsftp with user specification" "test_tsftp_with_user"
else
    echo -e "${YELLOW}ℹ sftp not installed, skipping tsftp functional tests${RESET}"
fi

echo

# Test 4: tmussh functionality (if mussh available)
echo -e "${YELLOW}4. Testing tmussh functionality${RESET}"

if [[ "$_HAS_MUSSH" == "true" ]]; then
    test_tmussh_basic() {
        setup_mocks
        
        # Test basic mussh command
        tmussh -h test-host -c "uptime" >/dev/null 2>&1
        
        local result=1
        if [[ -f /tmp/test_mussh_output ]]; then
            local output=$(cat /tmp/test_mussh_output)
            if [[ "$output" =~ "-h" && "$output" =~ "test-host" && "$output" =~ "uptime" ]]; then
                result=0
            fi
        fi
        
        cleanup_mocks
        return $result
    }
    
    test_tmussh_multiple_hosts() {
        setup_mocks
        
        # Test mussh with multiple hosts
        tmussh -h test-host backup-host -c "whoami" >/dev/null 2>&1
        
        local result=1
        if [[ -f /tmp/test_mussh_output ]]; then
            local output=$(cat /tmp/test_mussh_output)
            if [[ "$output" =~ "test-host" && "$output" =~ "backup-host" ]]; then
                result=0
            fi
        fi
        
        cleanup_mocks
        return $result
    }
    
    run_test "tmussh basic functionality" "test_tmussh_basic"
    run_test "tmussh multiple hosts" "test_tmussh_multiple_hosts"
else
    echo -e "${YELLOW}ℹ mussh not installed, skipping tmussh functional tests${RESET}"
fi

echo

# Test 5: Host resolution behavior
echo -e "${YELLOW}5. Testing host resolution${RESET}"

test_host_resolution_with_tailscale() {
    setup_mocks
    
    # Test that Tailscale hosts get resolved
    tscp test.txt test-host:/tmp/ >/dev/null 2>&1
    
    local result=1
    if [[ -f /tmp/test_scp_output ]]; then
        local output=$(cat /tmp/test_scp_output)
        # Should contain resolved hostname (not IP because MagicDNS is working in mock)
        if [[ "$output" =~ "test-host" ]]; then
            result=0
        fi
    fi
    
    cleanup_mocks
    return $result
}

test_fallback_to_original() {
    setup_mocks
    
    # Mock tailscale to return empty (no Tailscale)
    tailscale() { echo ""; }
    export -f tailscale
    
    # Test with non-Tailscale host (should pass through unchanged)
    tscp test.txt regular-host:/tmp/ >/dev/null 2>&1
    
    local result=1
    if [[ -f /tmp/test_scp_output ]]; then
        local output=$(cat /tmp/test_scp_output)
        if [[ "$output" =~ "regular-host" ]]; then
            result=0
        fi
    fi
    
    cleanup_mocks
    return $result
}

run_test "host resolution with Tailscale" "test_host_resolution_with_tailscale"
run_test "fallback to original hostname" "test_fallback_to_original"

echo

# Summary
echo -e "${BLUE}=== Functional Test Summary ===${RESET}"
echo -e "Tests run: ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${RESET}"
echo -e "Tests failed: ${RED}$((TESTS_RUN - TESTS_PASSED))${RESET}"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo -e "${GREEN}🎉 All functional tests passed!${RESET}"
    echo -e "${YELLOW}Note: Tests used mocked Tailscale data for predictable results${RESET}"
    exit 0
else
    echo -e "${RED}❌ Some functional tests failed${RESET}"
    exit 1
fi