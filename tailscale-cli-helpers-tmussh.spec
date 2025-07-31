Name:           tailscale-cli-helpers-tmussh
Version:        0.2.2
Release:        1
Summary:        Parallel SSH execution on Tailscale nodes using mussh

License:        MIT
URL:            https://github.com/digitalcybersoft/tailscale-cli-helpers
Source0:        https://github.com/digitalcybersoft/tailscale-cli-helpers/archive/refs/tags/v0.2.2.tar.gz

Requires:       tailscale-cli-helpers = %{version}-%{release}
Requires:       mussh
BuildArch:      noarch

%description
Provides the tmussh command for parallel SSH execution across multiple 
Tailscale nodes using mussh. This is an optional extension to the main
tailscale-cli-helpers package that adds multi-host parallel execution
capabilities with wildcard pattern support.

Features:
- Parallel SSH execution on multiple Tailscale nodes
- Wildcard pattern support (e.g., "web-*", "prod-*")
- Automatic Tailscale hostname resolution
- Integration with mussh for robust parallel execution

%prep
%setup -q -n tailscale-cli-helpers-0.2.2

%install
rm -rf $RPM_BUILD_ROOT

# Create directories
mkdir -p $RPM_BUILD_ROOT%{_bindir}
mkdir -p $RPM_BUILD_ROOT%{_mandir}/man1
mkdir -p $RPM_BUILD_ROOT%{_docdir}/%{name}

# Install tmussh executable
install -m 755 bin/tmussh $RPM_BUILD_ROOT%{_bindir}/

# Install man page
gzip -c man/man1/tmussh.1 > $RPM_BUILD_ROOT%{_mandir}/man1/tmussh.1.gz

# Install documentation
echo "Tailscale CLI Helpers - tmussh Extension

This package provides the tmussh command for parallel SSH execution
across multiple Tailscale nodes using mussh.

Usage:
  tmussh -h host1 host2 host3 -c \"uptime\"
  tmussh -h \"web-*\" -c \"systemctl status nginx\"
  tmussh -m 5 -h \"prod-*\" -c \"df -h\"

See: man tmussh for complete documentation" > $RPM_BUILD_ROOT%{_docdir}/%{name}/README

%files
%doc %{_docdir}/%{name}/README
%{_bindir}/tmussh
%{_mandir}/man1/tmussh.1.gz

%changelog
* Thu Jul 31 2025 Digital Cyber Soft <support@digitalcybersoft.com> - 0.2.2-1
- Initial separate package for tmussh
- Requires mussh and main tailscale-cli-helpers package
- Provides parallel SSH execution on Tailscale nodes
- Supports wildcard patterns for host selection