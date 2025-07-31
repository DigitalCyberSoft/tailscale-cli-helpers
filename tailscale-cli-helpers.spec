Name:           tailscale-cli-helpers
Version:        0.2.4
Release:        1
Summary:        Bash/Zsh functions for easy SSH access to Tailscale nodes

License:        MIT
URL:            https://github.com/digitalcybersoft/tailscale-cli-helpers
Source0:        https://github.com/digitalcybersoft/tailscale-cli-helpers/archive/refs/tags/v0.2.4.tar.gz

Requires:       bash
Requires:       jq
Requires:       tailscale
BuildArch:      noarch

# Suggest the mussh extension (will show as optional dependency)
Suggests:       tailscale-cli-helpers-mussh

%description
Provides convenient bash/zsh functions for SSH access to Tailscale nodes
with hostname completion and fuzzy matching. Includes the 'tssh' command
(with 'ts' alias) for quick connections, 'tscp' for file transfers,
'trsync' for rsync operations, and 'tmussh' for parallel SSH execution
across multiple nodes.

%prep
%setup -q -n %{name}-0.2.4

%install
rm -rf $RPM_BUILD_ROOT

# Create directories
mkdir -p $RPM_BUILD_ROOT%{_bindir}
mkdir -p $RPM_BUILD_ROOT%{_datadir}/%{name}/lib
mkdir -p $RPM_BUILD_ROOT%{_mandir}/man1
mkdir -p $RPM_BUILD_ROOT%{_docdir}/%{name}

# Install executables (excluding tmussh - separate package)
install -m 755 bin/ts $RPM_BUILD_ROOT%{_bindir}/
install -m 755 bin/tssh $RPM_BUILD_ROOT%{_bindir}/
install -m 755 bin/tscp $RPM_BUILD_ROOT%{_bindir}/
install -m 755 bin/tsftp $RPM_BUILD_ROOT%{_bindir}/
install -m 755 bin/trsync $RPM_BUILD_ROOT%{_bindir}/
install -m 755 bin/tssh_copy_id $RPM_BUILD_ROOT%{_bindir}/

# Install shared libraries
install -m 644 lib/tailscale-resolver.sh $RPM_BUILD_ROOT%{_datadir}/%{name}/lib/
install -m 644 lib/common.sh $RPM_BUILD_ROOT%{_datadir}/%{name}/lib/

