# Tailscale CLI helpers - ts dispatcher
# This file provides the ts dispatcher command that routes to individual tools

# Create ts dispatcher command
ts() {
    # If no arguments, show usage
    if [ $# -eq 0 ]; then
        echo "Usage: ts [command] [args...]"
        echo "Commands:"
        echo "  ssh      SSH to host (default if no command specified)"
        if [[ "$_HAS_SCP" == "true" ]]; then
            echo "  scp      Copy files to/from host"
        fi
        if [[ "$_HAS_SFTP" == "true" ]]; then
            echo "  sftp     Interactive file transfer to host"
        fi
        if [[ "$_HAS_RSYNC" == "true" ]]; then
            echo "  rsync    Sync files to/from host"
        fi
        echo "  ssh_copy_id  Copy SSH keys to host"
        if [[ "$_HAS_MUSSH" == "true" ]]; then
            echo "  mussh    Execute commands on multiple hosts"
        fi
        echo ""
        echo "Examples:"
        echo "  ts hostname                    # SSH to hostname (default)"
        echo "  ts ssh hostname                # Explicit SSH"
        if [[ "$_HAS_SCP" == "true" ]]; then
            echo "  ts scp file.txt hostname:/path # Copy file"
        fi
        if [[ "$_HAS_SFTP" == "true" ]]; then
            echo "  ts sftp hostname               # Interactive file transfer"
        fi
        if [[ "$_HAS_RSYNC" == "true" ]]; then
            echo "  ts rsync -av dir/ hostname:/   # Sync directory"
        fi
        echo "  ts ssh_copy_id hostname        # Copy SSH keys"
        if [[ "$_HAS_MUSSH" == "true" ]]; then
            echo "  ts mussh -h host1 host2 -c cmd # Execute on multiple hosts"
        fi
        return 1
    fi
    
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        ssh)
            _tssh_main "$@"
            ;;
        scp)
            if [[ "$_HAS_SCP" == "true" ]]; then
                _tscp_main "$@"
            else
                echo "Error: scp is not installed"
                return 1
            fi
            ;;
        sftp)
            if [[ "$_HAS_SFTP" == "true" ]]; then
                _tsftp_main "$@"
            else
                echo "Error: sftp is not installed"
                return 1
            fi
            ;;
        rsync)
            if [[ "$_HAS_RSYNC" == "true" ]]; then
                _trsync_main "$@"
            else
                echo "Error: rsync is not installed"
                return 1
            fi
            ;;
        ssh_copy_id)
            _tssh_copy_id_main "$@"
            ;;
        mussh)
            if [[ "$_HAS_MUSSH" == "true" ]]; then
                _tmussh_main "$@"
            else
                echo "Error: mussh is not installed"
                return 1
            fi
            ;;
        *)
            # Default to SSH if subcommand is not recognized
            _tssh_main "$subcommand" "$@"
            ;;
    esac
}

# Export function for subshells
export -f ts 2>/dev/null || true