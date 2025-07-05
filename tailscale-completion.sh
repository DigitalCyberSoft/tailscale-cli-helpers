# Tailscale CLI helpers - Bash/Zsh completion functions
# This file provides tab completion for the ts command

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