# Install man pages (excluding tmussh - separate package)
for man in man/man1/*.1; do
    if [[ "$(basename "$man")" != "tmussh.1" ]]; then
        gzip -c "$man" > $RPM_BUILD_ROOT%{_mandir}/man1/$(basename "$man").gz
    fi
done

# Install setup script
install -m 755 setup.sh $RPM_BUILD_ROOT%{_bindir}/%{name}-setup

# Create bash completion
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/bash_completion.d
cat > $RPM_BUILD_ROOT%{_sysconfdir}/bash_completion.d/%{name} << 'EOF'
# Bash completion for Tailscale CLI helpers

# Source the shared library for host list functions
if [[ -f /usr/share/tailscale-cli-helpers/lib/tailscale-resolver.sh ]]; then
    source /usr/share/tailscale-cli-helpers/lib/tailscale-resolver.sh
fi

# Completion for tssh
_tssh_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Handle options that need values
    case "$prev" in
        -i|-l|-p|-F|-E|-L|-R|-D|-W|-J|-Q|-c|-m|-b|-e|-o)
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
    
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        local available_commands="help ssh ssh_copy_id"
        command -v scp >/dev/null 2>&1 && available_commands="$available_commands scp"
        command -v sftp >/dev/null 2>&1 && available_commands="$available_commands sftp"
        command -v rsync >/dev/null 2>&1 && available_commands="$available_commands rsync"
        command -v tmussh >/dev/null 2>&1 && available_commands="$available_commands mussh"
        
        local hosts=""
        if type -t get_all_tailscale_hosts >/dev/null 2>&1; then
            hosts=$(get_all_tailscale_hosts 2>/dev/null)
        fi
        
        COMPREPLY=($(compgen -W "$available_commands $hosts" -- "$cur"))
        return
    fi
    
    case "${COMP_WORDS[1]}" in
        ssh|sftp) _tssh_completion ;;
        ssh_copy_id) _tssh_copy_id_completion ;;
        scp) _tscp_completion ;;
        rsync) _trsync_completion ;;
        mussh) 
            # Delegate to tmussh if available
            if command -v tmussh >/dev/null 2>&1; then
                # Use basic completion
                COMPREPLY=($(compgen -W "-h --hosts -H --hostfile -c --command" -- "$cur"))
            fi
            ;;
    esac
}

# Register completions
complete -F _tssh_completion tssh
complete -F _ts_completion ts
complete -F _tssh_completion tsftp
complete -F _tssh_copy_id_completion tssh_copy_id

# Simplified completions for file transfer commands
_tscp_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ "$cur" != *:* ]]; then
        if type -t get_all_tailscale_hosts >/dev/null 2>&1; then
            local hosts=$(get_all_tailscale_hosts 2>/dev/null)
            if [[ -n "$hosts" ]]; then
                COMPREPLY=($(compgen -W "$hosts" -- "$cur" | sed 's/$/:\/~/'))
            fi
        fi
        COMPREPLY+=($(compgen -f -- "$cur"))
    fi
}

_trsync_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-v -a -r -z --delete --exclude --dry-run" -- "$cur"))
    else
        _tscp_completion
    fi
}

_tssh_copy_id_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    case "$prev" in
        -i|-p|-o|-J) return ;;
    esac
    
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-i -p -o -f -J" -- "$cur"))
    elif type -t get_all_tailscale_hosts >/dev/null 2>&1; then
        local hosts=$(get_all_tailscale_hosts 2>/dev/null)
        if [[ -n "$hosts" ]]; then
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

# tmussh completion moved to separate package

complete -F _tscp_completion tscp
complete -F _trsync_completion trsync
EOF

# Install documentation
install -m 644 README.md $RPM_BUILD_ROOT%{_docdir}/%{name}/

%post
# Migration: Remove old function-based installation
if [ -f /etc/profile.d/tailscale-cli-helpers.sh ]; then
    # Check if it's the old version (contains source commands)
    if grep -q "tailscale-ssh-helper.sh" /etc/profile.d/tailscale-cli-helpers.sh 2>/dev/null; then
        rm -f /etc/profile.d/tailscale-cli-helpers.sh
    fi
fi

# Remove old function files if they exist without new structure
if [ -d /usr/share/tailscale-cli-helpers ] && [ ! -d /usr/share/tailscale-cli-helpers/lib ]; then
    rm -f /usr/share/tailscale-cli-helpers/tailscale-ssh-helper.sh
    rm -f /usr/share/tailscale-cli-helpers/tailscale-functions.sh
    rm -f /usr/share/tailscale-cli-helpers/tailscale-completion.sh
    rm -f /usr/share/tailscale-cli-helpers/tailscale-mussh.sh
    rm -f /usr/share/tailscale-cli-helpers/tailscale-ts-dispatcher.sh
    rmdir /usr/share/tailscale-cli-helpers 2>/dev/null || true
fi

%files
%license LICENSE
%doc %{_docdir}/%{name}/README.md
%{_bindir}/ts
%{_bindir}/tssh
%{_bindir}/tscp
%{_bindir}/tsftp
%{_bindir}/trsync
%{_bindir}/tssh_copy_id
%{_datadir}/%{name}/lib/tailscale-resolver.sh
%{_datadir}/%{name}/lib/common.sh
%{_mandir}/man1/ts.1.gz
%{_mandir}/man1/tssh.1.gz
%{_mandir}/man1/tscp.1.gz
%{_mandir}/man1/tsftp.1.gz
%{_mandir}/man1/trsync.1.gz
%{_mandir}/man1/tssh_copy_id.1.gz
%{_sysconfdir}/bash_completion.d/%{name}
%{_bindir}/%{name}-setup

%changelog
* Thu Jul 31 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.2.4-1
- Fixed missing common.sh library in package (fixes version display)
- Updated Debian packaging to use new bin/ structure
- Fixed Debian rules to install all required files

* Thu Jul 31 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.2.3-1
- Renamed tmussh package to mussh for clarity
- Added Suggests for optional mussh extension package
- Added Supplements tag to auto-install mussh extension when mussh is present

* Thu Jul 31 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.2.2-1
- Split tmussh into separate optional package for better dependency management
- Added comprehensive development documentation (CLAUDE.md)
- Implemented Debian package post-install migration script
- Restructured project with bin/, lib/, and man/ directories
- Updated all packaging specs for modular distribution
- Enhanced setup.sh with improved error handling and platform detection
- Updated test suites for better coverage and reliability

* Wed Jul 24 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.2.1-1
- Major security hardening with input validation and injection protection
- Added tsftp command for SFTP support as modern alternative to SCP
- Enhanced tab completion with version-aware features and Levenshtein sorting
- Fixed internal functions appearing in tab completion
- Refactored shared code to eliminate ~250 lines of duplication
- Added 40+ security tests covering all attack vectors
- Improved tmussh with multi-host functionality and pattern support

* Wed Jul 24 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.2.0-1
- MAJOR: Refactored from shell functions to standalone executables
- Commands now immediately available after installation (no shell restart needed)
- Added complete man pages for all commands
- Enhanced bash completions with smart hostname resolution
- Added migration logic to clean up old function-based installations
- All commands now installed to /usr/bin for immediate availability
- Maintained all existing functionality: fuzzy matching, security, multi-shell support

* Tue Jul 22 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.1.3-1
- Added MagicDNS fallback to IP when resolv.conf is misconfigured
- Fixed autocomplete to return hostnames without domain suffix

* Sun Jan 05 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.1.2-1
- Added ssh-copy-id alias with Tailscale support
- Enhanced tab completion for ssh-copy-id command
- Improved integration with existing SSH workflows

* Sun Jan 05 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.1.1-1
- Major restructure: split into modular components
- Enhanced cross-shell compatibility (bash/zsh)
- Comprehensive test suite
- System-wide installation support
- Improved setup script with sudo prompting

* Sun Jan 05 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.1-1
- Initial RPM release
- Provides ts command for Tailscale SSH connections
- Supports both bash and zsh with tab completion
- Includes fuzzy hostname matching