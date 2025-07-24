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

# Helper function to register completions for available commands
_dcs_register_completions() {
    local completion_func="$1"
    local commands=("tssh" "ts" "ssh-copy-id")
    
    if [[ "$_HAS_SCP" == "true" ]]; then
        commands+=("tscp")
    fi
    if [[ "$_HAS_SFTP" == "true" ]]; then
        commands+=("tsftp")
    fi
    if [[ "$_HAS_RSYNC" == "true" ]]; then
        commands+=("trsync")
    fi
    if [[ "$_HAS_MUSSH" == "true" ]]; then
        commands+=("tmussh")
    fi
    
    for cmd in "${commands[@]}"; do
        if [[ "$_IS_ZSH" == "true" ]]; then
            compdef "$completion_func" "$cmd"
        else
            complete -F "$completion_func" "$cmd"
        fi
    done
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