Name:           tailscale-cli-helpers
Version:        0.1.2
Release:        1%{?dist}
Summary:        Bash/Zsh functions for easy SSH access to Tailscale nodes

License:        MIT
URL:            https://github.com/digitalcybersoft/tailscale-cli-helpers
Source0:        https://github.com/digitalcybersoft/tailscale-cli-helpers/archive/refs/tags/v0.1.tar.gz

Requires:       bash
Requires:       jq
Requires:       tailscale
BuildArch:      noarch

%description
Provides convenient bash/zsh functions for SSH access to Tailscale nodes
with hostname completion and fuzzy matching. Includes the 'ts' command
for quick connections and smart host resolution.

%prep
%setup -q -n %{name}-0.1

%install
rm -rf $RPM_BUILD_ROOT

# Create directories
mkdir -p $RPM_BUILD_ROOT%{_datadir}/%{name}
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/profile.d
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/bash_completion.d
mkdir -p $RPM_BUILD_ROOT%{_bindir}
mkdir -p $RPM_BUILD_ROOT%{_docdir}/%{name}

# Install main files to /usr/share
install -m 644 tailscale-ssh-helper.sh $RPM_BUILD_ROOT%{_datadir}/%{name}/
install -m 644 tailscale-functions.sh $RPM_BUILD_ROOT%{_datadir}/%{name}/
install -m 644 tailscale-completion.sh $RPM_BUILD_ROOT%{_datadir}/%{name}/
install -m 755 setup.sh $RPM_BUILD_ROOT%{_bindir}/%{name}-setup

# Create profile.d script for all shells
cat > $RPM_BUILD_ROOT%{_sysconfdir}/profile.d/%{name}.sh << 'EOF'
# Tailscale CLI helpers
if [ -f %{_datadir}/%{name}/tailscale-ssh-helper.sh ]; then
    . %{_datadir}/%{name}/tailscale-ssh-helper.sh
fi
EOF

# Create bash completion script
cat > $RPM_BUILD_ROOT%{_sysconfdir}/bash_completion.d/%{name} << 'EOF'
# Tailscale CLI helpers bash completion
if [ -f %{_datadir}/%{name}/tailscale-ssh-helper.sh ]; then
    . %{_datadir}/%{name}/tailscale-ssh-helper.sh
fi
EOF

# Install documentation
install -m 644 README.md $RPM_BUILD_ROOT%{_docdir}/%{name}/

%files
%license LICENSE
%doc %{_docdir}/%{name}/README.md
%{_datadir}/%{name}/tailscale-ssh-helper.sh
%{_datadir}/%{name}/tailscale-functions.sh
%{_datadir}/%{name}/tailscale-completion.sh
%{_sysconfdir}/profile.d/%{name}.sh
%{_sysconfdir}/bash_completion.d/%{name}
%{_bindir}/%{name}-setup

%changelog
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