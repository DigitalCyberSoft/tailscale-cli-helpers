#!/bin/bash
# Test tsexit's menu by driving it in a pty: quick keys (0 disables the exit
# node, 1-3 switch to a recent exit node), the recent exit node list, and
# scrolling a newly expanded country's nodes into view

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TSEXIT="$PROJECT_DIR/bin/tsexit"

# Exit nodes in the synthetic tailnet
HOME_NODE="homeserver.tail1234.ts.net"
HOME_IP="100.64.0.10"
DE_NODE="de-fra-wg-001.mullvad.ts.net"
DE_IP="100.64.1.1"
SE_NODE="se-sto-wg-001.mullvad.ts.net"
SE_IP="100.64.1.2"
US_NODE="us-nyc-wg-301.mullvad.ts.net"
US_IP="100.64.1.3"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Check for required commands
check_requirements() {
    local cmd
    for cmd in jq python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}✗ $cmd is required but not installed${RESET}"
            exit 1
        fi
    done
}

# Setup test environment: a stateful tailscale shim serving a synthetic
# tailnet (status --json marks the peer last passed to set --exit-node), and
# a pty driver that presses keys in tsexit's menu
setup() {
    TEST_DIR=$(mktemp -d)
    trap 'rm -rf "$TEST_DIR"' EXIT
    mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home"

    cat > "$TEST_DIR/status.json" <<EOF
{
    "Self": {
        "HostName": "workstation",
        "TailscaleIPs": ["100.64.0.1"],
        "DNSName": "workstation.tail1234.ts.net."
    },
    "Peer": {
        "peer1": {
            "HostName": "homeserver",
            "TailscaleIPs": ["$HOME_IP"],
            "DNSName": "$HOME_NODE.",
            "ExitNodeOption": true
        },
        "peer2": {
            "HostName": "de-fra-wg-001",
            "TailscaleIPs": ["$DE_IP"],
            "DNSName": "$DE_NODE.",
            "ExitNodeOption": true,
            "Tags": ["tag:mullvad-exit-node"],
            "Location": {"Country": "Germany", "City": "Frankfurt"}
        },
        "peer3": {
            "HostName": "se-sto-wg-001",
            "TailscaleIPs": ["$SE_IP"],
            "DNSName": "$SE_NODE.",
            "ExitNodeOption": true,
            "Tags": ["tag:mullvad-exit-node"],
            "Location": {"Country": "Sweden", "City": "Stockholm"}
        },
        "peer4": {
            "HostName": "us-nyc-wg-301",
            "TailscaleIPs": ["$US_IP"],
            "DNSName": "$US_NODE.",
            "ExitNodeOption": true,
            "Tags": ["tag:mullvad-exit-node"],
            "Location": {"Country": "USA", "City": "New York, NY"}
        },
        "peer5": {
            "HostName": "web1",
            "TailscaleIPs": ["100.64.0.20"],
            "DNSName": "web1.tail1234.ts.net."
        },
        "peer6": {
            "HostName": "au-syd-wg-001",
            "TailscaleIPs": ["100.64.1.4"],
            "DNSName": "au-syd-wg-001.mullvad.ts.net.",
            "ExitNodeOption": true,
            "Tags": ["tag:mullvad-exit-node"],
            "Location": {"Country": "Australia", "City": "Sydney"}
        },
        "peer7": {
            "HostName": "ca-tor-wg-001",
            "TailscaleIPs": ["100.64.1.5"],
            "DNSName": "ca-tor-wg-001.mullvad.ts.net.",
            "ExitNodeOption": true,
            "Tags": ["tag:mullvad-exit-node"],
            "Location": {"Country": "Canada", "City": "Toronto"}
        },
        "peer8": {
            "HostName": "us-chi-wg-101",
            "TailscaleIPs": ["100.64.1.6"],
            "DNSName": "us-chi-wg-101.mullvad.ts.net.",
            "ExitNodeOption": true,
            "Tags": ["tag:mullvad-exit-node"],
            "Location": {"Country": "USA", "City": "Chicago, IL"}
        },
        "peer9": {
            "HostName": "us-lax-wg-201",
            "TailscaleIPs": ["100.64.1.7"],
            "DNSName": "us-lax-wg-201.mullvad.ts.net.",
            "ExitNodeOption": true,
            "Tags": ["tag:mullvad-exit-node"],
            "Location": {"Country": "USA", "City": "Los Angeles, CA"}
        },
        "peer10": {
            "HostName": "us-sea-wg-001",
            "TailscaleIPs": ["100.64.1.8"],
            "DNSName": "us-sea-wg-001.mullvad.ts.net.",
            "ExitNodeOption": true,
            "Tags": ["tag:mullvad-exit-node"],
            "Location": {"Country": "USA", "City": "Seattle, WA"}
        }
    },
    "CurrentTailnet": {"Name": "test"}
}
EOF

    # Japan gets more nodes (jp-tyo-wg-101 to 112) than a short menu shows
    jq '.Peer += ([range(101; 113)] | map({
            key: "jp\(.)",
            value: {
                HostName: "jp-tyo-wg-\(.)",
                TailscaleIPs: ["100.64.3.\(.)"],
                DNSName: "jp-tyo-wg-\(.).mullvad.ts.net.",
                ExitNodeOption: true,
                Tags: ["tag:mullvad-exit-node"],
                Location: {Country: "Japan", City: "Tokyo"}
            }
        }) | from_entries)' "$TEST_DIR/status.json" > "$TEST_DIR/status.tmp" &&
        mv "$TEST_DIR/status.tmp" "$TEST_DIR/status.json"

    # TS_SET_FAIL makes set fail with an error tsexit must not retry via sudo.
    # TS_SET_DENY makes set refuse the change the way tailscale does for a
    # user who is not the operator ("prefs write access denied" from
    # tailscaled, plus the CLI's operator hint)
    cat > "$TEST_DIR/bin/tailscale" <<EOF
