#!/bin/bash
# Tailscale CLI helpers - mussh integration
# This file provides the tmussh command for parallel SSH with Tailscale support

# Detect shell type for compatibility
if [[ -n "$ZSH_VERSION" ]]; then
    _IS_ZSH=true
else
    _IS_ZSH=false
fi

# Source the main functions to get host resolution
source "$(dirname "${BASH_SOURCE[0]}")/tailscale-functions.sh" 2>/dev/null || \
source "$(dirname "$0")/tailscale-functions.sh" 2>/dev/null

# Tailscale mussh wrapper function (internal)
_tmussh_main() {
    # Check if mussh is installed
    if ! command -v mussh &> /dev/null; then
        echo "Error: mussh is not installed. Please install mussh first."
        echo "Visit: https://github.com/DigitalCyberSoft/mussh"
        return 1
    fi
    
    local debug=false
    local mussh_args=()
    local hosts=()
    local resolved_hosts=()
    local host_file=""
    local use_host_file=false
    local command=""
    local implicit_hosts=true
    
    # ANSI color codes
    local GREEN='\033[0;32m'
    local YELLOW='\033[0;33m'
    local RESET='\033[0m'
    
    # Parse arguments similar to mussh
    local i=0
    local args=("$@")
    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"
        
        case "$arg" in
            -v|--verbose)
                debug=true
                mussh_args+=("$arg")
                ;;
            -h|--hosts)
                implicit_hosts=false
                ((i++))
                # Collect all hosts until next option
                while [ $i -lt ${#args[@]} ] && [[ "${args[$i]}" != -* ]]; do
                    hosts+=("${args[$i]}")
                    ((i++))
                done
                ((i--))  # Back up one since outer loop will increment
                ;;
            -H|--host-file)
                implicit_hosts=false
                use_host_file=true
                ((i++))
                host_file="${args[$i]}"
                mussh_args+=("-H" "$host_file")
                ;;
            -c|--command)
                ((i++))
                command="${args[$i]}"
                mussh_args+=("-c" "$command")
                ;;
            -*)
                # Pass through other mussh options
                mussh_args+=("$arg")
                # Check if this option takes an argument
                if [[ "$arg" =~ ^-(l|L|i|t|m|C|J|o)$ ]]; then
                    ((i++))
                    if [ $i -lt ${#args[@]} ]; then
                        mussh_args+=("${args[$i]}")
                    fi
                fi
                ;;
            *)
                if $implicit_hosts && [ -z "$command" ]; then
                    # In implicit mode, collect hosts until we find a non-host argument
                    if [[ "$arg" =~ ^[^-].*$ ]]; then
                        # Check if this could be a command (contains spaces or common command indicators)
                        if [[ "$arg" == *" "* ]] || [[ "$arg" =~ ^(ls|pwd|uptime|hostname|date|df|ps|systemctl|docker|kubectl) ]]; then
                            command="$arg"
                            mussh_args+=("-c" "$command")
                        else
                            hosts+=("$arg")
                        fi
                    fi
                else
                    mussh_args+=("$arg")
                fi
                ;;
        esac
        ((i++))
    done
    
    # Resolve Tailscale hosts
    if [ ${#hosts[@]} -gt 0 ]; then
        [ "$debug" = true ] && echo -e "${YELLOW}[DEBUG]${RESET} Resolving ${#hosts[@]} hosts..."
        
        for host in "${hosts[@]}"; do
            local user=""
            local hostname=""
            
            # Parse user@host format
            if [[ "$host" == *"@"* ]]; then
                user="${host%%@*}"
                hostname="${host#*@}"
            else
                hostname="$host"
            fi
            
            # Handle wildcards/patterns
            if [[ "$hostname" == *"*"* ]]; then
                # Get all matching Tailscale hosts
                local ts_json=$(tailscale status --json 2>/dev/null)
                if [[ -n "$ts_json" ]]; then
                    local pattern="${hostname//\*/.*}"  # Convert shell wildcard to regex
                    local matching_hosts=()
                    
                    # Get matching hosts from JSON using multi-host pattern matching
                    local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
                    local matches=$(_dcs_find_multiple_hosts_matching "$ts_json" "$hostname" "$magicdns_enabled")
                    
                    while IFS= read -r match; do
                        if [[ -n "$match" ]]; then
                            local match_ip=$(echo "$match" | cut -d',' -f1)
                            local match_hostname=$(echo "$match" | cut -d',' -f2)
                            local match_status=$(echo "$match" | cut -d',' -f4)
                            
                            # Only include online hosts for mussh
                            if [[ "$match_status" != "offline" ]]; then
                                if _dcs_is_magicdns_working; then
                                    if [[ -n "$user" ]]; then
                                        resolved_hosts+=("${user}@${match_hostname}")
                                    else
                                        resolved_hosts+=("${match_hostname}")
                                    fi
                                else
                                    if [[ -n "$user" ]]; then
                                        resolved_hosts+=("${user}@${match_ip}")
                                    else
                                        resolved_hosts+=("${match_ip}")
                                    fi
                                fi
                                
                                [ "$debug" = true ] && echo -e "${GREEN}[TS]${RESET} Matched: $hostname -> $match_hostname ($match_ip)"
                            fi
                        fi
                    done <<< "$matches"
                else
                    # Fallback to original pattern if can't resolve
                    resolved_hosts+=("$host")
                fi
            else
                # Single host - try to resolve
                local ts_json=$(tailscale status --json 2>/dev/null)
                if [[ -n "$ts_json" ]]; then
                    local magicdns_enabled=$(echo "$ts_json" | jq -r '.CurrentTailnet.MagicDNSEnabled' 2>/dev/null)
                    local host_data=$(_dcs_find_host_in_json "$ts_json" "$hostname" "$magicdns_enabled")
                    
                    if [[ -n "$host_data" ]]; then
                        local found_ip=$(echo "$host_data" | cut -d',' -f1)
                        local found_hostname=$(echo "$host_data" | cut -d',' -f2)
                        
                        if _dcs_is_magicdns_working; then
                            if [[ -n "$user" ]]; then
                                resolved_hosts+=("${user}@${found_hostname}")
                            else
                                resolved_hosts+=("${found_hostname}")
                            fi
                        else
                            if [[ -n "$user" ]]; then
                                resolved_hosts+=("${user}@${found_ip}")
                            else
                                resolved_hosts+=("${found_ip}")
                            fi
                        fi
                        
                        [ "$debug" = true ] && echo -e "${GREEN}[TS]${RESET} Resolved: $hostname -> $found_hostname ($found_ip)"
                    else
                        # Not a Tailscale host, pass through as-is
                        resolved_hosts+=("$host")
                    fi
                else
                    resolved_hosts+=("$host")
                fi
            fi
        done
        
        # Add resolved hosts to mussh command
        if [ ${#resolved_hosts[@]} -gt 0 ]; then
            mussh_args+=("-h")
            for host in "${resolved_hosts[@]}"; do
                mussh_args+=("$host")
            done
        fi
    fi
    
    # Execute mussh with resolved arguments
    if [ "$debug" = true ]; then
        echo -e "${GREEN}[TMUSSH]${RESET} Running: mussh ${mussh_args[*]}"
    fi
    
    mussh "${mussh_args[@]}"
}

# Create wrapper function
tmussh() {
    _tmussh_main "$@"
}

# Export functions - only export user-facing commands
export -f tmussh 2>/dev/null || true