#!/bin/bash
# Test jump host handling (-J, -o ProxyJump, rsync -e, mussh -p) across the
# helpers and the ts dispatcher

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PROJECT_DIR/bin"

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
}

# Setup test environment: a tailscale shim serving a synthetic tailnet, and
# shims for ssh, scp, sftp, rsync, ssh-copy-id and mussh that print the
# arguments they were run with instead of connecting
setup() {
    TEST_DIR=$(mktemp -d)
    trap 'rm -rf "$TEST_DIR"' EXIT
    mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home/.ssh"
    touch "$TEST_DIR/home/.ssh/known_hosts"

    cat > "$TEST_DIR/status.json" <<'EOF'
{
    "Self": {
        "HostName": "workstation",
        "TailscaleIPs": ["100.64.0.1"],
        "DNSName": "workstation.tail1234.ts.net.",
        "OS": "linux"
    },
    "Peer": {
        "peer1": {
            "HostName": "jumpnode",
            "TailscaleIPs": ["100.64.0.10"],
            "DNSName": "jumpnode.tail1234.ts.net.",
            "Online": true,
            "OS": "linux"
        },
        "peer2": {
            "HostName": "web1",
            "TailscaleIPs": ["100.64.0.20"],
            "DNSName": "web1.tail1234.ts.net.",
            "Online": true,
            "OS": "linux"
        },
        "peer3": {
            "HostName": "gateway",
            "TailscaleIPs": ["100.64.0.30"],
            "DNSName": "gateway.tail1234.ts.net.",
            "Online": true,
            "OS": "linux"
        },
        "peer4": {
            "HostName": "gateway-old",
            "TailscaleIPs": ["100.64.0.31"],
            "DNSName": "gateway-old.tail1234.ts.net.",
            "Online": false,
            "OS": "linux"
        }
    },
    "CurrentTailnet": {"Name": "test"},
    "MagicDNSSuffix": "tail1234.ts.net"
}
EOF

    cat > "$TEST_DIR/bin/tailscale" <<EOF
#!/bin/sh
[ "\$1 \$2" = "status --json" ] && exec cat "$TEST_DIR/status.json"
exit 0
EOF

    cat > "$TEST_DIR/bin/ssh" <<'EOF'
#!/bin/sh
printf '%s:' "${0##*/}"
for arg in "$@"; do printf ' [%s]' "$arg"; done
echo
EOF
    local tool
    for tool in scp sftp rsync ssh-copy-id mussh; do
        cp "$TEST_DIR/bin/ssh" "$TEST_DIR/bin/$tool"
    done
    chmod +x "$TEST_DIR/bin/"*

    export PATH="$TEST_DIR/bin:$PATH"
    export HOME="$TEST_DIR/home"
    unset TAILSCALE_USE_MAGICDNS
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

# Run a helper non-interactively and check the command it would run, as
# printed by the shims: "tool: [arg] [arg] ..."
# Usage: expect_exec <test_name> <expected> <command...>
expect_exec() {
    local test_name="$1"
    local expected="$2"
    shift 2

    local output
    output=$("$@" </dev/null 2>&1)
    local actual=$(echo "$output" | grep -E '^(ssh|scp|sftp|rsync|ssh-copy-id|mussh):')

    if [[ "$actual" == "$expected" ]]; then
        report_test "$test_name" "PASS"
    else
        report_test "$test_name" "FAIL" "Expected '$expected', got '${actual:-nothing run}'"
    fi
}

# Run tssh and check that it refuses to connect
# Usage: expect_refused <test_name> <tssh args...>
expect_refused() {
    local test_name="$1"
    shift

    local output status
    output=$("$BIN/tssh" "$@" </dev/null 2>&1)
    status=$?
    if [[ $status -ne 0 ]] && [[ "$output" == *"known_hosts either"* ]] && [[ "$output" != *"ssh:"* ]]; then
        report_test "$test_name" "PASS"
    else
        report_test "$test_name" "FAIL" "Exit $status, output: $output"
    fi
}

# Test reaching hosts through a jump host with tssh and ts
test_tssh() {
    echo -e "\n${BLUE}Testing tssh through a jump host...${RESET}"

    expect_exec "ts -J reaches a LAN address" \
        "ssh: [root@192.168.1.10] [-J] [root@100.64.0.10]" \
        "$BIN/ts" -J jumpnode 192.168.1.10
    expect_exec "ts ssh -J reaches a LAN address" \
        "ssh: [root@192.168.1.10] [-J] [root@100.64.0.10]" \
        "$BIN/ts" ssh -J jumpnode 192.168.1.10
    expect_exec "Tailscale target still resolves behind -J" \
        "ssh: [root@100.64.0.20] [-J] [root@100.64.0.10]" \
        "$BIN/tssh" -J jumpnode web1
    expect_exec "Target user and ssh options kept" \
        "ssh: [admin@192.168.1.10] [-J] [root@100.64.0.10] [-p] [2222] [uptime]" \
        "$BIN/tssh" -J jumpnode admin@192.168.1.10 -p 2222 uptime
    expect_exec "-o ProxyJump works like -J" \
        "ssh: [root@192.168.1.10] [-o] [ProxyJump=root@100.64.0.10]" \
        "$BIN/tssh" -o ProxyJump=jumpnode 192.168.1.10
    expect_exec "-J after the target, before the command" \
        "ssh: [root@192.168.1.10] [-J] [root@100.64.0.10] [uptime]" \
        "$BIN/tssh" 192.168.1.10 -J jumpnode uptime
    expect_exec "Remote command options left alone" \
        "ssh: [root@100.64.0.20] [grep] [-oP] [x] [/var/log/syslog]" \
        "$BIN/tssh" web1 grep -oP x /var/log/syslog
    expect_exec "Remote ssh -J left alone" \
        "ssh: [root@100.64.0.20] [ssh] [-J] [jumpnode] [internal]" \
        "$BIN/tssh" web1 ssh -J jumpnode internal
}

# Test how jump host specs are resolved
test_jump_specs() {
    echo -e "\n${BLUE}Testing jump host spec resolution...${RESET}"

    expect_exec "Attached form -Jhost" \
        "ssh: [root@192.168.1.10] [-J] [root@100.64.0.10]" \
        "$BIN/tssh" -Jjumpnode 192.168.1.10
    expect_exec "Attached form -oProxyJump=host" \
        "ssh: [root@192.168.1.10] [-o] [ProxyJump=root@100.64.0.10]" \
        "$BIN/tssh" -oProxyJump=jumpnode 192.168.1.10
    expect_exec "ProxyJump keyword in any case, space separated" \
        "ssh: [root@192.168.1.10] [-o] [ProxyJump=root@100.64.0.10]" \
        "$BIN/tssh" -o "proxyjump jumpnode" 192.168.1.10
    expect_exec "User and port kept on jump host" \
        "ssh: [root@192.168.1.10] [-J] [admin@100.64.0.10:2222]" \
        "$BIN/tssh" -J admin@jumpnode:2222 192.168.1.10
    expect_exec "ssh:// jump host URI" \
        "ssh: [root@192.168.1.10] [-J] [ssh://root@100.64.0.10:2222]" \
        "$BIN/tssh" -J ssh://jumpnode:2222 192.168.1.10
    expect_exec "Every hop of a chain resolves" \
        "ssh: [root@192.168.1.10] [-J] [root@100.64.0.10,root@100.64.0.20]" \
        "$BIN/tssh" -J jumpnode,web1 192.168.1.10
    expect_exec "Non-Tailscale hop passes through" \
        "ssh: [root@192.168.1.10] [-J] [root@100.64.0.10,bastion.example.com]" \
        "$BIN/tssh" -J jumpnode,bastion.example.com 192.168.1.10
    expect_exec "IPv4 jump host left alone" \
        "ssh: [root@192.168.1.10] [-J] [10.0.0.1]" \
        "$BIN/tssh" -J 10.0.0.1 192.168.1.10
    expect_exec "IPv6 jump host left alone" \
        "ssh: [root@192.168.1.10] [-J] [[fd7a:115c:a1e0::1]:22]" \
        "$BIN/tssh" -J "[fd7a:115c:a1e0::1]:22" 192.168.1.10
    expect_exec "Ambiguous jump host picks best match without a terminal" \
        "ssh: [root@192.168.1.10] [-J] [root@100.64.0.30]" \
        "$BIN/tssh" -J gate 192.168.1.10
}

# Test that behavior without a jump host is unchanged
test_without_jump() {
    echo -e "\n${BLUE}Testing tssh without a jump host...${RESET}"

    expect_exec "Tailscale target connects directly" \
        "ssh: [root@100.64.0.20]" \
        "$BIN/tssh" web1
    expect_exec "Other -o options untouched" \
        "ssh: [root@100.64.0.20] [-o] [StrictHostKeyChecking=no]" \
        "$BIN/tssh" -o StrictHostKeyChecking=no web1
    expect_exec "Attached -o options keep their form" \
        "ssh: [root@100.64.0.20] [-oStrictHostKeyChecking=no]" \
        "$BIN/tssh" -oStrictHostKeyChecking=no web1
    expect_refused "Unknown host still needs known_hosts" 192.168.1.10
    expect_refused "ProxyJump=none is not a jump host" -o ProxyJump=none 192.168.1.10
}

# Test the other helpers that can go through a jump host
test_other_commands() {
    echo -e "\n${BLUE}Testing other commands through a jump host...${RESET}"

    expect_exec "tscp -J" \
        "scp: [-J] [100.64.0.10] [notes.txt] [192.168.1.10:/tmp/]" \
        "$BIN/tscp" -J jumpnode notes.txt 192.168.1.10:/tmp/
    expect_exec "ts scp -J" \
        "scp: [-J] [100.64.0.10] [100.64.0.20:/var/log/syslog] [.]" \
        "$BIN/ts" scp -J jumpnode web1:/var/log/syslog .
    expect_exec "tsftp -J" \
        "sftp: [-J] [root@100.64.0.10] [root@192.168.1.10]" \
        "$BIN/tsftp" -J jumpnode 192.168.1.10
    expect_exec "trsync -e \"ssh -J\"" \
        "rsync: [-av] [-e] [ssh -J 100.64.0.10] [./site/] [192.168.1.10:/srv/]" \
        "$BIN/trsync" -av -e "ssh -J jumpnode" ./site/ 192.168.1.10:/srv/
    expect_exec "trsync -e ending an option bundle" \
        "rsync: [-avze] [ssh -p 2222 -J 100.64.0.10] [./site/] [192.168.1.10:/srv/]" \
        "$BIN/trsync" -avze "ssh -p 2222 -J jumpnode" ./site/ 192.168.1.10:/srv/
    expect_exec "trsync --rsh= with ProxyJump" \
        "rsync: [-a] [--rsh=ssh -o ProxyJump=100.64.0.10] [./site/] [192.168.1.10:/srv/]" \
        "$BIN/trsync" -a "--rsh=ssh -o ProxyJump=jumpnode" ./site/ 192.168.1.10:/srv/
    expect_exec "trsync leaves rsync's own -J alone" \
        "rsync: [-aJ] [-J] [./site/] [100.64.0.20:/srv/]" \
        "$BIN/trsync" -aJ -J ./site/ web1:/srv/
    expect_exec "tssh_copy_id -J goes to ssh as ProxyJump" \
        "ssh-copy-id: [-o] [ProxyJump=root@100.64.0.10] [root@192.168.1.10]" \
        "$BIN/tssh_copy_id" -J jumpnode 192.168.1.10
    expect_exec "tssh_copy_id keeps near-miss names behind a jump host" \
        "ssh-copy-id: [-o] [ProxyJump=root@100.64.0.10] [root@web9]" \
        "$BIN/tssh_copy_id" -J jumpnode web9
    expect_exec "tmussh -J keeps LAN hosts" \
        "mussh: [-J] [100.64.0.10] [-c] [uptime] [-h] [192.168.1.10] [web9]" \
        "$BIN/tmussh" -J jumpnode -h 192.168.1.10 web9 -c uptime
    expect_exec "tmussh -p proxy host" \
        "mussh: [-p] [100.64.0.10] [-c] [uptime] [-h] [web9]" \
        "$BIN/tmussh" -p jumpnode -h web9 -c uptime
    expect_exec "tmussh -o ProxyJump with a Tailscale target" \
        "mussh: [-o] [ProxyJump=100.64.0.10] [-c] [uptime] [-h] [100.64.0.20]" \
        "$BIN/tmussh" -o ProxyJump=jumpnode -h web1 -c uptime
}

# Main test execution
main() {
    echo -e "${BLUE}=== Tailscale CLI Helpers Jump Host Tests ===${RESET}"

    check_requirements
    setup

    test_tssh
    test_jump_specs
    test_without_jump
    test_other_commands

    # Summary
    echo -e "\n${BLUE}=== Test Summary ===${RESET}"
    echo -e "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${RESET}"
    echo -e "${RED}Failed: $TESTS_FAILED${RESET}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All jump host tests passed!${RESET}"
        exit 0
    else
        echo -e "\n${RED}Some jump host tests failed!${RESET}"
        exit 1
    fi
}

# Run main
main "$@"