#!/bin/sh
case "\$1" in
    status)
        if [ "\$2" = "--json" ]; then
            exec jq --arg ip "\$(cat "$TEST_DIR/exit-node" 2>/dev/null)" \\
                '.Peer |= map_values(.ExitNode = (.TailscaleIPs[0] == \$ip))' \\
                "$TEST_DIR/status.json"
        fi
        ;;
    set)
        if [ -n "\$TS_SET_FAIL" ]; then
            echo "set failed" >&2
            exit 1
        fi
        if [ -n "\$TS_SET_DENY" ]; then
            echo "prefs write access denied" >&2
            echo "To not require root, use 'sudo tailscale set --operator=\\\$USER' once." >&2
            exit 1
        fi
        case "\$2" in
            --exit-node=*) printf '%s' "\${2#--exit-node=}" > "$TEST_DIR/exit-node" ;;
        esac
        ;;
esac
exit 0
EOF
    chmod +x "$TEST_DIR/bin/tailscale"

    # Stands in for sudo, so no test can reach the real one: records the
    # command and runs it as if root had been granted
    cat > "$TEST_DIR/bin/sudo" <<EOF
#!/bin/sh
echo "\$*" >> "$TEST_DIR/sudo.log"
unset TS_SET_DENY
exec "\$@"
EOF
    chmod +x "$TEST_DIR/bin/sudo"

    # Usage: drive.py <output file> <command> <key>...
    # Presses each key once the screen settles, writes the output with
    # escape sequences stripped, and exits with the command's exit status.
    # <output file>.screen gets what was drawn since the last clear when the
    # last key was pressed: the menu as it looked before quitting.
    # PTY_ROWS sets the terminal height (default 40)
    cat > "$TEST_DIR/drive.py" <<'EOF'
import codecs, fcntl, os, pty, re, select, struct, sys, termios, time

out_path, command = sys.argv[1], sys.argv[2]
keys = [codecs.decode(k, "unicode_escape") for k in sys.argv[3:]]
rows = int(os.environ.get("PTY_ROWS", "40"))

pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, 100, 0, 0))
    os.execvp(command, [command])

output = bytearray()

