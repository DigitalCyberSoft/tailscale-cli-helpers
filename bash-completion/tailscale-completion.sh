#!/usr/bin/env bash
#
# tailscale-completion.sh - Tab completion for Tailscale CLI helpers
#
# This file provides tab completion for all ts commands
# Compatible with both bash and zsh
#

# Detect shell type
if [[ -n "$ZSH_VERSION" ]]; then
    _IS_ZSH=true
else
    _IS_ZSH=false
fi

# Source the resolver library for host completion
_completion_source_resolver() {
    local dirs=(
        "$(dirname "${BASH_SOURCE[0]}")/../lib"
        "/usr/share/tailscale-cli-helpers/lib"
        "/usr/local/share/tailscale-cli-helpers/lib"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ -f "$dir/tailscale-resolver.sh" ]]; then
            source "$dir/tailscale-resolver.sh"
            return 0
        fi
    done
    return 1
}

# Load resolver if not already loaded
if ! type get_all_tailscale_hosts >/dev/null 2>&1; then
    _completion_source_resolver
fi

# Get Tailscale hosts for completion with optional prefix filter
_get_tailscale_hosts() {
    local prefix="$1"
    local current="$2"
    
    # Extract user@ prefix if present
    local user_prefix=""
    local host_part="$current"
    if [[ "$current" == *"@"* ]]; then
        user_prefix="${current%%@*}@"
        host_part="${current#*@}"
    fi
    
    # Get all hosts
    local hosts
    if type get_all_tailscale_hosts >/dev/null 2>&1; then
        hosts=$(get_all_tailscale_hosts "" "^${host_part}")
    else
        # Fallback to basic tailscale status (exclude Mullvad exit nodes)
        # Mullvad nodes typically match patterns like de-*-wg-*, us-*-wg-*, etc.
        hosts=$(tailscale status 2>/dev/null | awk 'NR>1 && $1 != "" {print $2}' | \
                grep "^${host_part}" 2>/dev/null | \
                grep -v -E '^[a-z]{2}-[a-z]{3}-wg-[0-9]+$' 2>/dev/null)
    fi
    
    # Add user prefix back if needed
    if [[ -n "$user_prefix" ]]; then
        while IFS= read -r host; do
            [[ -n "$host" ]] && echo "${user_prefix}${host}"
        done <<< "$hosts"
    else
        echo "$hosts"
    fi
}

# Check which commands are available
_check_available_commands() {
    local cmds=()
    
    # Always available
    cmds+=("ssh")
    cmds+=("ssh_copy_id")
    cmds+=("exit")
    
    # Check optional commands
    command -v scp >/dev/null 2>&1 && cmds+=("scp")
    command -v sftp >/dev/null 2>&1 && cmds+=("sftp")
    command -v rsync >/dev/null 2>&1 && cmds+=("rsync")
    command -v mussh >/dev/null 2>&1 && cmds+=("mussh")
    
    echo "${cmds[@]}"
}

