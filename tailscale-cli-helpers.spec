Name:           tailscale-cli-helpers
Version:        1.0.0
Release:        1%{?dist}
Summary:        Bash/Zsh functions for easy SSH access to Tailscale nodes

License:        MIT
URL:            https://github.com/digitalcybersoft/tailscale-cli-helpers
Source0:        %{name}-%{version}.tar.gz

Requires:       bash
Requires:       jq
Requires:       tailscale
BuildArch:      noarch

%description
Provides convenient bash/zsh functions for SSH access to Tailscale nodes
with hostname completion and fuzzy matching. Includes the 'ts' command
for quick connections and smart host resolution.

%prep
%setup -q

%install
rm -rf $RPM_BUILD_ROOT

# Create directories
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/%{name}
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/profile.d
mkdir -p $RPM_BUILD_ROOT%{_bindir}
mkdir -p $RPM_BUILD_ROOT%{_docdir}/%{name}

# Install main files
install -m 644 tailscale-ssh-helper.sh $RPM_BUILD_ROOT%{_sysconfdir}/%{name}/
install -m 755 test-tailscale-helper.sh $RPM_BUILD_ROOT%{_sysconfdir}/%{name}/
install -m 755 setup.sh $RPM_BUILD_ROOT%{_bindir}/%{name}-setup

# Create profile.d script
cat > $RPM_BUILD_ROOT%{_sysconfdir}/profile.d/%{name}.sh << 'EOF'
# Tailscale CLI helpers
if [ -f %{_sysconfdir}/%{name}/tailscale-ssh-helper.sh ]; then
    . %{_sysconfdir}/%{name}/tailscale-ssh-helper.sh
fi
EOF

# Install documentation
install -m 644 README.md $RPM_BUILD_ROOT%{_docdir}/%{name}/

%files
%license LICENSE
%doc %{_docdir}/%{name}/README.md
%{_sysconfdir}/%{name}/tailscale-ssh-helper.sh
%{_sysconfdir}/%{name}/test-tailscale-helper.sh
%{_sysconfdir}/profile.d/%{name}.sh
%{_bindir}/%{name}-setup

%changelog
* Sun Jan 05 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 1.0.0-1
- Initial RPM release
- Provides ts command for Tailscale SSH connections
- Supports both bash and zsh with tab completion
- Includes fuzzy hostname matching