def strip(data):
    text = re.sub(rb"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][0-9A-Za-z]|\x1b[=>]|\r", b"", data)
    return text.decode("utf-8", "replace")

def screen():
    start = output.rfind(b"\x1b[2J")
    return strip(bytes(output[start + 4:] if start >= 0 else output))

def pump(quiet=0.4, limit=5.0):
    """Read until the screen is quiet; False once the command has exited."""
    end = time.time() + limit
    last = time.time()
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return False
            if not data:
                return False
            output.extend(data)
            last = time.time()
        elif time.time() - last > quiet:
            return True
    return True

running = pump(quiet=0.8)
last_screen = ""
for key in keys:
    if not running:
        break
    last_screen = screen()
    os.write(fd, key.encode())
    running = pump()

status = None
end = time.time() + 5
while status is None and time.time() < end:
    done, raw = os.waitpid(pid, os.WNOHANG)
    if done:
        status = raw
    else:
        pump(quiet=0.1, limit=0.2)
if status is None:
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    code = 124
elif os.WIFEXITED(status):
    code = os.WEXITSTATUS(status)
else:
    code = 128 + os.WTERMSIG(status)

with open(out_path, "w") as f:
    f.write(strip(bytes(output)))
with open(out_path + ".screen", "w") as f:
    f.write(last_screen)
sys.exit(code)
EOF

    export PATH="$TEST_DIR/bin:$PATH"
    export HOME="$TEST_DIR/home"
    export XDG_STATE_HOME="$TEST_DIR/state"
    export TERM=xterm-256color
    unset TS_SET_FAIL TS_SET_DENY PTY_ROWS
    RECENT_FILE="$XDG_STATE_HOME/tailscale-cli-helpers/recent-exit-nodes"
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

