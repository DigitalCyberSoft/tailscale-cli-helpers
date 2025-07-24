# Tailscale CLI helpers - Bash/Zsh completion functions
# This file provides tab completion for the ts command

# Detect shell type
if [[ -n "$ZSH_VERSION" ]]; then
    _IS_ZSH=true
else
    _IS_ZSH=false
fi

# Helper function to build available subcommands list
_dcs_build_subcommands() {
    local subcommands=("ssh")
    if [[ "$_HAS_SCP" == "true" ]]; then
        subcommands+=("scp")
    fi
    if [[ "$_HAS_SFTP" == "true" ]]; then
        subcommands+=("sftp")
    fi
    if [[ "$_HAS_RSYNC" == "true" ]]; then
        subcommands+=("rsync")
    fi
    subcommands+=("ssh_copy_id")
    if [[ "$_HAS_MUSSH" == "true" ]]; then
        subcommands+=("mussh")
    fi
    printf '%s\n' "${subcommands[@]}"
}

# Helper function to get Tailscale hosts
_dcs_get_tailscale_hosts() {
    local ts_hosts=()
    local ts_json
    
    # Security: Validate JSON before processing
    if ! ts_json=$(tailscale status --json 2>/dev/null); then
        return 1
    fi
    
    # Basic JSON validation
    if ! echo "$ts_json" | jq -e '.Self and .Peer' >/dev/null 2>&1; then
        return 1
    fi
    
    if [[ -n "$ts_json" ]]; then
        # Check if MagicDNS is enabled
        local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
        
        if [[ "$magicdns_enabled" == "true" ]]; then
            # Get self hostname
            local self_host=$(echo "$ts_json" | jq -r '.Self.HostName' 2>/dev/null)
            if [[ -n "$self_host" && "$self_host" != "null" ]]; then
                ts_hosts+=("$self_host")
            fi
            
            # Get peer hostnames
            local peer_hosts
            if [[ "$_IS_ZSH" == "true" ]]; then
                peer_hosts=(${(f)"$(echo "$ts_json" | jq -r '.Peer | to_entries[] | .value.HostName' 2>/dev/null)"})
            else
                peer_hosts=($(echo "$ts_json" | jq -r '.Peer | to_entries[] | .value.HostName' 2>/dev/null))
            fi
            for host in "${peer_hosts[@]}"; do
                if [[ -n "$host" && "$host" != "null" ]]; then
                    ts_hosts+=("$host")
                fi
            done
        else
            # MagicDNS disabled - use short hostnames only
            if [[ "$_IS_ZSH" == "true" ]]; then
                ts_hosts=(${(f)"$(echo "$ts_json" | jq -r '(.Self.HostName), (.Peer | to_entries[] | .value.HostName)' 2>/dev/null | grep -v "null" | sort -u)"})
            else
                ts_hosts=($(echo "$ts_json" | jq -r '(.Self.HostName), (.Peer | to_entries[] | .value.HostName)' 2>/dev/null | grep -v "null" | sort -u))
            fi
        fi
    fi
    
    printf '%s\n' "${ts_hosts[@]}"
}

# Helper function to sort hostnames by Levenshtein distance for better completion
_dcs_sort_hosts_by_distance() {
    local cur="$1"
    local hosts="$2"
    
    if [[ -n "$cur" && "$cur" != "" ]]; then
        # Sort by Levenshtein distance
        local distance_matches=()
        while IFS= read -r host; do
            if [[ -n "$host" ]]; then
                local distance=$(_dcs_levenshtein "$cur" "$host")
                distance_matches+=("$distance:$host")
            fi
        done <<< "$hosts"
        
        # Sort by distance (lowest first)
        if [[ "$_IS_ZSH" == "true" ]]; then
            distance_matches=("${(@f)$(printf '%s\n' "${distance_matches[@]}" | sort -n)}")
        else
            IFS=$'\n' distance_matches=($(sort -n <<< "${distance_matches[*]}"))
        fi
        
        # Extract the sorted hostnames
        local sorted_hosts=()
        for entry in "${distance_matches[@]}"; do
            sorted_hosts+=("${entry#*:}")
        done
        
        printf '%s\n' "${sorted_hosts[@]}"
    else
        # No current input, return hosts in original order
        printf '%s\n' "$hosts"
    fi
}

