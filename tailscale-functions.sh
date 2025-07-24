# Tailscale CLI helpers - Main functions
# This file provides the core ts and ssh functionality

# Detect shell type for compatibility
if [[ -n "$ZSH_VERSION" ]]; then
    _IS_ZSH=true
else
    _IS_ZSH=false
fi

# Security: Input validation functions
_dcs_validate_hostname() {
    local hostname="$1"
    # Allow only alphanumeric chars, dots, hyphens, and underscores
    # Prevent command injection and path traversal
    [[ -n "$hostname" ]] || return 1
    [[ "$hostname" =~ ^[a-zA-Z0-9._-]+$ ]] || return 1
    [[ ${#hostname} -le 253 ]] || return 1  # RFC 1035 limit
    return 0
}

# Security: Validate Tailscale JSON structure
_dcs_validate_tailscale_json() {
    local json="$1"
    [[ -n "$json" ]] || return 1
    # Verify basic structure exists
    echo "$json" | jq -e '.Self and .Peer and .CurrentTailnet' >/dev/null 2>&1
}

# Security: Sanitize jq filter patterns
_dcs_sanitize_pattern() {
    local pattern="$1"
    # Remove any potentially dangerous characters for regex patterns
    echo "$pattern" | sed 's/[^a-zA-Z0-9._-]//g'
}

# Parse JSON to find a specific host and extract its data
_dcs_find_host_in_json() {
    local json="$1"
    local search_hostname="$2"
    local magicdns_enabled="$3"
    
    # Security: Validate inputs
    _dcs_validate_hostname "$search_hostname" || return 1
    _dcs_validate_tailscale_json "$json" || return 1
    
    # Security: Use jq --arg to prevent injection
    local result=$(echo "$json" | jq -r --arg hostname "$search_hostname" --arg magicdns "$magicdns_enabled" '
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
    
    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi
    
    return 1
}

# Find all hosts matching a pattern
_dcs_find_hosts_matching() {
    local json="$1"
    local search_pattern="$2"
    local magicdns_enabled="$3"
    
    # Security: Validate inputs
    _dcs_validate_hostname "$search_pattern" || return 1
    _dcs_validate_tailscale_json "$json" || return 1
    
    # Security: Sanitize pattern for regex use
    local safe_pattern=$(_dcs_sanitize_pattern "$search_pattern")
    
    # Security: Use jq --arg to prevent injection
    echo "$json" | jq -r --arg pattern "$safe_pattern" --arg magicdns "$magicdns_enabled" '
        # Extract Self host if it matches
        (if (.Self.HostName | test($pattern)) then 
            "\(.Self.TailscaleIPs[0]),\(.Self.DNSName // .Self.HostName),\(.Self.OS),online,self"
        else empty end),
        # Extract matching Peer hosts  
        (.Peer | to_entries[] | .value | 
            if (.HostName | test($pattern)) then
                "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end),\(.PublicKey)"
            else empty end
        )
    ' 2>/dev/null || {
        # Security: Safe fallback without pattern injection
        echo "$json" | jq -r --arg pattern "$safe_pattern" '
            (.Self.HostName), (.Peer | to_entries[] | .value.HostName) | 
            select(test($pattern))' 2>/dev/null | head -1
    }
}

# Levenshtein distance function for fuzzy matching
_dcs_levenshtein() {
    local str1="$1"
    local str2="$2"
    
    local len1=${#str1}
    local len2=${#str2}
    
    # Create matrix - use associative array for compatibility
    if [[ "$_IS_ZSH" == "true" ]]; then
        typeset -A matrix
    else
        declare -A matrix
    fi
    
    # Initialize first row and column
    for ((i=0; i<=len1; i++)); do
        matrix[$i,0]=$i
    done
    
    for ((j=0; j<=len2; j++)); do
        matrix[0,$j]=$j
    done
    
    # Fill matrix
    for ((i=1; i<=len1; i++)); do
        for ((j=1; j<=len2; j++)); do
            local cost=1
            if [[ "${str1:$((i-1)):1}" == "${str2:$((j-1)):1}" ]]; then
                cost=0
            fi
            
            local deletion=$((matrix[$((i-1)),$j] + 1))
            local insertion=$((matrix[$i,$((j-1))] + 1))
            local substitution=$((matrix[$((i-1)),$((j-1))] + cost))
            
            local min=$deletion
            if [[ $insertion -lt $min ]]; then
                min=$insertion
            fi
            if [[ $substitution -lt $min ]]; then
                min=$substitution
            fi
            
            matrix[$i,$j]=$min
        done
    done
    
    echo ${matrix[$len1,$len2]}
}

# Check if MagicDNS is enabled
_dcs_is_magicdns_enabled() {
    local ts_json
    if ! ts_json=$(tailscale status --json 2>/dev/null) || ! _dcs_validate_tailscale_json "$ts_json"; then
        return 1
    fi
    local enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
    
    if [[ "$enabled" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Check if MagicDNS is properly configured in resolv.conf
_dcs_is_magicdns_working() {
    # Check if MagicDNS is enabled first
    if ! _dcs_is_magicdns_enabled; then
        return 1
    fi
    
    # Security: Safe check for Tailscale DNS configuration
    # Use fixed string matching to prevent injection
    if [[ -r /etc/resolv.conf ]]; then
        grep -Fxq "nameserver 100.100.100.100" /etc/resolv.conf 2>/dev/null || \
        grep -q "^nameserver 100\.100\.100\.100" /etc/resolv.conf 2>/dev/null
    else
        return 1
    fi
}

# Main Tailscale SSH function
tssh_main() {
    local debug=false
    local input=""
    local hostname=""
    local user="root"
    local search_pattern=""
    
    # ANSI color codes
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local YELLOW='\033[0;33m'
    local RESET='\033[0m'
    
    # Check for debug flag
    if [[ "$1" == "-v" ]]; then
        debug=true
        shift
    fi
    
    input=$1
    
    if [ -z "$input" ]; then
        echo "Usage: tssh [-v] <user@hostname>"
        echo "  -v  Enable verbose debug output"
        return 1
    fi
    
    # Parse user@host format
    if [[ "$input" == *"@"* ]]; then
        user=${input%%@*}
        hostname=${input#*@}
        search_pattern="$hostname"
    else
        hostname=$input
        search_pattern="$hostname"
    fi
    
    # Security: Get tailscale JSON status with validation
    local ts_json
    if ! ts_json=$(tailscale status --json 2>/dev/null); then
        echo "Failed to get Tailscale status. Is Tailscale running?" >&2
        return 1
    fi
    
    if [[ -z "$ts_json" ]]; then
        echo "No Tailscale hosts found. Is Tailscale running?" >&2
        return 1
    fi
    
    # Security: Validate JSON structure
    if ! _dcs_validate_tailscale_json "$ts_json"; then
        echo "Invalid Tailscale status format" >&2
        return 1
    fi
    
    # Check MagicDNS status once
    local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
    
    if [ "$debug" = true ]; then
        echo -e "${YELLOW}[DEBUG]${RESET} Searching for: '$search_pattern'"
    fi
    
    # Find all matching hosts and sort by Levenshtein distance
    local all_matches=()
    local matching_hosts=()
    
    # Handle process substitution compatibility
    if [[ "$_IS_ZSH" == "true" ]]; then
        # zsh needs different handling for process substitution with arrays
        local matches_output
        matches_output=$(_dcs_find_hosts_matching "$ts_json" "$search_pattern" "$magicdns_enabled")
        if [[ -n "$matches_output" ]]; then
            while IFS= read -r match; do
                if [[ -n "$match" ]]; then
                    all_matches+=("$match")
                fi
            done <<< "$matches_output"
        fi
    else
        while IFS= read -r match; do
            if [[ -n "$match" ]]; then
                all_matches+=("$match")
            fi
        done < <(_dcs_find_hosts_matching "$ts_json" "$search_pattern" "$magicdns_enabled")
    fi
    
    # If we have matches, sort them by Levenshtein distance
    if [[ ${#all_matches[@]} -gt 0 ]]; then
        local distance_matches=()
        
        # Calculate Levenshtein distance for each match
        for match in "${all_matches[@]}"; do
            local match_hostname=$(echo "$match" | cut -d',' -f2)
            local distance=$(_dcs_levenshtein "$search_pattern" "$match_hostname")
            distance_matches+=("$distance:$match")
        done
        
        # Sort by distance (lowest first)
        # Sort array in a shell-compatible way
        if [[ "$_IS_ZSH" == "true" ]]; then
            # zsh array sorting
            distance_matches=("${(@f)$(printf '%s\n' "${distance_matches[@]}" | sort -n)}")
        else
            # bash array sorting
            IFS=$'\n' distance_matches=($(sort -n <<< "${distance_matches[*]}"))
        fi
        
        # Extract the sorted matches
        for entry in "${distance_matches[@]}"; do
            matching_hosts+=("${entry#*:}")
        done
    fi
    
    if [ "$debug" = true ]; then
        echo -e "${YELLOW}[DEBUG]${RESET} Found ${#all_matches[@]} matches, sorted by Levenshtein distance"
    fi
    
    # Handle results
    if [[ ${#matching_hosts[@]} -eq 0 ]]; then
        echo "Host not found in Tailscale network, checking known_hosts..."
        
        if [[ -r ~/.ssh/known_hosts ]] && _dcs_validate_hostname "$search_pattern"; then
            if grep -Fq "$search_pattern" ~/.ssh/known_hosts 2>/dev/null; then
                echo -e "${BLUE}[SSH]${RESET} Found in known_hosts, connecting to ${BLUE}$user@$hostname${RESET}..."
                # Security: Use -- to prevent hostname being interpreted as option
                ssh -- "$user@$hostname"
                return $?
            else
                echo "Host not found in known_hosts either" >&2
                return 1
            fi
        else
            echo "Host not found and cannot access known_hosts" >&2
            return 1
        fi
    elif [[ ${#matching_hosts[@]} -eq 1 ]]; then
        # Single match
        local host_info="${matching_hosts[0]}"
        local ip=$(echo "$host_info" | cut -d ',' -f 1)
        local real_hostname=$(echo "$host_info" | cut -d ',' -f 2)
        
        if _dcs_is_magicdns_working; then
            # MagicDNS is properly configured - use DNS name
            echo -e "${GREEN}[TS]${RESET} Connecting to ${GREEN}$user@$real_hostname${RESET} (${ip})..."
            # Security: Use -- to prevent arguments being interpreted as options
            ssh -- "$user@$real_hostname"
        else
            # MagicDNS not working - use IP address
            echo -e "${GREEN}[TS]${RESET} Connecting to ${GREEN}$user@$real_hostname${RESET} (${ip})..."
            if [[ "$magicdns_enabled" == "true" ]]; then
                echo "Note: MagicDNS is enabled but resolv.conf is not configured properly. Using IP address."
            fi
            # Security: Use -- to prevent arguments being interpreted as options
            ssh -- "$user@$ip"
        fi
    else
        # Multiple matches
        echo "Multiple hosts found matching '$hostname':"
        
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
            
            echo -e "${GREEN}[$((i+1))]${RESET} $host_name ($host_ip) - $host_os - $host_status"
        done
        
        # Get selection
        if [ -t 0 ]; then
            read -p "Select host number ([1]-${#sorted_hosts[@]}): " selection
        else
            echo "Non-interactive mode, selecting first match"
            selection=1
        fi
        
        if [ -z "$selection" ]; then
            selection=1
        fi
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#sorted_hosts[@]}" ]; then
            local selected_host="${sorted_hosts[$((selection-1))]}"
            local selected_ip=$(echo "$selected_host" | cut -d ',' -f 1)
            local selected_hostname=$(echo "$selected_host" | cut -d ',' -f 2)
            
            if _dcs_is_magicdns_working; then
                # MagicDNS is properly configured - use DNS name
                echo -e "${GREEN}[TS]${RESET} Connecting to ${GREEN}$user@$selected_hostname${RESET} (${selected_ip})..."
                # Security: Use -- to prevent arguments being interpreted as options
                ssh -- "$user@$selected_hostname"
            else
                # MagicDNS not working - use IP address
                echo -e "${GREEN}[TS]${RESET} Connecting to ${GREEN}$user@$selected_hostname${RESET} (${selected_ip})..."
                if [[ "$magicdns_enabled" == "true" ]]; then
                    echo "Note: MagicDNS is enabled but resolv.conf is not configured properly. Using IP address."
                fi
                # Security: Use -- to prevent arguments being interpreted as options
                ssh -- "$user@$selected_ip"
            fi
        else
            echo "Invalid selection"
            return 1
        fi
    fi
}

# Create wrapper functions
tssh() {
    tssh_main "$@"
}

# ts alias for backward compatibility
ts() {
    tssh_main "$@"
}

# Create ssh-copy-id aliases
alias ssh-copy-id='dcs_ssh_copy_id'
alias tssh-copy-id='dcs_ssh_copy_id'

# Enhanced ssh-copy-id with Tailscale support
dcs_ssh_copy_id() {
    local args=()
    local i=1
    local use_proxy_jump=false
    local jumphost=""
    local verbose=false
    local target_host=""
    local user="root"
    
    # ANSI color codes
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local RESET='\033[0m'

    # Check for verbose flag
    for arg in "$@"; do
        if [[ "$arg" == "-v" ]]; then
            verbose=true
            break
        fi
    done

    while [ $i -le $# ]; do
        local arg="${!i}"

        if [[ "$arg" == "-J" ]]; then
            use_proxy_jump=true
            ((i++))
            jumphost="${!i}"
        elif [[ "$arg" != "-v" && ! "$arg" =~ ^- && -z "$target_host" ]]; then
            target_host="$arg"
            args+=("$arg")
        else
            args+=("$arg")
        fi
        ((i++))
    done

    # Security: Function to safely check if IP is in Tailscale range
    is_tailscale_ip() {
        local ip="$1"
        
        # Validate IP format with safer pattern
        if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            return 1
        fi
        
        # Extract octets safely
        local IFS='.'
        local octets=($ip)
        local first_octet=${octets[0]}
        local second_octet=${octets[1]}
        
        # Validate octet ranges
        if [[ "$first_octet" -lt 0 || "$first_octet" -gt 255 ]] || 
           [[ "$second_octet" -lt 0 || "$second_octet" -gt 255 ]]; then
            return 1
        fi
        
        # Check Tailscale range (100.64.0.0/10)
        if [[ "$first_octet" -eq 100 ]] && [[ "$second_octet" -ge 64 ]] && [[ "$second_octet" -le 127 ]]; then
            return 0
        fi
        
        return 1
    }

    # Function to resolve host using JSON
    resolve_host() {
        local input_host="$1"
        local host_user="root"
        local hostname=""
        local search_pattern=""
        
        # Parse user@host format
        if [[ "$input_host" == *"@"* ]]; then
            host_user=${input_host%%@*}
            hostname=${input_host#*@}
            search_pattern="$hostname"
        else
            hostname="$input_host"
            search_pattern="$hostname"
        fi
        
        # Security: Safe check of known_hosts with validated input
        if [[ -r ~/.ssh/known_hosts ]] && _dcs_validate_hostname "$search_pattern"; then
            if grep -Fq "$search_pattern " ~/.ssh/known_hosts 2>/dev/null || grep -Fq "$search_pattern," ~/.ssh/known_hosts 2>/dev/null; then
            if is_tailscale_ip "$search_pattern"; then
                # Security: Verify if Tailscale IP is still valid
                local ts_json
                if ts_json=$(tailscale status --json 2>/dev/null) && _dcs_validate_tailscale_json "$ts_json"; then
                    if echo "$ts_json" | jq -e --arg ip "$search_pattern" '.Self.TailscaleIPs[] == $ip or (.Peer | to_entries[] | .value.TailscaleIPs[] == $ip)' >/dev/null 2>&1; then
                        echo "$input_host"
                        return 0
                    fi
                fi
            else
                echo "$input_host"
                return 0
            fi
            fi
        elif _dcs_validate_hostname "$search_pattern" && (host "$search_pattern" >/dev/null 2>&1 || getent hosts "$search_pattern" >/dev/null 2>&1); then
            echo "$input_host"
            return 0
        else
            # Security: Try Tailscale safely
            local ts_json
            if ts_json=$(tailscale status --json 2>/dev/null) && _dcs_validate_tailscale_json "$ts_json"; then
                local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
                local host_data=$(_dcs_find_host_in_json "$ts_json" "$search_pattern" "$magicdns_enabled")
                if [[ -n "$host_data" ]]; then
                    local found_ip=$(echo "$host_data" | cut -d',' -f1)
                    local found_hostname=$(echo "$host_data" | cut -d',' -f2)
                    
                    if _dcs_is_magicdns_working; then
                        # MagicDNS is properly configured - return DNS name
                        echo "$host_user@$found_hostname"
                    else
                        # MagicDNS not working - return IP
                        echo "$host_user@$found_ip"
                    fi
                    return 0
                fi
            fi
            
            echo "$input_host"
            return 1
        fi
    }

    # Resolve jumphost if using proxy jump
    if [[ "$use_proxy_jump" == "true" && -n "$jumphost" ]]; then
        local resolved_jumphost=$(resolve_host "$jumphost")
        jumphost="$resolved_jumphost"
    fi

    # Resolve target host if not using proxy jump
    if [[ -n "$target_host" && "$use_proxy_jump" == "false" ]]; then
        local resolved_target=$(resolve_host "$target_host")
        
        # Replace the original target in args with resolved version
        local new_args=()
        for arg in "${args[@]}"; do
            if [[ "$arg" == "$target_host" ]]; then
                new_args+=("$resolved_target")
            else
                new_args+=("$arg")
            fi
        done
        args=("${new_args[@]}")
    fi

    if [[ "$use_proxy_jump" == "true" && -n "$jumphost" ]]; then
        command ssh-copy-id -o "ProxyJump=$jumphost" "${args[@]}"
    else
        command ssh-copy-id "${args[@]}"
    fi
}

# Tailscale SCP function
tscp_main() {
    # Simple wrapper that resolves Tailscale hostnames for scp
    local resolved_args=()
    
    for arg in "$@"; do
        if [[ "$arg" == *":"* ]] && [[ "$arg" != "-"* ]]; then
            # This looks like a remote host:path spec
            local host_part="${arg%%:*}"
            local path_part="${arg#*:}"
            local user="root"
            local hostname=""
            
            # Parse user@host format
            if [[ "$host_part" == *"@"* ]]; then
                user="${host_part%%@*}"
                hostname="${host_part#*@}"
            else
                hostname="$host_part"
            fi
            
            # Security: Try to resolve with Tailscale safely
            local ts_json
            if ts_json=$(tailscale status --json 2>/dev/null) && _dcs_validate_tailscale_json "$ts_json"; then
                local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
                local host_data=$(_dcs_find_host_in_json "$ts_json" "$hostname" "$magicdns_enabled")
                
                if [[ -n "$host_data" ]]; then
                    local found_ip=$(echo "$host_data" | cut -d',' -f1)
                    local found_hostname=$(echo "$host_data" | cut -d',' -f2)
                    
                    if _dcs_is_magicdns_working; then
                        resolved_args+=("${user}@${found_hostname}:${path_part}")
                    else
                        resolved_args+=("${user}@${found_ip}:${path_part}")
                    fi
                    continue
                fi
            fi
        fi
        
        # Use original argument if not resolved
        resolved_args+=("$arg")
    done
    
    # Security: Execute scp with resolved arguments safely
    if [[ ${#resolved_args[@]} -eq 0 ]]; then
        echo "Error: No arguments provided to scp" >&2
        return 1
    fi
    scp "${resolved_args[@]}"
}

# Create wrapper function
tscp() {
    tscp_main "$@"
}

# Tailscale rsync function
trsync_main() {
    # Simple wrapper that resolves Tailscale hostnames for rsync
    local resolved_args=()
    
    for arg in "$@"; do
        if [[ "$arg" == *":"* ]] && [[ "$arg" != "-"* ]]; then
            # This looks like a remote host:path spec
            local host_part="${arg%%:*}"
            local path_part="${arg#*:}"
            local user="root"
            local hostname=""
            
            # Parse user@host format
            if [[ "$host_part" == *"@"* ]]; then
                user="${host_part%%@*}"
                hostname="${host_part#*@}"
            else
                hostname="$host_part"
            fi
            
            # Security: Try to resolve with Tailscale safely
            local ts_json
            if ts_json=$(tailscale status --json 2>/dev/null) && _dcs_validate_tailscale_json "$ts_json"; then
                local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
                local host_data=$(_dcs_find_host_in_json "$ts_json" "$hostname" "$magicdns_enabled")
                
                if [[ -n "$host_data" ]]; then
                    local found_ip=$(echo "$host_data" | cut -d',' -f1)
                    local found_hostname=$(echo "$host_data" | cut -d',' -f2)
                    
                    if _dcs_is_magicdns_working; then
                        resolved_args+=("${user}@${found_hostname}:${path_part}")
                    else
                        resolved_args+=("${user}@${found_ip}:${path_part}")
                    fi
                    continue
                fi
            fi
        fi
        
        # Use original argument if not resolved
        resolved_args+=("$arg")
    done
    
    # Security: Execute rsync with resolved arguments safely
    if [[ ${#resolved_args[@]} -eq 0 ]]; then
        echo "Error: No arguments provided to rsync" >&2
        return 1
    fi
    rsync "${resolved_args[@]}"
}

# Create wrapper function
trsync() {
    trsync_main "$@"
}

# Helpful message when sourcing
if [[ "$_IS_ZSH" == "true" ]]; then
    # For zsh users - ensure compatibility mode is set
    if [[ -o SH_WORD_SPLIT ]]; then
        : # Already set, do nothing
    else
        echo "Note: Setting SH_WORD_SPLIT for bash compatibility" >&2
        setopt SH_WORD_SPLIT
    fi
fi

# Export functions for subshells
export -f tssh_main 2>/dev/null || true
export -f tssh 2>/dev/null || true
export -f ts 2>/dev/null || true
export -f dcs_ssh_copy_id 2>/dev/null || true
export -f tscp_main 2>/dev/null || true
export -f tscp 2>/dev/null || true
export -f trsync_main 2>/dev/null || true
export -f trsync 2>/dev/null || true