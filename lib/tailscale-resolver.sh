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

# Check whether the tailnet has MagicDNS turned on. MagicDNSSuffix is
# reported even when MagicDNS is disabled, so only MagicDNSEnabled counts
_magicdns_enabled() {
    echo "$1" | jq -e '.CurrentTailnet.MagicDNSEnabled == true' >/dev/null 2>&1
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

# Resolve Tailscale hostname to IP or DNS name; with fuzzy=false only exact
# names match, not near misses
# Usage: resolve_tailscale_host <hostname> [verbose] [fuzzy]
resolve_tailscale_host() {
    local search_hostname="$1"
    local verbose="${2:-false}"
    local fuzzy="${3:-true}"

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
    if _magicdns_enabled "$tailscale_json"; then
        magicdns_enabled="true"
    fi
    
    [[ "$verbose" == "true" ]] && echo "[DEBUG] MagicDNS enabled: $magicdns_enabled" >&2
    [[ "$verbose" == "true" ]] && echo "[DEBUG] Searching for hostname: $hostname_only" >&2
    
    # Try exact match first (case-insensitive, device hostname or machine name)
    local result=$(echo "$tailscale_json" | jq -r --arg hostname "$hostname_only" --arg magicdns "$magicdns_enabled" '
        def names_lc: [(.HostName // ""), ((.DNSName // "") | split(".")[0])] | map(ascii_downcase) | map(select(. != ""));
        ($hostname | ascii_downcase) as $h |
        # Check Self host first
        (.Self | if (names_lc | index($h)) then
            "\(.TailscaleIPs[0]),\(.DNSName // .HostName),\(.OS),online,self"
        else empty end),
        # Check Peer hosts
        (.Peer | to_entries[] | .value |
            if (names_lc | index($h)) then
                "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end),\(.PublicKey)"
            else empty end
        )
    ' 2>/dev/null | head -1)
    
    if [[ -z "$result" ]] && [[ "$fuzzy" == "true" ]]; then
        # Try fuzzy matching
        [[ "$verbose" == "true" ]] && echo "[DEBUG] No exact match, trying fuzzy search..." >&2
        
        # Get all candidate names (device hostnames and machine names, lowercased)
        local all_hosts=$(echo "$tailscale_json" | jq -r '
            (.Self, (.Peer | to_entries[] | .value)) |
            (.HostName // ""), ((.DNSName // "") | split(".")[0]) |
            select(. != "") | ascii_downcase
        ' 2>/dev/null | sort -u)

        local best_match=""
        local best_distance=999
        local needle_lc=$(printf '%s' "$hostname_only" | tr '[:upper:]' '[:lower:]')

        while IFS= read -r host; do
            [[ -z "$host" ]] && continue
            local distance=$(_levenshtein "$needle_lc" "$host")
            if [[ $distance -lt $best_distance ]]; then
                best_distance=$distance
                best_match=$host
            fi
        done <<< "$all_hosts"
        
        if [[ -n "$best_match" ]] && [[ $best_distance -le 5 ]]; then
            [[ "$verbose" == "true" ]] && echo "[DEBUG] Best fuzzy match: $best_match (distance: $best_distance)" >&2
            
            # Get the full data for the best match
            result=$(echo "$tailscale_json" | jq -r --arg hostname "$best_match" --arg magicdns "$magicdns_enabled" '
                def names_lc: [(.HostName // ""), ((.DNSName // "") | split(".")[0])] | map(ascii_downcase) | map(select(. != ""));
                ($hostname | ascii_downcase) as $h |
                (.Self | if (names_lc | index($h)) then
                    "\(.TailscaleIPs[0]),\(.DNSName // .HostName),\(.OS),online,self"
                else empty end),
                (.Peer | to_entries[] | .value |
                    if (names_lc | index($h)) then
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
    if _magicdns_enabled "$tailscale_json"; then
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
    if _magicdns_enabled "$tailscale_json"; then
        magicdns_enabled="true"
    fi
    
    # Find all matching hosts (case-insensitive, device hostname or machine name),
    # excluding Mullvad exit nodes
    local matches=$(echo "$tailscale_json" | jq -r --arg pattern "$hostname_only" --arg magicdns "$magicdns_enabled" '
        def names_lc: [(.HostName // ""), ((.DNSName // "") | split(".")[0])] | map(ascii_downcase) | map(select(. != ""));
        ($pattern | ascii_downcase) as $p |
        # Check Self host
        (.Self | if (names_lc | any(contains($p))) then
            "\(.TailscaleIPs[0]),\(.DNSName // .HostName),\(.OS),online"
        else empty end),
        # Check Peer hosts (excluding Mullvad exit nodes)
        (.Peer | to_entries[] | .value |
            select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not)) |
            if (names_lc | any(contains($p))) then
                "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end)"
            else empty end
        )
    ' 2>/dev/null)
    
    # If no matches with contains, try exact match
    if [[ -z "$matches" ]]; then
        matches=$(echo "$tailscale_json" | jq -r --arg hostname "$hostname_only" --arg magicdns "$magicdns_enabled" '
            def names_lc: [(.HostName // ""), ((.DNSName // "") | split(".")[0])] | map(ascii_downcase) | map(select(. != ""));
            ($hostname | ascii_downcase) as $h |
            # Check Self host
            (.Self | if (names_lc | index($h)) then
                "\(.TailscaleIPs[0]),\(.DNSName // .HostName),\(.OS),online"
            else empty end),
            # Check Peer hosts (excluding Mullvad exit nodes)
            (.Peer | to_entries[] | .value |
                select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not)) |
                if (names_lc | index($h)) then
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
    if _magicdns_enabled "$tailscale_json"; then
        magicdns_enabled="true"
    fi
    
    # Convert shell wildcard pattern to regex pattern
    local regex_pattern="${search_pattern//\*/.*}"
    
    # Use jq to find matching hosts - allow more permissive pattern matching for multi-host commands
    echo "$tailscale_json" | jq -r --arg pattern "$regex_pattern" --arg magicdns "$magicdns_enabled" '
        def names: [(.HostName // ""), ((.DNSName // "") | split(".")[0])] | map(select(. != ""));
        # Extract Self host if it matches
        (.Self | if (names | any(test($pattern; "i"))) then
            "\(.TailscaleIPs[0]),\(.DNSName // .HostName),\(.OS),online"
        else empty end),
        # Extract matching Peer hosts (excluding Mullvad exit nodes)
        (.Peer | to_entries[] | .value |
            select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not)) |
            if (names | any(test($pattern; "i"))) then
                "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end)"
            else empty end
        )
    ' 2>/dev/null || {
        # Fallback: try basic pattern matching without regex (excluding Mullvad exit nodes)
        echo "$tailscale_json" | jq -r --arg pattern "$search_pattern" '
            # Simple fallback - check if either name contains the pattern (without wildcards)
            (.Self, (.Peer | to_entries[] | .value |
                select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not))
            )) |
            (.HostName // ""), ((.DNSName // "") | split(".")[0]) |
            select(. != "") |
            select(ascii_downcase | contains($pattern | ascii_downcase))' 2>/dev/null | sort -u | head -5
    }
}

# Interactive host resolution with selection menu
# Usage: resolve_host_interactive <hostname> <context_label>
# Outputs: resolved hostname or IP (with user@ prefix if applicable)
# Returns: 0 on success, 1 on failure
resolve_host_interactive() {
    local search_input="$1"
    local context_label="${2:-}"

    # Check if user wants to use MagicDNS (opt-in)
    local use_magicdns="${TAILSCALE_USE_MAGICDNS:-false}"
    case "$use_magicdns" in
        true|1|yes|YES|True|TRUE) use_magicdns=true ;;
        *) use_magicdns=false ;;
    esac

    # ANSI color codes
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local RESET='\033[0m'

    # Parse user@host format
    local user_prefix=""
    local search_hostname="$search_input"
    if [[ "$search_input" == *"@"* ]]; then
        user_prefix="${search_input%%@*}@"
        search_hostname="${search_input#*@}"
    fi

    # Find all matching hosts
    local matching_hosts=()
    local matches
    matches=$(find_all_matching_hosts "$search_hostname")

    if [[ -n "$matches" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && matching_hosts+=("$line")
        done <<< "$matches"
    fi

    if [[ ${#matching_hosts[@]} -eq 0 ]]; then
        echo "Host '$search_hostname' not found in Tailscale network" >&2
        return 1
    elif [[ ${#matching_hosts[@]} -eq 1 ]]; then
        # Single match - use directly
        local host_info="${matching_hosts[0]}"
        local ip=$(echo "$host_info" | cut -d ',' -f 1)
        local real_hostname=$(echo "$host_info" | cut -d ',' -f 2)

        if [[ "$use_magicdns" == "true" ]] && is_magicdns_working; then
            echo -e "${GREEN}[TS]${RESET} Resolved ${GREEN}${search_hostname}${RESET} -> ${GREEN}${real_hostname}${RESET} (${ip})" >&2
            echo "${user_prefix}${real_hostname}"
        else
            echo -e "${GREEN}[TS]${RESET} Resolved ${GREEN}${search_hostname}${RESET} -> ${GREEN}${ip}${RESET} (${real_hostname})" >&2
            echo "${user_prefix}${ip}"
        fi
        return 0
    else
        # Multiple matches - show selection menu with context
        if [[ -n "$context_label" ]]; then
            echo -e "${YELLOW}Resolving host for:${RESET} ${context_label}" >&2
        fi
        echo "Multiple hosts found matching '$search_hostname':" >&2

        # Sort hosts: online first, then offline
        local online_hosts=()
        local offline_hosts=()

        for host in "${matching_hosts[@]}"; do
            local host_status=$(echo "$host" | cut -d ',' -f 4)
            if [[ "$host_status" == "offline" ]]; then
                offline_hosts+=("$host")
            else
                online_hosts+=("$host")
            fi
        done

        local sorted_hosts=("${online_hosts[@]}" "${offline_hosts[@]}")

        # Display options
        for i in "${!sorted_hosts[@]}"; do
            local host_info="${sorted_hosts[$i]}"
            local host_ip=$(echo "$host_info" | cut -d ',' -f 1)
            local host_name=$(echo "$host_info" | cut -d ',' -f 2)
            local host_os=$(echo "$host_info" | cut -d ',' -f 3)
            local host_status=$(echo "$host_info" | cut -d ',' -f 4)

            echo -e "${GREEN}[$((i+1))]${RESET} $host_name ($host_ip) - $host_os - $host_status" >&2
        done

        # Get selection
        local selection
        if [ -t 0 ]; then
            read -p "Select host number ([1]-${#sorted_hosts[@]}): " selection </dev/tty
        else
            echo "Non-interactive mode, selecting first match" >&2
            selection=1
        fi

        if [ -z "$selection" ]; then
            selection=1
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#sorted_hosts[@]}" ]; then
            local selected_host="${sorted_hosts[$((selection-1))]}"
            local selected_ip=$(echo "$selected_host" | cut -d ',' -f 1)
            local selected_hostname=$(echo "$selected_host" | cut -d ',' -f 2)

            if [[ "$use_magicdns" == "true" ]] && is_magicdns_working; then
                echo "${user_prefix}${selected_hostname}"
            else
                echo "${user_prefix}${selected_ip}"
            fi
            return 0
        else
            echo "Invalid selection" >&2
            return 1
        fi
    fi
}

# Resolve the hops of an ssh -J (ProxyJump) spec: comma-separated
# [user@]host[:port] or ssh://[user@]host[:port] entries. Hops naming a
# Tailscale node become its IP (or MagicDNS name), connecting as default_user
# when no user is given; addresses and other names pass through.
# Usage: resolve_jump_hosts <spec> [default_user]
# Outputs: the spec with Tailscale hops resolved
resolve_jump_hosts() {
    local spec="$1"
    local default_prefix="${2:+$2@}"
    local hops=()
    local resolved_hops=()
    local hop scheme user_prefix host port_suffix resolved

    # "none" turns jumping off
    if [[ "$spec" == [Nn][Oo][Nn][Ee] ]]; then
        echo "$spec"
        return 0
    fi

    IFS=',' read -r -a hops <<< "$spec"
    for hop in "${hops[@]}"; do
        scheme=""
        user_prefix=""
        port_suffix=""
        host="$hop"
        if [[ "$host" == "ssh://"* ]]; then
            scheme="ssh://"
            host="${host#ssh://}"
        fi
        if [[ "$host" == *"@"* ]]; then
            user_prefix="${host%@*}@"
            host="${host##*@}"
        fi
        if [[ "$host" == *":"* ]] && [[ "$host" != "["* ]]; then
            port_suffix=":${host#*:}"
            host="${host%%:*}"
        fi

        # IPv4 addresses need no lookup; bracketed IPv6 fails validation
        if [[ "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || ! _validate_hostname "$host"; then
            resolved_hops+=("$hop")
        elif resolved=$(resolve_host_interactive "$host" "jump host $spec"); then
            resolved_hops+=("${scheme}${user_prefix:-$default_prefix}${resolved}${port_suffix}")
        else
            resolved_hops+=("$hop")
        fi
    done

    local IFS=','
    echo "${resolved_hops[*]}"
}

# Get the jump host spec from an ssh -o option if it is a ProxyJump
# ("ProxyJump=spec" or "ProxyJump spec", keyword in any case)
_proxy_jump_spec() {
    local option="$1"
    local keyword="${option%%[=[:space:]]*}"
    [[ "$keyword" != "$option" ]] || return 1
    [[ "$keyword" == [Pp][Rr][Oo][Xx][Yy][Jj][Uu][Mm][Pp] ]] || return 1
    local spec="${option#"$keyword"}"
    echo "${spec#"${spec%%[![:space:]=]*}"}"
}

# Resolve the jump hosts in ssh-style options (-J <spec>, -J<spec>,
# -o ProxyJump=<spec>, -oProxyJump=<spec>) and leave the arguments in the
# JUMP_ARGS array. Jump options come out as -J <spec> or -o ProxyJump=<spec>;
# all other arguments are kept as given. Pass options only, not a remote
# command whose words could look like options.
# Usage: resolve_jump_args <default_user> <args...>
# Returns: 0 if the arguments name a jump host, 1 otherwise
resolve_jump_args() {
    local default_user="$1"
    shift
    local jumping=1
    local arg option value spec
    JUMP_ARGS=()

    while [[ $# -gt 0 ]]; do
        arg="$1"
        shift
        case "$arg" in
            --)
                JUMP_ARGS+=("$arg" "$@")
                break
                ;;
            -J|-o)
                if [[ $# -eq 0 ]]; then
                    JUMP_ARGS+=("$arg")
                    break
                fi
                option="$arg"
                value="$1"
                shift
                ;;
            -J?*|-o?*)
                option="${arg:0:2}"
                value="${arg:2}"
                ;;
            *)
                JUMP_ARGS+=("$arg")
                continue
                ;;
        esac

        if [[ "$option" == "-J" ]]; then
            spec="$value"
        elif ! spec=$(_proxy_jump_spec "$value"); then
            # Some other -o option, kept in its original form
            if [[ "$arg" == "-o" ]]; then
                JUMP_ARGS+=(-o "$value")
            else
                JUMP_ARGS+=("$arg")
            fi
            continue
        fi

        [[ "$spec" == [Nn][Oo][Nn][Ee] ]] || jumping=0
        spec=$(resolve_jump_hosts "$spec" "$default_user")
        if [[ "$option" == "-J" ]]; then
            JUMP_ARGS+=(-J "$spec")
        else
            JUMP_ARGS+=(-o "ProxyJump=$spec")
        fi
    done

    return $jumping
}

# Get all Tailscale hosts for completion
get_all_tailscale_hosts() {
    local prefix="${1:-}"
    local prefix_pattern="${2:-}"
    
    local tailscale_json
    tailscale_json=$(tailscale status --json 2>/dev/null) || return 1
    
    _validate_tailscale_json "$tailscale_json" || return 1
    
    # Extract all node names, excluding Mullvad exit nodes. Prefer the machine
    # name (first DNSName label) - it is what MagicDNS and tailscale status show
    # and stays valid after a machine is renamed; fall back to the device hostname.
    local hosts=$(echo "$tailscale_json" | jq -r '
        (.Self, (.Peer | to_entries[] | .value |
            select(.Tags == null or (.Tags | contains(["tag:mullvad-exit-node"]) | not))
        )) |
        (((.DNSName // "") | split(".")[0]) as $mn | if $mn != "" then $mn else (.HostName // "") end) |
        select(. != "")
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