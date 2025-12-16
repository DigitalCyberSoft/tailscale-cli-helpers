Name:           tailscale-cli-helpers
Version:        0.3.3
Release:        1
Summary:        Bash/Zsh functions for easy SSH access to Tailscale nodes

License:        MIT
URL:            https://github.com/digitalcybersoft/tailscale-cli-helpers
Source0:        https://github.com/digitalcybersoft/tailscale-cli-helpers/archive/refs/tags/v0.3.3.tar.gz

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
%setup -q -n %{name}-0.3.3

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
install -m 755 bin/tsexit $RPM_BUILD_ROOT%{_bindir}/

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

# Install bash completion
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/bash_completion.d
install -m 644 bash-completion/tailscale-completion.sh $RPM_BUILD_ROOT%{_sysconfdir}/bash_completion.d/%{name}

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
%{_bindir}/tsexit
%{_datadir}/%{name}/lib/tailscale-resolver.sh
%{_datadir}/%{name}/lib/common.sh
%{_mandir}/man1/ts.1.gz
%{_mandir}/man1/tssh.1.gz
%{_mandir}/man1/tscp.1.gz
%{_mandir}/man1/tsftp.1.gz
%{_mandir}/man1/trsync.1.gz
%{_mandir}/man1/tssh_copy_id.1.gz
%{_mandir}/man1/tsexit.1.gz
%{_sysconfdir}/bash_completion.d/%{name}
%{_bindir}/%{name}-setup

%changelog
* Thu Dec 11 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.3.3-1
- Fix tsexit to use short hostname instead of FQDN for exit node selection

* Thu Dec 11 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.3.2-1
- Fix ts dispatcher intercepting -h flag meant for subcommands
- Fix tmussh wildcard expansion to use IPs when MagicDNS unavailable

* Mon Aug 18 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.3.1-1
- Added tsexit command for interactive exit node management
- Supports Mullvad multi-country exit nodes with country grouping
- Features arrow key navigation and automatic sudo elevation
- Countries collapsed by default, expandable with Enter or right arrow
- Jump-to-country feature using letter keys

* Thu Jul 31 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.3.0-1
- Restored functionality that was accidentally deleted during modular refactoring
- Restored multiple host selection menu with fuzzy matching
- Restored security validation functions (_sanitize_pattern)
- Restored tab completion (tailscale-completion.sh)
- Fixed test counting that was broken (showing 0/0)
- Updated all tests to work with new modular structure

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

* Thu Jul 24 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.2.1-1
- Major security hardening with input validation and injection protection
- Added tsftp command for SFTP support as modern alternative to SCP
- Enhanced tab completion with version-aware features and Levenshtein sorting
- Fixed internal functions appearing in tab completion
- Refactored shared code to eliminate ~250 lines of duplication
- Added 40+ security tests covering all attack vectors
- Improved tmussh with multi-host functionality and pattern support

* Thu Jul 24 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.2.0-1
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