# Helper function to complete hostnames with Levenshtein sorting
_dcs_complete_hosts() {
    local cur="$1"
    local hosts sorted_hosts_output
    hosts=$(_dcs_get_tailscale_hosts)
    sorted_hosts_output=$(_dcs_sort_hosts_by_distance "$cur" "$hosts")
    
    if [[ "$_IS_ZSH" == "true" ]]; then
        compadd -- ${(f)sorted_hosts_output}
    else
        COMPREPLY=( $(compgen -W "$sorted_hosts_output" -- "$cur") )
    fi
}

# Completion function specifically for tmussh command
_tmussh_completions() {
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
    
    # Detect mussh version and set appropriate options based on CHANGES file
    local mussh_version
    mussh_version=$(mussh -V 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\|[0-9]\+\.[0-9]\+' | head -1)
    
    # Base options available in all versions (v1.0+)
    opts="-h -H -c -C -d -v -m -q -i -o -a -A -b -B -u -U -P -l -L -s -t -V --help"
    
    if [[ -n "$mussh_version" ]]; then
        local version_num=$(echo "$mussh_version" | awk -F. '{
            if (NF == 3) print ($1*10000 + $2*100 + $3)
            else if (NF == 2) print ($1*10000 + $2*100)
            else print ($1*10000)
        }')
        
        # Add v1.1+ options (SSH advanced features)
        if [[ $version_num -ge 10100 ]]; then
            opts="$opts -J -CM -CP -S -E -BI -W -T -HKH -VHD"
        fi
        
        # Add v1.2.3+ options (screen support)  
        if [[ $version_num -ge 10203 ]]; then
            opts="$opts --screen"
        fi
    fi
    
    # If previous word was -h or --hosts, complete with hostnames (Levenshtein sorted)
    if [[ "$prev" == "-h" || "$prev" == "--hosts" ]]; then
        _dcs_complete_hosts "$cur"
        return 0
    fi
    
    # If previous word was -H or --host-file, complete with filenames
    if [[ "$prev" == "-H" || "$prev" == "--host-file" ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            _files
        else
            COMPREPLY=( $(compgen -f -- ${cur}) )
        fi
        return 0
    fi
    
    # If previous word was -J (jump host), complete with hostnames (Levenshtein sorted)
    if [[ "$prev" == "-J" ]]; then
        _dcs_complete_hosts "$cur"
        return 0
    fi
    
    # If previous word was -n (netgroup), don't complete (user enters netgroup name)
    if [[ "$prev" == "-n" ]]; then
        return 0
    fi
    
    # If previous word was -i (identity files), complete with files
    if [[ "$prev" == "-i" ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            _files
        else
            COMPREPLY=( $(compgen -f -- ${cur}) )
        fi
        return 0
    fi
    
    # If previous word was -C (script files), complete with files
    if [[ "$prev" == "-C" ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            _files
        else
            COMPREPLY=( $(compgen -f -- ${cur}) )
        fi
        return 0
    fi
    
    # If previous word was -S (ControlPath), complete with files/paths
    if [[ "$prev" == "-S" ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            _files
        else
            COMPREPLY=( $(compgen -f -- ${cur}) )
        fi
        return 0
    fi
    
    # If previous word was -T (socket), complete with files/paths
    if [[ "$prev" == "-T" ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            _files
        else
            COMPREPLY=( $(compgen -f -- ${cur}) )
        fi
        return 0
    fi
    
    # If previous word was -E (log file), complete with files
    if [[ "$prev" == "-E" ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            _files
        else
            COMPREPLY=( $(compgen -f -- ${cur}) )
        fi
        return 0
    fi
    
    # If previous word was -BI (bind interface), don't complete (user enters interface)
    if [[ "$prev" == "-BI" ]]; then
        return 0
    fi
    
    # If previous word was -W (forward), don't complete (user enters host:port)
    if [[ "$prev" == "-W" ]]; then
        return 0
    fi
    
    # Options that don't need completion (user enters values)
    if [[ "$prev" =~ ^(-l|-L|-o|-s|-t|-m|-CP|-d|-v)$ ]]; then
        return 0
    fi
    
    # If previous word was -c or --command, don't complete (user enters command)
    if [[ "$prev" == "-c" || "$prev" == "--command" ]]; then
        return 0
    fi
    
    # If current word starts with -, complete with options
    if [[ ${cur} == -* ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            compadd -- ${(z)opts}
        else
            COMPREPLY=( $(compgen -W "$opts" -- ${cur}) )
        fi
        return 0
    fi
    
    # For continuing -h arguments (multiple hosts), check if we're in a host list
    local i=1
    local in_host_list=false
    if [[ "$_IS_ZSH" == "true" ]]; then
        for ((i=2; i<CURRENT; i++)); do
            if [[ "${words[i]}" == "-h" || "${words[i]}" == "--hosts" ]]; then
                in_host_list=true
            elif [[ "${words[i]}" == "-"* ]]; then
                in_host_list=false
            fi
        done
    else
        for ((i=1; i<COMP_CWORD; i++)); do
            if [[ "${COMP_WORDS[i]}" == "-h" || "${COMP_WORDS[i]}" == "--hosts" ]]; then
                in_host_list=true
            elif [[ "${COMP_WORDS[i]}" == "-"* ]]; then
                in_host_list=false
            fi
        done
    fi
    
    # If we're in a host list, complete with hostnames (Levenshtein sorted)
    if [[ "$in_host_list" == "true" && ${cur} != -* ]]; then
        _dcs_complete_hosts "$cur"
        return 0
    fi
    
    # Default: complete with hostnames using Levenshtein distance sorting (like ts command)
    _dcs_complete_hosts "$cur"
    return 0
}

# Helper function to register completions for available commands
_dcs_register_completions() {
    local completion_func="$1"
    local commands=("tssh" "ts" "tssh_copy_id")
    
    if [[ "$_HAS_SCP" == "true" ]]; then
        commands+=("tscp")
    fi
    if [[ "$_HAS_SFTP" == "true" ]]; then
        commands+=("tsftp")
    fi
    if [[ "$_HAS_RSYNC" == "true" ]]; then
        commands+=("trsync")
    fi
    for cmd in "${commands[@]}"; do
        if [[ "$_IS_ZSH" == "true" ]]; then
            compdef "$completion_func" "$cmd"
        else
            complete -F "$completion_func" "$cmd"
        fi
    done
    
    # Register tmussh with its own dedicated completion function
    if [[ "$_HAS_MUSSH" == "true" ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            compdef "_tmussh_completions" "tmussh"
        else
            complete -F "_tmussh_completions" "tmussh"
        fi
    fi
}

_tssh_completions() {
    local cur prev opts
    
    # Handle shell-specific completion variables
    if [[ "$_IS_ZSH" == "true" ]]; then
        # zsh completion
        cur="${words[CURRENT]}"
        prev="${words[CURRENT-1]}"
        local command_name="${words[1]}"
    else
        # bash completion
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        local command_name="${COMP_WORDS[0]}"
    fi
    
    # Handle ts dispatcher command
    if [[ "$command_name" == "ts" ]]; then
        # Check if we're completing the first argument (subcommand)
        local word_index
        if [[ "$_IS_ZSH" == "true" ]]; then
            word_index=$CURRENT
            if [[ $word_index -eq 2 ]]; then
                # Complete subcommands using helper function
                local subcommands
                if [[ "$_IS_ZSH" == "true" ]]; then
                    subcommands=(${(f)"$(_dcs_build_subcommands)"})
                else
                    subcommands=($(_dcs_build_subcommands))
                fi
                compadd -a subcommands
                return 0
            fi
        else
            word_index=$COMP_CWORD
            if [[ $word_index -eq 1 ]]; then
                # Complete subcommands using helper function
                local subcommands
                if [[ "$_IS_ZSH" == "true" ]]; then
                    subcommands=(${(f)"$(_dcs_build_subcommands)"})
                else
                    subcommands=($(_dcs_build_subcommands))
                fi
                COMPREPLY=( $(compgen -W "${subcommands[*]}" -- ${cur}) )
                return 0
            fi
        fi
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
        
        # Get all available tailscale hosts using helper function
        local unique_hosts
        if [[ "$_IS_ZSH" == "true" ]]; then
            unique_hosts=(${(f)"$(_dcs_get_tailscale_hosts)"})
        else
            unique_hosts=($(_dcs_get_tailscale_hosts))
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
        _tssh_completions
        return 0
    }
    _dcs_register_completions "_ts_zsh_completion"
else
    # bash completion
    _dcs_register_completions "_tssh_completions"
fi