# Completion for ts command (dispatcher)
_ts_complete() {
    local cur prev
    
    if [[ "$_IS_ZSH" == "true" ]]; then
        cur="${words[CURRENT]}"
        prev="${words[CURRENT-1]}"
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    
    # If no subcommand yet, show available subcommands and hosts
    if [[ "$_IS_ZSH" == "true" ]]; then
        local cmd_pos=2
    else
        local cmd_pos=1
    fi
    
    if [[ "$_IS_ZSH" == "true" && $CURRENT -eq 2 ]] || [[ "$_IS_ZSH" != "true" && $COMP_CWORD -eq 1 ]]; then
        # First argument - show subcommands and hosts
        local subcommands=($(_check_available_commands))
        local hosts=$(_get_tailscale_hosts "" "$cur")
        
        if [[ "$_IS_ZSH" == "true" ]]; then
            compadd -a subcommands
            [[ -n "$hosts" ]] && compadd $(echo "$hosts")
        else
            COMPREPLY=($(compgen -W "${subcommands[*]}" -- "$cur"))
            if [[ -n "$hosts" ]]; then
                COMPREPLY+=($(compgen -W "$hosts" -- "$cur"))
            fi
        fi
        return
    fi
    
    # Get the subcommand
    local subcmd
    if [[ "$_IS_ZSH" == "true" ]]; then
        subcmd="${words[2]}"
    else
        subcmd="${COMP_WORDS[1]}"
    fi
    
    # Delegate to subcommand completion
    case "$subcmd" in
        ssh|sftp)
            # SSH/SFTP options and hosts
            if [[ "$cur" == -* ]]; then
                local opts="-v -h --help -V --version"
                if [[ "$_IS_ZSH" == "true" ]]; then
                    compadd $(echo "$opts")
                else
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                fi
            else
                local hosts=$(_get_tailscale_hosts "" "$cur")
                if [[ "$_IS_ZSH" == "true" ]]; then
                    [[ -n "$hosts" ]] && compadd $(echo "$hosts")
                else
                    [[ -n "$hosts" ]] && COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
                fi
            fi
            ;;
        scp|rsync)
            # File completion and host:path completion
            if [[ "$cur" == *:* ]]; then
                # Remote path completion - just show the current text
                if [[ "$_IS_ZSH" == "true" ]]; then
                    compadd "$cur"
                else
                    COMPREPLY=("$cur")
                fi
            else
                # Local files and remote hosts
                if [[ "$_IS_ZSH" == "true" ]]; then
                    _files
                    local hosts=$(_get_tailscale_hosts "" "$cur")
                    [[ -n "$hosts" ]] && compadd -S ":" $(echo "$hosts")
                else
                    COMPREPLY=($(compgen -f -- "$cur"))
                    local hosts=$(_get_tailscale_hosts "" "$cur")
                    if [[ -n "$hosts" ]]; then
                        while IFS= read -r host; do
                            [[ -n "$host" ]] && COMPREPLY+=("${host}:")
                        done <<< "$hosts"
                    fi
                fi
            fi
            ;;
        ssh_copy_id)
            # SSH key copy options and hosts
            if [[ "$cur" == -* ]]; then
                local opts="-i -J -h --help -V --version"
                if [[ "$_IS_ZSH" == "true" ]]; then
                    compadd $(echo "$opts")
                else
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                fi
            else
                local hosts=$(_get_tailscale_hosts "" "$cur")
                if [[ "$_IS_ZSH" == "true" ]]; then
                    [[ -n "$hosts" ]] && compadd $(echo "$hosts")
                else
                    [[ -n "$hosts" ]] && COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
                fi
            fi
            ;;
        mussh)
            # Multi-SSH options and hosts
            if [[ "$prev" == "-h" || "$prev" == "--hosts" ]]; then
                local hosts=$(_get_tailscale_hosts "" "$cur")
                if [[ "$_IS_ZSH" == "true" ]]; then
                    [[ -n "$hosts" ]] && compadd $(echo "$hosts")
                else
                    [[ -n "$hosts" ]] && COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
                fi
            elif [[ "$cur" == -* ]]; then
                local opts="-h --hosts -c --command -H --hostfile -h --help -V --version"
                if [[ "$_IS_ZSH" == "true" ]]; then
                    compadd $(echo "$opts")
                else
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                fi
            fi
            ;;
        exit)
            # Exit node manager options
            local options="--help --version --list"
            if [[ "$_IS_ZSH" == "true" ]]; then
                compadd $(echo "$options")
            else
                COMPREPLY=($(compgen -W "$options" -- "$cur"))
            fi
            ;;
    esac
}

# Individual command completions
_tssh_complete() {
    local cur
    if [[ "$_IS_ZSH" == "true" ]]; then
        cur="${words[CURRENT]}"
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
    fi
    
    if [[ "$cur" == -* ]]; then
        local opts="-v --verbose -h --help -V --version"
        if [[ "$_IS_ZSH" == "true" ]]; then
            compadd $(echo "$opts")
        else
            COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        fi
    else
        local hosts=$(_get_tailscale_hosts "" "$cur")
        if [[ "$_IS_ZSH" == "true" ]]; then
            [[ -n "$hosts" ]] && compadd $(echo "$hosts")
        else
            [[ -n "$hosts" ]] && COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
        fi
    fi
}

