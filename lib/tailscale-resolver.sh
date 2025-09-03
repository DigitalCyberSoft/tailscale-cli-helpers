#!/usr/bin/env bash
#
# tailscale-resolver.sh - Shared Tailscale hostname resolution library
#
# This file is sourced by other scripts to provide common resolution logic
#

# Security: Input validation
_validate_hostname() {
    local hostname="$1"
    [[ -n "$hostname" ]] || return 1
    [[ "$hostname" =~ ^[a-zA-Z0-9._@-]+$ ]] || return 1
    [[ ${#hostname} -le 253 ]] || return 1
    return 0
}

# Security: Validate Tailscale JSON structure
_validate_tailscale_json() {
    local json="$1"
    [[ -n "$json" ]] || return 1
    echo "$json" | jq -e '.Self and .Peer and .CurrentTailnet' >/dev/null 2>&1
}

# Security: Sanitize pattern for safe regex use
_sanitize_pattern() {
    local pattern="$1"
    # Remove any potentially dangerous characters for regex patterns
    echo "$pattern" | sed 's/[^a-zA-Z0-9._-]//g'
}

# Levenshtein distance calculation
_levenshtein() {
    local str1="$1"
    local str2="$2"
    local len1=${#str1}
    local len2=${#str2}
    local matrix=()
    local i j cost

    # Initialize matrix
    for ((i = 0; i <= len1; i++)); do
        matrix[$((i * (len2 + 1)))]=$i
    done
    for ((j = 0; j <= len2; j++)); do
        matrix[$j]=$j
    done

    # Calculate distances
    for ((i = 1; i <= len1; i++)); do
        for ((j = 1; j <= len2; j++)); do
            if [[ "${str1:$((i-1)):1}" == "${str2:$((j-1)):1}" ]]; then
                cost=0
            else
                cost=1
            fi
            
            local deletion=$((matrix[$(((i-1) * (len2 + 1) + j))] + 1))
            local insertion=$((matrix[$((i * (len2 + 1) + (j-1)))] + 1))
            local substitution=$((matrix[$(((i-1) * (len2 + 1) + (j-1)))] + cost))
            
            local min=$deletion
            [[ $insertion -lt $min ]] && min=$insertion
            [[ $substitution -lt $min ]] && min=$substitution
            
            matrix[$((i * (len2 + 1) + j))]=$min
        done
    done
    
    echo ${matrix[$((len1 * (len2 + 1) + len2))]}
}

# Resolve Tailscale hostname to IP or DNS name
resolve_tailscale_host() {
    local search_hostname="$1"
    local verbose="${2:-false}"
    
    # Check if user wants to use MagicDNS (opt-in)
    local use_magicdns="${TAILSCALE_USE_MAGICDNS:-false}"
    case "$use_magicdns" in
        true|1|yes|YES|True|TRUE) use_magicdns=true ;;
        *) use_magicdns=false ;;
    esac
    
    # Security: Validate hostname
    _validate_hostname "$search_hostname" || {
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Invalid hostname format: $search_hostname" >&2
        return 1
    }
    
    # Handle user@host format
    local user_prefix=""
    local hostname_only="$search_hostname"
    if [[ "$search_hostname" == *"@"* ]]; then
        user_prefix="${search_hostname%%@*}@"
        hostname_only="${search_hostname#*@}"
    fi
    
    # Get Tailscale status
    local tailscale_json
    tailscale_json=$(tailscale status --json 2>/dev/null) || {
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Failed to get Tailscale status" >&2
        return 1
    }
    
    # Validate JSON
    _validate_tailscale_json "$tailscale_json" || {
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Invalid Tailscale JSON response" >&2
        return 1
    }
    
    # Check if MagicDNS is enabled
    local magicdns_enabled="false"
    if echo "$tailscale_json" | jq -e '.MagicDNSSuffix != null and .MagicDNSSuffix != ""' >/dev/null 2>&1; then
        magicdns_enabled="true"
    fi
    
    [[ "$verbose" == "true" ]] && echo "[DEBUG] MagicDNS enabled: $magicdns_enabled" >&2
    [[ "$verbose" == "true" ]] && echo "[DEBUG] Searching for hostname: $hostname_only" >&2
    
    # Try exact match first
    local result=$(echo "$tailscale_json" | jq -r --arg hostname "$hostname_only" --arg magicdns "$magicdns_enabled" '
        # Check Self host first
        (if .Self.HostName == $hostname then 
            "\(.Self.TailscaleIPs[0]),\(.Self.DNSName // .Self.HostName),\(.Self.OS),online,self"
        else empty end),
        # Check Peer hosts
        (.Peer | to_entries[] | .value | 
            if .HostName == $hostname then
                "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end),\(.PublicKey)"
            else empty end
        )
    ' 2>/dev/null | head -1)
    
    if [[ -z "$result" ]]; then
        # Try fuzzy matching
        [[ "$verbose" == "true" ]] && echo "[DEBUG] No exact match, trying fuzzy search..." >&2
        
        # Get all hosts with Levenshtein distances
        local all_hosts=$(echo "$tailscale_json" | jq -r --arg magicdns "$magicdns_enabled" '
            (.Self | "\(.HostName)"),
            (.Peer | to_entries[] | .value.HostName)
        ' 2>/dev/null)
        
        local best_match=""
        local best_distance=999
        
        while IFS= read -r host; do
            [[ -z "$host" ]] && continue
            local distance=$(_levenshtein "$hostname_only" "$host")
            if [[ $distance -lt $best_distance ]]; then
                best_distance=$distance
                best_match=$host
            fi
        done <<< "$all_hosts"
        
        if [[ -n "$best_match" ]] && [[ $best_distance -le 5 ]]; then
            [[ "$verbose" == "true" ]] && echo "[DEBUG] Best fuzzy match: $best_match (distance: $best_distance)" >&2
            
            # Get the full data for the best match
            result=$(echo "$tailscale_json" | jq -r --arg hostname "$best_match" --arg magicdns "$magicdns_enabled" '
                (if .Self.HostName == $hostname then 
                    "\(.Self.TailscaleIPs[0]),\(.Self.DNSName // .Self.HostName),\(.Self.OS),online,self"
                else empty end),
                (.Peer | to_entries[] | .value | 
                    if .HostName == $hostname then
                        "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end),\(.PublicKey)"
                    else empty end
                )
            ' 2>/dev/null | head -1)
        fi
    fi
    
    if [[ -n "$result" ]]; then
        IFS=',' read -r ip dns_name os online_status pubkey <<< "$result"
        
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Found host - IP: $ip, DNS: $dns_name, OS: $os, Status: $online_status" >&2
        
        # Use DNS name only if user opts in AND MagicDNS is working
        if [[ "$use_magicdns" == "true" ]] && [[ "$magicdns_enabled" == "true" ]] && [[ -n "$dns_name" ]] && [[ "$dns_name" != "null" ]] && is_magicdns_working; then
            echo "${user_prefix}${dns_name}"
        else
            echo "${user_prefix}${ip}"
        fi
        return 0
    fi
    
    [[ "$verbose" == "true" ]] && echo "[DEBUG] Host not found in Tailscale network" >&2
    return 1
}

# Check if MagicDNS is working (has proper resolv.conf entry)
is_magicdns_working() {
    # Check if MagicDNS is enabled first
    local tailscale_json
    tailscale_json=$(tailscale status --json 2>/dev/null) || return 1
    
    local magicdns_enabled="false"
    if echo "$tailscale_json" | jq -e '.MagicDNSSuffix != null and .MagicDNSSuffix != ""' >/dev/null 2>&1; then
        magicdns_enabled="true"
    fi
    
    [[ "$magicdns_enabled" != "true" ]] && return 1
    
    # Check if resolv.conf has Tailscale nameserver
    if [[ -r /etc/resolv.conf ]]; then
        grep -q "^nameserver 100\.100\.100\.100" /etc/resolv.conf 2>/dev/null
    else
        return 1
    fi
}

# Find all hosts matching a pattern
find_all_matching_hosts() {
    local search_hostname="$1"
    local verbose="${2:-false}"
    
    # Security: Validate hostname
    _validate_hostname "$search_hostname" || {
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Invalid hostname format: $search_hostname" >&2
        return 1
    }
    
    # Handle user@host format
    local hostname_only="$search_hostname"
    if [[ "$search_hostname" == *"@"* ]]; then
        hostname_only="${search_hostname#*@}"
    fi
    
    # Get Tailscale status
    local tailscale_json
    tailscale_json=$(tailscale status --json 2>/dev/null) || {
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Failed to get Tailscale status" >&2
        return 1
    }
    
    # Validate JSON
    _validate_tailscale_json "$tailscale_json" || {
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Invalid Tailscale JSON response" >&2
        return 1
    }
    
    # Get MagicDNS status
    local magicdns_enabled="false"
    if echo "$tailscale_json" | jq -e '.MagicDNSSuffix != null and .MagicDNSSuffix != ""' >/dev/null 2>&1; then
        magicdns_enabled="true"
    fi
    
    # Find all matching hosts (case-insensitive), excluding Mullvad exit nodes
    local matches=$(echo "$tailscale_json" | jq -r --arg pattern "$hostname_only" --arg magicdns "$magicdns_enabled" '
        # Check Self host
        (if (.Self.HostName | ascii_downcase | contains($pattern | ascii_downcase)) then 
            "\(.Self.TailscaleIPs[0]),\(.Self.DNSName // .Self.HostName),\(.Self.OS),online"
        else empty end),
        # Check Peer hosts (excluding Mullvad exit nodes)
        (.Peer | to_entries[] | .value | 
            select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not)) |
            if (.HostName | ascii_downcase | contains($pattern | ascii_downcase)) then
                "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end)"
            else empty end
        )
    ' 2>/dev/null)
    
    # If no matches with contains, try exact match
    if [[ -z "$matches" ]]; then
        matches=$(echo "$tailscale_json" | jq -r --arg hostname "$hostname_only" --arg magicdns "$magicdns_enabled" '
            # Check Self host
            (if .Self.HostName == $hostname then 
                "\(.Self.TailscaleIPs[0]),\(.Self.DNSName // .Self.HostName),\(.Self.OS),online"
            else empty end),
            # Check Peer hosts (excluding Mullvad exit nodes)
            (.Peer | to_entries[] | .value | 
                select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not)) |
                if .HostName == $hostname then
                    "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end)"
                else empty end
            )
        ' 2>/dev/null)
    fi
    
    # Output all matches with Levenshtein distance sorting
    if [[ -n "$matches" ]]; then
        local sorted_matches=()
        while IFS= read -r match; do
            if [[ -n "$match" ]]; then
                local match_hostname=$(echo "$match" | cut -d',' -f2)
                local distance=$(_levenshtein "$hostname_only" "$match_hostname")
                # Format: distance:hostname:full_match for proper sorting
                # Pad distance with zeros for correct numeric sorting
                sorted_matches+=("$(printf "%03d:%s:%s" "$distance" "$match_hostname" "$match")")
            fi
        done <<< "$matches"
        
        # Sort by distance (numeric) then by hostname (alphabetic)
        IFS=$'\n' sorted_matches=($(sort -t':' -k1,1n -k2,2 <<< "${sorted_matches[*]}"))
        
        # Output sorted matches without distance and hostname prefix
        for entry in "${sorted_matches[@]}"; do
            # Extract the full match data (after second colon)
            echo "${entry#*:*:}"
        done
    fi
    
    return 0
}

# Multi-host pattern matching function for commands like mussh that need wildcard support
# Returns newline-separated list of "ip,hostname,os,status" entries
find_multiple_hosts_matching() {
    local search_pattern="$1"
    local verbose="${2:-false}"
    
    # Basic validation
    if [[ -z "$search_pattern" ]]; then
        return 1
    fi
    
    # Get Tailscale status
    local tailscale_json
    tailscale_json=$(tailscale status --json 2>/dev/null) || {
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Failed to get Tailscale status" >&2
        return 1
    }
    
    # Validate JSON
    _validate_tailscale_json "$tailscale_json" || {
        [[ "$verbose" == "true" ]] && echo "[DEBUG] Invalid Tailscale JSON response" >&2
        return 1
    }
    
    # Get MagicDNS status
    local magicdns_enabled="false"
    if echo "$tailscale_json" | jq -e '.MagicDNSSuffix != null and .MagicDNSSuffix != ""' >/dev/null 2>&1; then
        magicdns_enabled="true"
    fi
    
    # Convert shell wildcard pattern to regex pattern
    local regex_pattern="${search_pattern//\*/.*}"
    
    # Use jq to find matching hosts - allow more permissive pattern matching for multi-host commands
    echo "$tailscale_json" | jq -r --arg pattern "$regex_pattern" --arg magicdns "$magicdns_enabled" '
        # Extract Self host if it matches
        (if (.Self.HostName | test($pattern)) then 
            "\(.Self.TailscaleIPs[0]),\(.Self.DNSName // .Self.HostName),\(.Self.OS),online"
        else empty end),
        # Extract matching Peer hosts (excluding Mullvad exit nodes)
        (.Peer | to_entries[] | .value | 
            select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not)) |
            if (.HostName | test($pattern)) then
                "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end)"
            else empty end
        )
    ' 2>/dev/null || {
        # Fallback: try basic pattern matching without regex (excluding Mullvad exit nodes)
        echo "$tailscale_json" | jq -r --arg pattern "$search_pattern" '
            # Simple fallback - check if hostname contains the pattern (without wildcards)
            (.Self.HostName), 
            (.Peer | to_entries[] | .value | 
                select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not)) |
                .HostName
            ) | 
            select(contains($pattern))' 2>/dev/null | head -5
    }
}

# Get all Tailscale hosts for completion
get_all_tailscale_hosts() {
    local prefix="${1:-}"
    local prefix_pattern="${2:-}"
    
    local tailscale_json
    tailscale_json=$(tailscale status --json 2>/dev/null) || return 1
    
    _validate_tailscale_json "$tailscale_json" || return 1
    
    # Extract all hostnames, excluding Mullvad exit nodes
    local hosts=$(echo "$tailscale_json" | jq -r '
        (.Self | "\(.HostName)"),
        (.Peer | to_entries[] | .value | 
            select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not)) |
            .HostName
        )
    ' 2>/dev/null | sort -u)
    
    # Filter by prefix if provided
    if [[ -n "$prefix_pattern" ]]; then
        hosts=$(echo "$hosts" | grep -E "^${prefix_pattern}")
    fi
    
    # Add user prefix if needed
    if [[ -n "$prefix" ]]; then
        while IFS= read -r host; do
            [[ -n "$host" ]] && echo "${prefix}${host}"
        done <<< "$hosts"
    else
        echo "$hosts"
    fi
}