# Tailscale CLI helpers - ts dispatcher
# This file provides the ts dispatcher command that routes to individual tools

# Create ts dispatcher command
ts() {
    # If no arguments, show usage
    if [ $# -eq 0 ]; then
        echo "Usage: ts [command] [args...]"
        echo "Commands:"
        echo "  ssh      SSH to host (default if no command specified)"
        echo "  scp      Copy files to/from host"
        echo "  rsync    Sync files to/from host"
        if command -v mussh &> /dev/null; then
            echo "  mussh    Execute commands on multiple hosts"
        fi
        echo ""
        echo "Examples:"
        echo "  ts hostname                    # SSH to hostname (default)"
        echo "  ts ssh hostname                # Explicit SSH"
        echo "  ts scp file.txt hostname:/path # Copy file"
        echo "  ts rsync -av dir/ hostname:/   # Sync directory"
        if command -v mussh &> /dev/null; then
            echo "  ts mussh -h host1 host2 -c cmd # Execute on multiple hosts"
        fi
        return 1
    fi
    
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        ssh)
            tssh_main "$@"
            ;;
        scp)
            tscp_main "$@"
            ;;
        rsync)
            trsync_main "$@"
            ;;
        mussh)
            if command -v mussh &> /dev/null; then
                tmussh_main "$@"
            else
                echo "Error: mussh is not installed"
                return 1
            fi
            ;;
        *)
            # Default to SSH if subcommand is not recognized
            tssh_main "$subcommand" "$@"
            ;;
    esac
}

# Export function for subshells
export -f ts 2>/dev/null || true