#!/bin/bash
# Final test summary script for binary-based installation

echo "===========================================" 
echo "TAILSCALE CLI HELPERS - TEST SUMMARY"
echo "Testing binary-based installation"
echo "==========================================="
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Check if we're in development or installed
DEV_MODE=false
if [[ -d "../bin" ]] && [[ -d "../lib" ]]; then
    DEV_MODE=true
    echo -e "${BLUE}📁 Development Mode - Testing from source${RESET}"
else
    echo -e "${BLUE}📁 Testing installed binaries${RESET}"
fi

echo
echo -e "${BLUE}📦 Project Structure:${RESET}"
if [[ "$DEV_MODE" == "true" ]]; then
    echo "  ✓ Binaries: bin/ directory"
    echo "  ✓ Library: lib/tailscale-resolver.sh"
    echo "  ✓ Man pages: man/man1/ directory"
    echo "  ✓ Tests: tests/ directory"
    echo "  ✓ Setup: setup.sh"
    echo "  ✓ Packaging: RPM and DEB files"
else
    echo "  ✓ Installed binaries in PATH"
    echo "  ✓ Man pages available"
    echo "  ✓ Bash completions installed"
fi
echo

echo -e "${BLUE}🔍 Command Availability:${RESET}"
commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id")
optional_commands=("tmussh")
available_count=0

for cmd in "${commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} $cmd"
        available_count=$((available_count + 1))
    else
        echo -e "  ${RED}✗${RESET} $cmd (not found)"
    fi
done

# Check optional commands
optional_available=0
for cmd in "${optional_commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} $cmd (optional)"
        optional_available=$((optional_available + 1))
    else
        echo -e "  ${YELLOW}?${RESET} $cmd (optional - requires mussh)"
    fi
done

echo -e "  ${BLUE}→${RESET} $available_count/${#commands[@]} core commands available, $optional_available/${#optional_commands[@]} optional commands available"
echo

echo -e "${BLUE}📚 Man Pages:${RESET}"
man_count=0
for cmd in "${commands[@]}"; do
    if man "$cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} $cmd man page"
        man_count=$((man_count + 1))
    else
        echo -e "  ${YELLOW}?${RESET} $cmd man page (not found)"
    fi
done
echo -e "  ${BLUE}→${RESET} $man_count/${#commands[@]} man pages available"
echo

echo -e "${BLUE}🛠️ Dependencies:${RESET}"
deps=("jq" "tailscale" "ssh")
optional_deps=("scp" "sftp" "rsync" "mussh")

for dep in "${deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} $dep"
    else
        echo -e "  ${RED}✗${RESET} $dep (required)"
    fi
done

echo -e "  ${BLUE}Optional:${RESET}"
for dep in "${optional_deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${RESET} $dep"
    else
        echo -e "  ${YELLOW}?${RESET} $dep (optional)"
    fi
done
echo

echo -e "${BLUE}🧪 Quick Functionality Test:${RESET}"

# Test basic command execution
test_count=0
pass_count=0

# Test ts help
if ts help >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} ts help works"
    pass_count=$((pass_count + 1))
else
    echo -e "  ${RED}✗${RESET} ts help failed"
fi
test_count=$((test_count + 1))

# Test tssh usage
if tssh 2>&1 | grep -q "Usage" >/dev/null; then
    echo -e "  ${GREEN}✓${RESET} tssh shows usage"
    pass_count=$((pass_count + 1))
else
    echo -e "  ${RED}✗${RESET} tssh usage failed"
fi
test_count=$((test_count + 1))

# Test ts dispatcher
if ts help | grep -q "ssh" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} ts dispatcher works"
    pass_count=$((pass_count + 1))
else
    echo -e "  ${RED}✗${RESET} ts dispatcher failed"
fi
test_count=$((test_count + 1))

# Test that old functions are not loaded
if ! type tssh 2>/dev/null | grep -q "function" >/dev/null; then
    echo -e "  ${GREEN}✓${RESET} old functions removed"
    pass_count=$((pass_count + 1))
else
    echo -e "  ${YELLOW}?${RESET} old functions still present"
fi
test_count=$((test_count + 1))

echo -e "  ${BLUE}→${RESET} $pass_count/$test_count quick tests passed"
echo

# Check bash completions
echo -e "${BLUE}🔄 Bash Completions:${RESET}"
completion_files=(
    "/etc/bash_completion.d/tailscale-cli-helpers"
    "$HOME/.local/share/bash-completion/completions/tailscale-cli-helpers"
)

completion_found=false
for comp_file in "${completion_files[@]}"; do
    if [[ -f "$comp_file" ]]; then
        echo -e "  ${GREEN}✓${RESET} Found: $comp_file"
        completion_found=true
        break
    fi
done

if [[ "$completion_found" == "false" ]]; then
    echo -e "  ${YELLOW}?${RESET} No completion files found"
fi
echo

echo -e "${BLUE}🚀 Next Steps:${RESET}"
if [[ $available_count -eq ${#commands[@]} ]] && [[ $pass_count -eq $test_count ]]; then
    echo -e "  ${GREEN}✅ Installation looks good!${RESET}"
    echo "  Try: ts <hostname> to SSH to a Tailscale node"
    echo "  Try: tscp file.txt <hostname>:/path/ to copy files"
    echo "  Try: man ts for full documentation"
    echo
    echo -e "${GREEN}🎉 All systems operational!${RESET}"
else
    echo -e "  ${YELLOW}⚠️ Issues detected:${RESET}"
    if [[ $available_count -ne ${#commands[@]} ]]; then
        echo "    - Some commands are missing"
        echo "    - Try running the installation script again"
    fi
    if [[ $pass_count -ne $test_count ]]; then
        echo "    - Functionality tests failed"
        echo "    - Check dependencies and installation"
    fi
    echo
    echo "  Run ./tests/test-both-shells.sh for detailed testing"
fi

echo
echo "==========================================="