# Set the starting state: active exit node IP (empty for none) and the
# recent list, one name per argument
start_with() {
    printf '%s' "$1" > "$TEST_DIR/exit-node"
    shift
    rm -f "$RECENT_FILE"
    if [[ $# -gt 0 ]]; then
        mkdir -p "${RECENT_FILE%/*}"
        printf '%s\n' "$@" > "$RECENT_FILE"
    fi
}

# Run tsexit in a pty pressing the given keys; sets OUTPUT, SCREEN (the menu
# when the last key was pressed) and STATUS
run_tsexit() {
    python3 "$TEST_DIR/drive.py" "$TEST_DIR/output" "$TSEXIT" "$@"
    STATUS=$?
    OUTPUT=$(cat "$TEST_DIR/output")
    SCREEN=$(cat "$TEST_DIR/output.screen")
}

# Check the exit status, the exit node left active and the saved recent list
# Usage: expect_state <test_name> <status> <exit node IP> <recent names, comma separated>
expect_state() {
    local test_name="$1"
    local expected="status=$2 node=$3 recent=$4"
    local recent=""
    [[ -f "$RECENT_FILE" ]] && recent=$(paste -sd, "$RECENT_FILE")
    local actual="status=$STATUS node=$(cat "$TEST_DIR/exit-node") recent=$recent"

    if [[ "$actual" == "$expected" ]]; then
        report_test "$test_name" "PASS"
    else
        report_test "$test_name" "FAIL" "Expected '$expected', got '$actual'"
    fi
}

# Check that text does (or with "!" does not) contain a string
# Usage: expect_text <test_name> <label> <text> [!] <string>
expect_text() {
    local test_name="$1"
    local label="$2"
    local text="$3"
    shift 3
    local negate=false
    if [[ "$1" == "!" ]]; then
        negate=true
        shift
    fi

    local found=false
    [[ "$text" == *"$1"* ]] && found=true
    if [[ "$found" != "$negate" ]]; then
        report_test "$test_name" "PASS"
    else
        report_test "$test_name" "FAIL" "$label $([[ $negate == true ]] && echo "contains" || echo "lacks") '$1'"
    fi
}

# Check the whole captured output, or only the final menu screen
# Usage: expect_output|expect_screen <test_name> [!] <string>
expect_output() {
    local test_name="$1"
    shift
    expect_text "$test_name" "Output" "$OUTPUT" "$@"
}

expect_screen() {
    local test_name="$1"
    shift
    expect_text "$test_name" "Screen" "$SCREEN" "$@"
}

test_disable_key() {
    echo -e "\n${BLUE}Disable with 0${RESET}"

    start_with "$DE_IP"
    run_tsexit "0"
    expect_state "0 disables the exit node and quits, remembering it" 0 "" "$DE_NODE"
    expect_output "result is printed" "Exit node disabled successfully"
    expect_output "footer shows the 0 key" "[0] Disable"
}

test_recent_keys() {
    echo -e "\n${BLUE}Recent exit nodes${RESET}"

    start_with "" "$DE_NODE"
    run_tsexit "1"
    expect_state "1 reactivates the last exit node" 0 "$DE_IP" "$DE_NODE"
    expect_output "recent entry shows city and key" "◯ $DE_NODE (Frankfurt) [1]"

    start_with "$HOME_IP" "$HOME_NODE" "$DE_NODE"
    run_tsexit "1"
    expect_state "current node is left out, so 1 is the previous one" 0 "$DE_IP" "$DE_NODE,$HOME_NODE"
    expect_output "current node has no recent key" ! "$HOME_NODE ["

    start_with "$US_IP" "$SE_NODE" "$HOME_NODE" "$DE_NODE"
    run_tsexit "0"
    expect_state "node set outside tsexit is remembered; list keeps 3" 0 "" "$US_NODE,$SE_NODE,$HOME_NODE"

    start_with "" "gone-wg-001.mullvad.ts.net" "$SE_NODE"
    run_tsexit "1"
    expect_state "entries no longer offered are skipped in numbering" 0 "$SE_IP" "$SE_NODE,gone-wg-001.mullvad.ts.net"
    expect_output "stale entry is not shown" ! "gone-wg-001"

    start_with "" "$SE_NODE"
    run_tsexit "3" "q"
    expect_state "unused recent key does nothing" 0 "" "$SE_NODE"
}

test_enter_records_previous() {
    echo -e "\n${BLUE}Selecting with Enter${RESET}"

    # Cursor starts on None; Down moves to the first personal device
    start_with "$DE_IP" "$DE_NODE"
    run_tsexit $'\x1b[B' $'\r' "x" "q"
    expect_state "Enter records the new node ahead of the one it replaced" 0 "$HOME_IP" "$HOME_NODE,$DE_NODE"
}

test_failures() {
    echo -e "\n${BLUE}Failures${RESET}"

    start_with "$DE_IP" "$SE_NODE"
    export TS_SET_FAIL=1
    run_tsexit "0"
    unset TS_SET_FAIL
    expect_state "failed disable exits non-zero and changes nothing" 1 "$DE_IP" "$SE_NODE"
    expect_output "failure is reported" "Failed to disable exit node"

    start_with "$DE_IP"
    touch "$TEST_DIR/not-a-dir"
    XDG_STATE_HOME="$TEST_DIR/not-a-dir" run_tsexit "0"
    expect_state "unsaveable recent list still disables" 0 "" ""
    expect_output "unsaveable recent list warns" "Warning: could not save recent exit nodes"
}

test_sudo_fallback() {
    echo -e "\n${BLUE}Sudo fallback${RESET}"

    # Tailscale refuses the change, so tsexit retries it through sudo
    rm -f "$TEST_DIR/sudo.log"
    start_with "$DE_IP"
    export TS_SET_DENY=1
    run_tsexit "0"
    unset TS_SET_DENY
    expect_state "a refused change is retried with sudo" 0 "" "$DE_NODE"
    expect_output "the sudo retry is announced" "Permission required, using sudo..."
    expect_output "the operator command is suggested" "run once: sudo tailscale set --operator=$(id -un)"
    local sudo_calls
    sudo_calls=$(cat "$TEST_DIR/sudo.log" 2>/dev/null)
    if [[ "$sudo_calls" == "tailscale set --exit-node=" ]]; then
        report_test "sudo runs only the refused tailscale set" "PASS"
    else
        report_test "sudo runs only the refused tailscale set" "FAIL" "sudo was run as: '${sudo_calls:-never}'"
    fi

    # An allowed change never touches sudo and shows no tip
    rm -f "$TEST_DIR/sudo.log"
    start_with "$DE_IP"
    run_tsexit "0"
    expect_output "no operator tip when the change is allowed" ! "--operator"
    if [[ ! -e "$TEST_DIR/sudo.log" ]]; then
        report_test "sudo is not used when the change is allowed" "PASS"
    else
        report_test "sudo is not used when the change is allowed" "FAIL" "sudo was run as: '$(cat "$TEST_DIR/sudo.log")'"
    fi
}

test_other_keys() {
    echo -e "\n${BLUE}Other keys and modes${RESET}"

    start_with "$DE_IP"
    run_tsexit "r" "q"
    expect_output "r refreshes instead of jumping to a country" "Refreshing..."

    # Select mode numbers options itself: 1 is None, 2 the first recent node
    start_with "" "$SE_NODE"
    TERM=dumb run_tsexit $'2\r' "x"
    expect_state "select mode lists recent nodes as options" 0 "$SE_IP" "$SE_NODE"
    expect_output "select mode labels recent nodes" "$SE_NODE (Stockholm) (recent)"

    OUTPUT=$("$TSEXIT" --help)
    expect_output "--help documents the quick keys" "0: Disable the exit node and quit"
}

test_expand_reveals_nodes() {
    echo -e "\n${BLUE}Expanding a country${RESET}"

    # An 18-row terminal leaves a 10-row menu: None, a separator, the
    # personal section (3 rows), the Mullvad header and separator, then
    # Australia, Canada, Germany, Japan, Sweden, USA
    export PTY_ROWS=18
    local down=$'\x1b[B'
    local right=$'\x1b[C'

    # Seven Downs reach USA, which scrolls into the bottom row
    start_with ""
    run_tsexit "$down" "$down" "$down" "$down" "$down" "$down" "$down" "$right" "q"
    expect_screen "Right on the bottom row shows the new nodes" "us-sea-wg-001.mullvad.ts.net (Seattle, WA)"
    expect_screen "all of a country's nodes show when they fit" "us-nyc-wg-301.mullvad.ts.net (New York, NY)"
    expect_screen "the expanded country stays on screen" "▼ 🌍 USA (4 nodes)"

    # Japan's 12 nodes cannot all fit: Japan moves to the top row and its
    # nodes fill the other 9
    start_with ""
    run_tsexit "$down" "$down" "$down" "$down" "$down" $'\r' "q"
    expect_screen "Enter expanding a large country keeps its row on screen" "▼ 🌍 Japan (12 nodes)"
    local shown
    shown=$(grep -c "jp-tyo-wg-" <<< "$SCREEN")
    if [[ "$shown" -eq 9 ]]; then
        report_test "a large country's nodes fill the rest of the menu" "PASS"
    else
        report_test "a large country's nodes fill the rest of the menu" "FAIL" "Expected 9 Japan nodes on screen, got $shown"
    fi

    # Australia's node already fits below it, so nothing scrolls
    start_with ""
    run_tsexit "$down" "$down" "$right" "q"
    expect_screen "expanding a country whose nodes fit does not scroll" "None (Disable exit node)"
    expect_screen "the fitting node is shown" "au-syd-wg-001.mullvad.ts.net (Sydney)"

    unset PTY_ROWS
}

main() {
    echo -e "${BLUE}=== tsexit Menu ===${RESET}"

    check_requirements
    setup

    test_disable_key
    test_recent_keys
    test_enter_records_previous
    test_failures
    test_sudo_fallback
    test_other_keys
    test_expand_reveals_nodes

    echo -e "\n${BLUE}=== Test Summary ===${RESET}"
    echo "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${RESET}"
    echo -e "${RED}Failed: $TESTS_FAILED${RESET}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All tsexit tests passed!${RESET}"
        exit 0
    else
        echo -e "\n${RED}Some tsexit tests failed${RESET}"
        exit 1
    fi
}

main "$@"
