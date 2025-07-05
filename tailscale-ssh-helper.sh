# Detect shell type
if [[ -n "$ZSH_VERSION" ]]; then
    _IS_ZSH=true
else
    _IS_ZSH=false
fi

_dcs_ts_completions() {
    local cur prev opts
    
    # Handle shell-specific completion variables
    if [[ "$_IS_ZSH" == "true" ]]; then
        # zsh completion
        cur="${words[CURRENT]}"
        prev="${words[CURRENT-1]}"
    else
        # bash completion
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    
    # ANSI color codes for visual indicators
    local GREEN='\033[0;32m'  # Green for Tailscale
    local BLUE='\033[0;34m'   # Blue for direct SSH
    local RESET='\033[0m'     # Reset color
    
    # Check if first argument is -v
    local start_idx=1
    if [[ "$_IS_ZSH" == "true" ]]; then
        if [[ ${words[2]} == "-v" ]]; then
            start_idx=2
        fi
    else
        if [[ ${COMP_WORDS[1]} == "-v" ]]; then
            start_idx=2
        fi
    fi
    
    # If first argument position or we're completing a flag
    local current_word
    if [[ "$_IS_ZSH" == "true" ]]; then
        current_word=$CURRENT
    else
        current_word=$COMP_CWORD
    fi
    
    # Check if we're at the first argument position
    if [[ "$_IS_ZSH" == "true" ]]; then
        # zsh: CURRENT starts at 2 for first argument
        if [[ $current_word -eq 2 ]]; then
            # If it starts with -, suggest -v
            if [[ ${cur} == -* ]]; then
                compadd -- -v
                return 0
            fi
        fi
    else
        # bash: COMP_CWORD starts at 1 for first argument
        if [[ $current_word -eq 1 ]]; then
            # If it starts with -, suggest -v
            if [[ ${cur} == -* ]]; then
                COMPREPLY=( $(compgen -W "-v" -- ${cur}) )
                return 0
            fi
        fi
    fi
    
    # Complete hostnames
    local should_complete_host=false
    if [[ "$_IS_ZSH" == "true" ]]; then
        # zsh: CURRENT is 1-indexed
        if [[ ($CURRENT -eq 2 && ${cur} != -* ) || ($CURRENT -eq 3 && ${words[2]} == "-v") ]]; then
            should_complete_host=true
        fi
    else
        if [[ (${COMP_CWORD} -eq 1 && ${cur} != -* ) || (${COMP_CWORD} -eq 2 && ${COMP_WORDS[1]} == "-v") ]]; then
            should_complete_host=true
        fi
    fi
    
    if [[ "$should_complete_host" == "true" ]]; then
        # Common usernames to suggest
        local users=("root" "admin" "ubuntu" "ec2-user" "fedora" "centos")
        local default_user="root"
        
        # Get all available tailscale hosts using JSON
        local ts_hosts=()
        local ts_json=$(tailscale status --json 2>/dev/null)
        local unique_hosts=()
        
        if [[ -n "$ts_json" ]]; then
            # Check if MagicDNS is enabled
            local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
            
            if [[ "$magicdns_enabled" == "true" ]]; then
                # MagicDNS enabled - use full DNS names
                local dns_suffix=$(echo "$ts_json" | jq -r '.MagicDNSSuffix' 2>/dev/null)
                
                # Get self hostname with DNS suffix
                local self_host=$(echo "$ts_json" | jq -r '.Self.HostName' 2>/dev/null)
                if [[ -n "$self_host" && "$self_host" != "null" ]]; then
                    ts_hosts+=("${self_host}.${dns_suffix}")
                fi
                
                # Get peer DNS names (already include suffix)
                # Handle array assignment for both shells
                local peer_hosts
                if [[ "$_IS_ZSH" == "true" ]]; then
                    peer_hosts=(${(f)"$(echo "$ts_json" | jq -r '.Peer | to_entries[] | .value.DNSName | rtrimstr(".")' 2>/dev/null)"})
                else
                    peer_hosts=($(echo "$ts_json" | jq -r '.Peer | to_entries[] | .value.DNSName | rtrimstr(".")' 2>/dev/null))
                fi
                for host in "${peer_hosts[@]}"; do
                    if [[ -n "$host" && "$host" != "null" ]]; then
                        ts_hosts+=("$host")
                    fi
                done
            else
                # MagicDNS disabled - use short hostnames only
                # Handle array assignment for both shells
                if [[ "$_IS_ZSH" == "true" ]]; then
                    ts_hosts=(${(f)"$(echo "$ts_json" | jq -r '(.Self.HostName), (.Peer | to_entries[] | .value.HostName)' 2>/dev/null | grep -v "null" | sort -u)"})
                else
                    ts_hosts=($(echo "$ts_json" | jq -r '(.Self.HostName), (.Peer | to_entries[] | .value.HostName)' 2>/dev/null | grep -v "null" | sort -u))
                fi
            fi
            
            # Add all tailscale hosts to unique_hosts
            for host in "${ts_hosts[@]}"; do
                if [ -n "$host" ]; then
                    unique_hosts+=("$host")
                fi
            done
        fi
        
        # Check if current input contains @ (user@host format)
        if [[ "$cur" == *"@"* ]]; then
            local user_part=${cur%%@*}
            local host_part=${cur#*@}
            
            # Complete the hostname part
            local matches=()
            
            for host in "${unique_hosts[@]}"; do
                if [[ "$host" == "$host_part"* || "$host" == *"$host_part"* ]]; then
                    matches+=("$user_part@$host")
                fi
            done
            
            if [[ "$_IS_ZSH" == "true" ]]; then
                compadd -a matches
            else
                COMPREPLY=("${matches[@]}")
            fi
        else
            # If no @ yet, we could be typing a username or hostname
            # Try hostname completion
            local hostname_matches=()
            
            for host in "${unique_hosts[@]}"; do
                if [[ "$host" == "$cur"* || "$host" == *"$cur"* ]]; then
                    hostname_matches+=("$host")
                fi
            done
            
            if [[ "$_IS_ZSH" == "true" ]]; then
                if [[ ${#hostname_matches[@]} -gt 0 ]]; then
                    compadd -a hostname_matches
                fi
            else
                COMPREPLY=("${hostname_matches[@]}")
            fi
            
            # If no hostname matches, try common usernames with @ appended
            local has_matches=false
            if [[ "$_IS_ZSH" == "true" ]]; then
                # Check if we have hostname matches
                if [[ ${#hostname_matches[@]} -eq 0 ]]; then
                    for user in "${users[@]}"; do
                        if [[ "$user" == "$cur"* ]]; then
                            compadd -S @ -- "$user"
                        fi
                    done
                fi
            else
                if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
                    for user in "${users[@]}"; do
                        if [[ "$user" == "$cur"* ]]; then
                            COMPREPLY+=("$user@")
                        fi
                    done
                fi
            fi
        fi
    fi
    
    # Handle post-processing for bash
    if [[ "$_IS_ZSH" != "true" ]]; then
        # If single exact match, add a space
        if [[ ${#COMPREPLY[@]} -eq 1 && ! "${COMPREPLY[0]}" == *"@" ]]; then
            compopt -o nospace 2>/dev/null || true
            COMPREPLY=("${COMPREPLY[0]} ")
        fi
    fi
    
    return 0
}

# Register the completion function based on shell
if [[ "$_IS_ZSH" == "true" ]]; then
    # zsh completion wrapper
    _ts_zsh_completion() {
        local -a completions
        _dcs_ts_completions
        return 0
    }
    compdef _ts_zsh_completion ts
else
    # bash completion
    complete -F _dcs_ts_completions ts
fi

# Parse JSON to find a specific host and extract its data
_dcs_find_host_in_json() {
    local json="$1"
    local search_hostname="$2"
    local magicdns_enabled="$3"
    
    # Use jq to extract exact host match
    local result=$(echo "$json" | jq -r --arg magicdns "$magicdns_enabled" '
        # Check Self host first
        (if .Self.HostName == "'"$search_hostname"'" then 
            "\(.Self.TailscaleIPs[0]),\(.Self.DNSName // .Self.HostName),\(.Self.OS),online,self"
        else empty end),
        # Check Peer hosts
        (.Peer | to_entries[] | .value | 
            if .HostName == "'"$search_hostname"'" then
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
    
    # Use jq to extract host information properly
    echo "$json" | jq -r --arg magicdns "$magicdns_enabled" '
        # Extract Self host if it matches
        (if (.Self.HostName | test("'"$search_pattern"'")) then 
            "\(.Self.TailscaleIPs[0]),\(.Self.DNSName // .Self.HostName),\(.Self.OS),online,self"
        else empty end),
        # Extract matching Peer hosts  
        (.Peer | to_entries[] | .value | 
            if (.HostName | test("'"$search_pattern"'")) then
                "\(.TailscaleIPs[0]),\(if $magicdns == "true" then (.DNSName | rtrimstr(".")) else (.DNSName | split(".")[0]) end),\(.OS),\(if .Online or .Active then "online" else "offline" end),\(.PublicKey)"
            else empty end
        )
    ' 2>/dev/null || {
        # Fallback to grep-based approach if jq fails
        echo "$json" | grep -o '"HostName": *"[^"]*'"$search_pattern"'[^"]*"' | sed 's/.*"HostName": *"\([^"]*\)".*/\1/' | head -1
    }
}

dcs_ts() {
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
        echo "Usage: ts [-v] <user@hostname>"
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
    
    # Get tailscale JSON status once
    local ts_json=$(tailscale status --json 2>/dev/null)
    
    if [ -z "$ts_json" ]; then
        echo "No Tailscale hosts found. Is Tailscale running?"
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
        
        if grep -q "$search_pattern" ~/.ssh/known_hosts 2>/dev/null; then
            echo -e "${BLUE}[SSH]${RESET} Found in known_hosts, connecting to ${BLUE}$user@$hostname${RESET}..."
            ssh "$user@$hostname"
            return $?
        else
            echo "Host not found in known_hosts either"
            return 1
        fi
    elif [[ ${#matching_hosts[@]} -eq 1 ]]; then
        # Single match
        local host_info="${matching_hosts[0]}"
        local ip=$(echo "$host_info" | cut -d ',' -f 1)
        local real_hostname=$(echo "$host_info" | cut -d ',' -f 2)
        
        if [[ "$magicdns_enabled" == "true" ]]; then
            # MagicDNS enabled - use DNS name directly from the data
            echo -e "${GREEN}[TS]${RESET} Connecting to ${GREEN}$user@$real_hostname${RESET} (${ip})..."
            ssh "$user@$real_hostname"
        else
            # MagicDNS disabled - use IP but show hostname
            echo -e "${GREEN}[TS]${RESET} Connecting to ${GREEN}$user@$real_hostname${RESET} (${ip})..."
            ssh "$user@$ip"
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
            
            if [[ "$magicdns_enabled" == "true" ]]; then
                # MagicDNS enabled - use DNS name directly from the data
                echo -e "${GREEN}[TS]${RESET} Connecting to ${GREEN}$user@$selected_hostname${RESET} (${selected_ip})..."
                ssh "$user@$selected_hostname"
            else
                # MagicDNS disabled - use IP but show hostname
                echo -e "${GREEN}[TS]${RESET} Connecting to ${GREEN}$user@$selected_hostname${RESET} (${selected_ip})..."
                ssh "$user@$selected_ip"
            fi
        else
            echo "Invalid selection"
            return 1
        fi
    fi
}

# Create wrapper function
ts() {
    dcs_ts "$@"
}

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

    # Function to check if IP is in Tailscale range
    is_tailscale_ip() {
        local ip="$1"
        
        # Use a more compatible regex pattern
        if ! echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            return 1
        fi
        
        local first_octet=$(echo "$ip" | cut -d'.' -f1)
        local second_octet=$(echo "$ip" | cut -d'.' -f2)
        
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
        
        # First check known_hosts
        if grep -q "^$search_pattern " ~/.ssh/known_hosts 2>/dev/null || grep -q "^$search_pattern," ~/.ssh/known_hosts 2>/dev/null; then
            if is_tailscale_ip "$search_pattern"; then
                # Verify if Tailscale IP is still valid
                local ts_json=$(tailscale status --json 2>/dev/null)
                if [[ -n "$ts_json" ]] && echo "$ts_json" | grep -q "\"$search_pattern\""; then
                    echo "$input_host"
                    return 0
                fi
            else
                echo "$input_host"
                return 0
            fi
        elif host "$search_pattern" >/dev/null 2>&1 || getent hosts "$search_pattern" >/dev/null 2>&1; then
            echo "$input_host"
            return 0
        else
            # Try Tailscale
            local ts_json=$(tailscale status --json 2>/dev/null)
            if [[ -n "$ts_json" ]]; then
                local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
                local host_data=$(_dcs_find_host_in_json "$ts_json" "$search_pattern" "$magicdns_enabled")
                if [[ -n "$host_data" ]]; then
                    local found_ip=$(echo "$host_data" | cut -d',' -f1)
                    local found_hostname=$(echo "$host_data" | cut -d',' -f2)
                    
                    if [[ "$magicdns_enabled" == "true" ]]; then
                        # MagicDNS enabled - return DNS name
                        echo "$host_user@$found_hostname"
                    else
                        # MagicDNS disabled - return IP
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

# Check if MagicDNS is enabled
_dcs_is_magicdns_enabled() {
    local ts_json=$(tailscale status --json 2>/dev/null)
    local enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
    
    if [[ "$enabled" == "true" ]]; then
        return 0
    else
        return 1
    fi
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
export -f dcs_ts 2>/dev/null || true
export -f ts 2>/dev/null || true
export -f dcs_ssh_copy_id 2>/dev/null || true