_tscp_complete() {
    local cur
    if [[ "$_IS_ZSH" == "true" ]]; then
        cur="${words[CURRENT]}"
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
    fi
    
    # Handle remote path completion
    if [[ "$cur" == *:* ]]; then
        if [[ "$_IS_ZSH" == "true" ]]; then
            compadd "$cur"
        else
            COMPREPLY=("$cur")
        fi
    else
        # Local files and remote hosts
        if [[ "$_IS_ZSH" == "true" ]]; then
            _files
            local hosts=$(_get_tailscale_hosts "" "$cur")
            [[ -n "$hosts" ]] && compadd -S ":" $(echo "$hosts")
        else
            COMPREPLY=($(compgen -f -- "$cur"))
            local hosts=$(_get_tailscale_hosts "" "$cur")
            if [[ -n "$hosts" ]]; then
                while IFS= read -r host; do
                    [[ -n "$host" ]] && COMPREPLY+=("${host}:")
                done <<< "$hosts"
            fi
        fi
    fi
}

_tsftp_complete() {
    _tssh_complete  # Same as tssh
}

_trsync_complete() {
    _tscp_complete  # Same as tscp
}

_tssh_copy_id_complete() {
    local cur prev
    if [[ "$_IS_ZSH" == "true" ]]; then
        cur="${words[CURRENT]}"
        prev="${words[CURRENT-1]}"
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    
    case "$prev" in
        -i)
            # SSH key file completion
            if [[ "$_IS_ZSH" == "true" ]]; then
                _files
            else
                COMPREPLY=($(compgen -f -- "$cur"))
            fi
            ;;
        -J)
            # Jump host completion
            local hosts=$(_get_tailscale_hosts "" "$cur")
            if [[ "$_IS_ZSH" == "true" ]]; then
                [[ -n "$hosts" ]] && compadd $(echo "$hosts")
            else
                [[ -n "$hosts" ]] && COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
            fi
            ;;
        *)
            if [[ "$cur" == -* ]]; then
                local opts="-i -J -h --help -V --version"
                if [[ "$_IS_ZSH" == "true" ]]; then
                    compadd $(echo "$opts")
                else
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                fi
            else
                local hosts=$(_get_tailscale_hosts "" "$cur")
                if [[ "$_IS_ZSH" == "true" ]]; then
                    [[ -n "$hosts" ]] && compadd $(echo "$hosts")
                else
                    [[ -n "$hosts" ]] && COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
                fi
            fi
            ;;
    esac
}

_tmussh_complete() {
    local cur prev
    if [[ "$_IS_ZSH" == "true" ]]; then
        cur="${words[CURRENT]}"
        prev="${words[CURRENT-1]}"
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    
    case "$prev" in
        -h|--hosts)
            # Host completion with wildcard support
            local hosts=$(_get_tailscale_hosts "" "$cur")
            if [[ "$_IS_ZSH" == "true" ]]; then
                [[ -n "$hosts" ]] && compadd $(echo "$hosts")
            else
                [[ -n "$hosts" ]] && COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
            fi
            ;;
        -H|--hostfile)
            # File completion
            if [[ "$_IS_ZSH" == "true" ]]; then
                _files
            else
                COMPREPLY=($(compgen -f -- "$cur"))
            fi
            ;;
        *)
            if [[ "$cur" == -* ]]; then
                local opts="-h --hosts -c --command -H --hostfile -h --help -V --version"
                if [[ "$_IS_ZSH" == "true" ]]; then
                    compadd $(echo "$opts")
                else
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                fi
            fi
            ;;
    esac
}

# Completion for tsexit command
_tsexit_complete() {
    local cur
    
    if [[ "$_IS_ZSH" == "true" ]]; then
        cur="${words[CURRENT]}"
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
    fi
    
    # Options for tsexit
    local options="--help --version --list"
    
    if [[ "$_IS_ZSH" == "true" ]]; then
        compadd $(echo "$options")
    else
        COMPREPLY=($(compgen -W "$options" -- "$cur"))
    fi
}

# Register completions
if [[ "$_IS_ZSH" == "true" ]]; then
    # Zsh completion setup
    compdef _ts_complete ts
    compdef _tssh_complete tssh
    compdef _tscp_complete tscp
    compdef _tsftp_complete tsftp
    compdef _trsync_complete trsync
    compdef _tssh_copy_id_complete tssh_copy_id
    compdef _tmussh_complete tmussh
    compdef _tsexit_complete tsexit
else
    # Bash completion setup
    complete -F _ts_complete ts
    complete -F _tssh_complete tssh
    complete -F _tscp_complete tscp
    complete -F _tsftp_complete tsftp
    complete -F _trsync_complete trsync
    complete -F _tssh_copy_id_complete tssh_copy_id
    complete -F _tmussh_complete tmussh
    complete -F _tsexit_complete tsexit
fi