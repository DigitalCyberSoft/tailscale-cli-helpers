#!/bin/bash
# Interactive test for fuzzy matching functionality

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Source the functions
if [[ -f ../tailscale-ssh-helper.sh ]]; then
    source ../tailscale-ssh-helper.sh
else
    echo -e "${RED}✗ Could not find ../tailscale-ssh-helper.sh${RESET}"
    exit 1
fi

echo -e "${BLUE}=== Fuzzy Matching Test ===${RESET}"
echo
echo "This test will verify that the Levenshtein distance function works correctly"
echo "for fuzzy hostname matching."
echo

# Test the Levenshtein function directly
test_levenshtein_direct() {
    local str1="$1"
    local str2="$2"
    local expected="$3"
    
    local result=$(_dcs_levenshtein "$str1" "$str2")
    
    if [[ "$result" -eq "$expected" ]]; then
        echo -e "${GREEN}✓${RESET} Distance between '$str1' and '$str2': $result (expected: $expected)"
        return 0
    else
        echo -e "${RED}✗${RESET} Distance between '$str1' and '$str2': $result (expected: $expected)"
        return 1
    fi
}

echo -e "${YELLOW}Testing known distance calculations:${RESET}"
test_levenshtein_direct "test" "test" 0
test_levenshtein_direct "cat" "bat" 1  
test_levenshtein_direct "kitten" "sitting" 3
test_levenshtein_direct "abc" "def" 3
test_levenshtein_direct "hello" "hallo" 1

echo
echo -e "${YELLOW}Interactive fuzzy matching test:${RESET}"
echo "Enter a short test string (this will be used to test fuzzy matching):"
echo "The system will show how it would match against common hostname patterns."
echo

read -p "Test string: " test_string

if [[ -z "$test_string" ]]; then
    echo -e "${RED}No test string provided, exiting${RESET}"
    exit 1
fi

echo
echo -e "${BLUE}Testing fuzzy matching for: '$test_string'${RESET}"
echo

# Create some example hostnames to test against
example_hosts=(
    "webserver"
    "database"
    "frontend" 
    "backend"
    "staging"
    "production"
    "development"
    "testing"
    "monitor"
    "backup"
)

# Calculate distances and sort
declare -a distances=()
for host in "${example_hosts[@]}"; do
    local distance=$(_dcs_levenshtein "$test_string" "$host")
    distances+=("$distance:$host")
done

# Sort by distance
IFS=$'\n' sorted_distances=($(sort -n <<< "${distances[*]}"))

echo "Fuzzy matching results (sorted by similarity):"
echo "================================================"

for entry in "${sorted_distances[@]}"; do
    local distance="${entry%%:*}"
    local hostname="${entry#*:}"
    
    # Color code based on distance
    if [[ $distance -eq 0 ]]; then
        color="${GREEN}"
        match_quality="Exact match"
    elif [[ $distance -le 2 ]]; then
        color="${GREEN}"
        match_quality="Excellent match"
    elif [[ $distance -le 4 ]]; then
        color="${YELLOW}"
        match_quality="Good match"
    else
        color="${RED}"
        match_quality="Poor match"
    fi
    
    echo -e "${color}$hostname${RESET} (distance: $distance) - $match_quality"
done

echo
echo -e "${BLUE}This demonstrates how tssh would rank hosts when you type:${RESET}"
echo "  tssh $test_string"
echo
echo "The hosts with the lowest distance would be shown first."
echo "In a real Tailscale environment, this would help you find the right host"
echo "even if you don't remember the exact hostname."

echo
echo -e "${GREEN}✓ Fuzzy matching test completed!${RESET}"