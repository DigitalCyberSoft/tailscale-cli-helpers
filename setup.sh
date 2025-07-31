#!/bin/bash
# Universal setup script for tailscale-cli-helpers
# Installs standalone binary commands

set -e

# Security: Set secure umask for file creation
umask 0022

# Security: Validate source files exist and are regular files
validate_source_file() {
    local file="$1"
    [[ -f "$file" && ! -L "$file" ]] || {
        echo "Error: Invalid or missing source file: $file" >&2
        return 1
    }
    # Check file is readable
    [[ -r "$file" ]] || {
        echo "Error: Cannot read source file: $file" >&2
        return 1
    }
}

# Security: Validate destination directory
validate_destination_dir() {
    local dir="$1"
    # Ensure no path traversal
    case "$dir" in
        *../*|*/..*|../*|*..)
            echo "Error: Path traversal detected in: $dir" >&2
            return 1
            ;;
    esac
    return 0
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    # Check for tailscale
    if ! command -v tailscale &> /dev/null; then
        missing+=("tailscale")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing dependencies: ${missing[*]}"
        echo "Please install them before running this setup."
        return 1
    fi
    
    return 0
}

# Create bash completion file
create_bash_completion() {
    local completion_file="$1"
    
    cat > "$completion_file" << 'EOF'
# Bash completion for Tailscale CLI helpers

# Source the shared library for host list functions
if [[ -f /usr/share/tailscale-cli-helpers/lib/tailscale-resolver.sh ]]; then
    source /usr/share/tailscale-cli-helpers/lib/tailscale-resolver.sh
elif [[ -f ~/.local/share/tailscale-cli-helpers/lib/tailscale-resolver.sh ]]; then
    source ~/.local/share/tailscale-cli-helpers/lib/tailscale-resolver.sh
fi

# Completion for tssh
_tssh_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Handle options that need values
    case "$prev" in
        -i|-l|-p|-F|-E|-L|-R|-D|-W|-J|-Q|-c|-m|-b|-e|-o)
            # Let bash handle file/value completion
            return
            ;;
    esac
    
    # If current word starts with -, show SSH options
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-4 -6 -A -a -C -f -G -g -K -k -M -N -n -q -s -T -t -V -v -X -x -Y -y -B -b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w" -- "$cur"))
        return
    fi
    
    # Complete hostnames
    if type -t get_all_tailscale_hosts >/dev/null 2>&1; then
        local hosts=$(get_all_tailscale_hosts 2>/dev/null)
        if [[ -n "$hosts" ]]; then
            # Handle user@host format
            if [[ "$cur" == *@* ]]; then
                local user_prefix="${cur%%@*}@"
                local host_part="${cur#*@}"
                COMPREPLY=($(compgen -W "$hosts" -- "$host_part" | sed "s/^/${user_prefix}/"))
            else
                COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
            fi
        fi
    fi
}

# Completion for ts dispatcher
_ts_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # First argument - subcommands or hostnames
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        local subcommands="help ssh ssh_copy_id scp sftp rsync mussh"
        
        # Add available commands based on what's installed
        local available_commands="help ssh ssh_copy_id"
        command -v scp >/dev/null 2>&1 && available_commands="$available_commands scp"
        command -v sftp >/dev/null 2>&1 && available_commands="$available_commands sftp"
        command -v rsync >/dev/null 2>&1 && available_commands="$available_commands rsync"
        command -v mussh >/dev/null 2>&1 && available_commands="$available_commands mussh"
        
        # Get hostnames for default SSH behavior
        local hosts=""
        if type -t get_all_tailscale_hosts >/dev/null 2>&1; then
            hosts=$(get_all_tailscale_hosts 2>/dev/null)
        fi
        
        COMPREPLY=($(compgen -W "$available_commands $hosts" -- "$cur"))
        return
    fi
    
    # Delegate to specific command completion
    case "${COMP_WORDS[1]}" in
        ssh|sftp)
            # Use tssh completion logic
            _tssh_completion
            ;;
        ssh_copy_id)
            _tssh_copy_id_completion
            ;;
        scp)
            _tscp_completion
            ;;
        rsync)
            _trsync_completion
            ;;
        mussh)
            _tmussh_completion
            ;;
    esac
}

# Completion for tscp
_tscp_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    
    # Let bash handle local files
    if [[ "$cur" != *:* ]]; then
        # Check if this might be a remote spec being typed
        if type -t get_all_tailscale_hosts >/dev/null 2>&1; then
            local hosts=$(get_all_tailscale_hosts 2>/dev/null)
            if [[ -n "$hosts" ]]; then
                # Add : to each host for remote path completion
                COMPREPLY=($(compgen -W "$hosts" -- "$cur" | sed 's/$/:\/~/'))
            fi
        fi
        # Also include local file completion
        COMPREPLY+=($(compgen -f -- "$cur"))
    fi
}

# Completion for tsftp
_tsftp_completion() {
    _tssh_completion
}

# Completion for trsync
_trsync_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    
    # If current word starts with -, show rsync options
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-v -q -c -a -r -R -b -u -l -L -H -p -o -g -D -t -S -n -W -x -B -e -C -I -T -P -z -h --verbose --quiet --checksum --archive --recursive --relative --backup --update --links --copy-links --hard-links --perms --owner --group --devices --times --sparse --dry-run --whole-file --one-file-system --block-size --rsh --existing --ignore-existing --temp-dir --compare-dest --copy-dest --link-dest --compress --human-readable --progress --partial --partial-dir --delay-updates --delete --delete-before --delete-during --delete-after --delete-excluded --ignore-errors --force --max-delete --max-size --min-size --timeout --contimeout --modify-window --include --include-from --exclude --exclude-from --files-from --address --port --sockopts --blocking-io --stats --8-bit-output --human-readable --progress --itemize-changes --out-format --log-file --log-file-format --password-file --list-only --bwlimit --write-batch --only-write-batch --read-batch --protocol --iconv --ipv4 --ipv6 --version --help" -- "$cur"))
        return
    fi
    
    # Otherwise use tscp completion logic for remote paths
    _tscp_completion
}

# Completion for tssh_copy_id
_tssh_copy_id_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Handle options that need values
    case "$prev" in
        -i|-p|-o|-J)
            # Let bash handle file/value completion
            return
            ;;
    esac
    
    # If current word starts with -, show options
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-i -p -o -f -J" -- "$cur"))
        return
    fi
    
    # Complete hostnames
    if type -t get_all_tailscale_hosts >/dev/null 2>&1; then
        local hosts=$(get_all_tailscale_hosts 2>/dev/null)
        if [[ -n "$hosts" ]]; then
            # Handle user@host format
            if [[ "$cur" == *@* ]]; then
                local user_prefix="${cur%%@*}@"
                local host_part="${cur#*@}"
                COMPREPLY=($(compgen -W "$hosts" -- "$host_part" | sed "s/^/${user_prefix}/"))
            else
                COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
            fi
        fi
    fi
}

# Completion for tmussh
_tmussh_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Handle options that need values
    case "$prev" in
        -h|--hosts)
            # Complete hostnames, including wildcards
            if type -t get_all_tailscale_hosts >/dev/null 2>&1; then
                local hosts=$(get_all_tailscale_hosts 2>/dev/null)
                COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
                # Also suggest wildcard patterns
                if [[ -z "$cur" ]] || [[ "$cur" == *"*"* ]]; then
                    COMPREPLY+=("*" "web-*" "prod-*" "dev-*")
                fi
            fi
            return
            ;;
        -H|--hostfile|-c|--command|-m|-t)
            # Let bash handle file/value completion
            return
            ;;
    esac
    
    # Show mussh options
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-h --hosts -H --hostfile -c --command -m -t -v -q" -- "$cur"))
    fi
}

# Register completions
complete -F _tssh_completion tssh
complete -F _ts_completion ts
complete -F _tscp_completion tscp
complete -F _tsftp_completion tsftp
complete -F _trsync_completion trsync
complete -F _tssh_copy_id_completion tssh_copy_id

# Only register tmussh completion if tmussh is available
if command -v tmussh >/dev/null 2>&1; then
    complete -F _tmussh_completion tmussh
fi
EOF
}

# Clean up old function-based installation
cleanup_old_installation() {
    local install_type="$1"  # "user" or "system"
    
    if [[ "$install_type" == "user" ]]; then
        # Remove old user function files
        local old_install_dir="$HOME/.config/tailscale-cli-helpers"
        if [[ -d "$old_install_dir" ]]; then
            echo "Removing old function-based installation from $old_install_dir..."
            rm -rf "$old_install_dir"
        fi
        
        # Remove old sourcing lines from shell RC files
        for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
            if [[ -f "$rc_file" ]]; then
                if grep -q "tailscale-cli-helpers/tailscale-ssh-helper.sh" "$rc_file" 2>/dev/null; then
                    echo "Removing old sourcing lines from $rc_file..."
                    # Create backup
                    cp "$rc_file" "$rc_file.bak.$(date +%Y%m%d_%H%M%S)"
                    # Remove lines containing the old source command
                    grep -v "tailscale-cli-helpers/tailscale-ssh-helper.sh" "$rc_file" > "$rc_file.tmp" && mv "$rc_file.tmp" "$rc_file"
                fi
            fi
        done
        
        # Remove old user completion files
        if [[ -f "$HOME/.local/share/bash-completion/completions/tailscale-ssh-helper" ]]; then
            rm -f "$HOME/.local/share/bash-completion/completions/tailscale-ssh-helper"
        fi
        
    elif [[ "$install_type" == "system" ]]; then
        # Remove old system function files
        local old_install_dir="/usr/share/tailscale-cli-helpers"
        if [[ -d "$old_install_dir" ]] && [[ ! -d "$old_install_dir/lib" ]]; then
            echo "Removing old function-based installation from $old_install_dir..."
            # Only remove if it doesn't have the new lib/ structure
            local old_files=("tailscale-ssh-helper.sh" "tailscale-functions.sh" "tailscale-completion.sh" "tailscale-mussh.sh" "tailscale-ts-dispatcher.sh")
            for file in "${old_files[@]}"; do
                [[ -f "$old_install_dir/$file" ]] && rm -f "$old_install_dir/$file"
            done
            # Remove directory if empty
            rmdir "$old_install_dir" 2>/dev/null || true
        fi
        
        # Remove old profile.d script
        if [[ -f "/etc/profile.d/tailscale-cli-helpers.sh" ]]; then
            echo "Removing old profile.d script..."
            rm -f "/etc/profile.d/tailscale-cli-helpers.sh"
        fi
        
        # Remove old bash completion if it contains function loading
        if [[ -f "/etc/bash_completion.d/tailscale-cli-helpers" ]]; then
            if grep -q "tailscale-ssh-helper.sh" "/etc/bash_completion.d/tailscale-cli-helpers" 2>/dev/null; then
                echo "Removing old bash completion script..."
                rm -f "/etc/bash_completion.d/tailscale-cli-helpers"
            fi
        fi
    fi
}

# Install for user
install_for_user() {
    echo "Installing Tailscale CLI helpers for current user..."
    
    # Clean up old installation first
    cleanup_old_installation "user"
    
    # Create directories
    local bin_dir="$HOME/.local/bin"
    local lib_dir="$HOME/.local/share/tailscale-cli-helpers/lib"
    local man_dir="$HOME/.local/share/man/man1"
    local completion_dir="$HOME/.local/share/bash-completion/completions"
    
    mkdir -p "$bin_dir" "$lib_dir" "$man_dir" "$completion_dir"
    
    # Security: Validate destination directories
    validate_destination_dir "$bin_dir" || return 1
    validate_destination_dir "$lib_dir" || return 1
    validate_destination_dir "$man_dir" || return 1
    validate_destination_dir "$completion_dir" || return 1
    
    # Install executables (excluding tmussh - optional)
    local commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id")
    for cmd in "${commands[@]}"; do
        if [[ -f "bin/$cmd" ]]; then
            validate_source_file "bin/$cmd" || return 1
            cp "bin/$cmd" "$bin_dir/" && chmod 755 "$bin_dir/$cmd"
            echo "Installed: $cmd"
        fi
    done
    
    # Optional: Install tmussh if mussh is available
    if command -v mussh >/dev/null 2>&1; then
        if [[ -f "bin/tmussh" ]]; then
            validate_source_file "bin/tmussh" || return 1
            cp "bin/tmussh" "$bin_dir/" && chmod 755 "$bin_dir/tmussh"
            echo "Installed: tmussh (mussh detected)"
        fi
    else
        echo "Skipped: tmussh (mussh not installed)"
    fi
    
    # Install shared library
    if [[ -f "lib/tailscale-resolver.sh" ]]; then
        validate_source_file "lib/tailscale-resolver.sh" || return 1
        cp "lib/tailscale-resolver.sh" "$lib_dir/" && chmod 644 "$lib_dir/tailscale-resolver.sh"
        echo "Installed: shared library"
    fi
    
    # Install man pages (excluding tmussh unless installed)
    for man in man/man1/*.1; do
        if [[ -f "$man" ]]; then
            local man_name="$(basename "$man")"
            # Skip tmussh man page if tmussh wasn't installed
            if [[ "$man_name" == "tmussh.1" ]] && ! command -v mussh >/dev/null 2>&1; then
                echo "Skipped: $man_name man page (mussh not installed)"
                continue
            fi
            validate_source_file "$man" || return 1
            gzip -c "$man" > "$man_dir/$man_name.gz"
            echo "Installed: $man_name man page"
        fi
    done
    
    # Install bash completion
    create_bash_completion "$completion_dir/tailscale-cli-helpers"
    echo "Installed: bash completions"
    
    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo ""
        echo "WARNING: $HOME/.local/bin is not in your PATH"
        echo "Add this line to your shell configuration file:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
    
    echo ""
    echo "Installation complete!"
    if command -v mussh >/dev/null 2>&1; then
        echo "Commands available: ts, tssh, tscp, tsftp, trsync, tssh_copy_id, tmussh"
    else
        echo "Commands available: ts, tssh, tscp, tsftp, trsync, tssh_copy_id"
        echo "Note: tmussh not installed (requires mussh)"
    fi
    echo ""
    echo "To enable bash completions in current shell:"
    echo "  source $completion_dir/tailscale-cli-helpers"
}

# Install system-wide
install_system_wide() {
    if [[ $EUID -ne 0 ]]; then
        echo "System-wide installation requires root privileges."
        echo "Please run with sudo: sudo $0 --system"
        return 1
    fi
    
    echo "Installing Tailscale CLI helpers system-wide..."
    
    # Clean up old installation first
    cleanup_old_installation "system"
    
    # Create directories
    local bin_dir="/usr/bin"
    local lib_dir="/usr/share/tailscale-cli-helpers/lib"
    local man_dir="/usr/share/man/man1"
    local completion_dir="/etc/bash_completion.d"
    
    mkdir -p "$lib_dir" "$completion_dir"
    
    # Security: Validate destination directories
    validate_destination_dir "$bin_dir" || return 1
    validate_destination_dir "$lib_dir" || return 1
    validate_destination_dir "$man_dir" || return 1
    validate_destination_dir "$completion_dir" || return 1
    
    # Install executables
    local commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id" "tmussh")
    for cmd in "${commands[@]}"; do
        if [[ -f "bin/$cmd" ]]; then
            validate_source_file "bin/$cmd" || return 1
            install -m 755 "bin/$cmd" "$bin_dir/"
            echo "Installed: $cmd"
        fi
    done
    
    # Install shared library
    if [[ -f "lib/tailscale-resolver.sh" ]]; then
        validate_source_file "lib/tailscale-resolver.sh" || return 1
        install -m 644 "lib/tailscale-resolver.sh" "$lib_dir/"
        echo "Installed: shared library"
    fi
    
    # Install man pages
    for man in man/man1/*.1; do
        if [[ -f "$man" ]]; then
            validate_source_file "$man" || return 1
            gzip -c "$man" > "$man_dir/$(basename "$man").gz"
            chmod 644 "$man_dir/$(basename "$man").gz"
            echo "Installed: $(basename "$man") man page"
        fi
    done
    
    # Install bash completion
    create_bash_completion "$completion_dir/tailscale-cli-helpers"
    chmod 644 "$completion_dir/tailscale-cli-helpers"
    echo "Installed: bash completions"
    
    echo ""
    echo "System-wide installation complete!"
    if command -v mussh >/dev/null 2>&1; then
        echo "Commands available: ts, tssh, tscp, tsftp, trsync, tssh_copy_id, tmussh"
    else
        echo "Commands available: ts, tssh, tscp, tsftp, trsync, tssh_copy_id"
        echo "Note: tmussh not installed (requires mussh)"
    fi
    echo "Commands are immediately available in all shells."
    echo "Bash completions will be available in new bash sessions."
}

# Uninstall
uninstall() {
    echo "Uninstalling Tailscale CLI helpers..."
    
    # Remove user installation
    if [[ -d "$HOME/.local/share/tailscale-cli-helpers" ]]; then
        rm -rf "$HOME/.local/share/tailscale-cli-helpers"
        echo "Removed user library files"
    fi
    
    # Remove user binaries
    local commands=("ts" "tssh" "tscp" "tsftp" "trsync" "tssh_copy_id" "tmussh")
    for cmd in "${commands[@]}"; do
        if [[ -f "$HOME/.local/bin/$cmd" ]]; then
            rm -f "$HOME/.local/bin/$cmd"
            echo "Removed user binary: $cmd"
        fi
    done
    
    # Remove user man pages
    for man in "$HOME/.local/share/man/man1"/ts*.1.gz; do
        if [[ -f "$man" ]]; then
            rm -f "$man"
            echo "Removed: $(basename "$man")"
        fi
    done
    
    # Remove user bash completion
    if [[ -f "$HOME/.local/share/bash-completion/completions/tailscale-cli-helpers" ]]; then
        rm -f "$HOME/.local/share/bash-completion/completions/tailscale-cli-helpers"
        echo "Removed user bash completions"
    fi
    
    # Remove system installation (requires root)
    if [[ $EUID -eq 0 ]]; then
        if [[ -d "/usr/share/tailscale-cli-helpers" ]]; then
            rm -rf "/usr/share/tailscale-cli-helpers"
            echo "Removed system library files"
        fi
        
        for cmd in "${commands[@]}"; do
            if [[ -f "/usr/bin/$cmd" ]]; then
                rm -f "/usr/bin/$cmd"
                echo "Removed system binary: $cmd"
            fi
        done
        
        for man in /usr/share/man/man1/ts*.1.gz; do
            if [[ -f "$man" ]]; then
                rm -f "$man"
                echo "Removed: $(basename "$man")"
            fi
        done
        
        if [[ -f "/etc/bash_completion.d/tailscale-cli-helpers" ]]; then
            rm -f "/etc/bash_completion.d/tailscale-cli-helpers"
            echo "Removed system bash completions"
        fi
    else
        echo "Note: Run with sudo to remove system-wide installation"
    fi
    
    echo "Uninstallation complete!"
}

# Main function
main() {
    local mode="auto"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user)
                mode="user"
                shift
                ;;
            --system)
                mode="system"
                shift
                ;;
            --uninstall)
                mode="uninstall"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --user       Install for current user only"
                echo "  --system     Install system-wide (requires sudo)"
                echo "  --uninstall  Remove installation"
                echo "  --help       Show this help message"
                echo ""
                echo "Without options, installs for current user if not root,"
                echo "or system-wide if running as root."
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check dependencies (except for uninstall)
    if [[ "$mode" != "uninstall" ]]; then
        check_dependencies || exit 1
    fi
    
    # Auto-detect mode if not specified
    if [[ "$mode" == "auto" ]]; then
        if [[ $EUID -eq 0 ]]; then
            mode="system"
        else
            mode="user"
        fi
    fi
    
    # Execute based on mode
    case "$mode" in
        user)
            install_for_user
            ;;
        system)
            install_system_wide
            ;;
        uninstall)
            uninstall
            ;;
    esac
}

main "$@"