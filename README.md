# Tailscale CLI Helpers

Bash/Zsh functions for easy SSH access to Tailscale nodes with hostname completion and fuzzy matching.

## Features

- **Quick SSH connections**: Use `ts hostname` to connect to any Tailscale node
- **Tab completion**: Autocomplete Tailscale hostnames and usernames
- **Fuzzy matching**: Find hosts even with partial names
- **Smart resolution**: Automatically uses MagicDNS when available, falls back to IPs
- **SSH fallback**: Seamlessly falls back to regular SSH for non-Tailscale hosts
- **Multi-shell support**: Works with both Bash and Zsh
- **ssh-copy-id wrapper**: Smart host resolution for `dcs_ssh_copy_id` command

## Requirements

- Bash 4.0+ or Zsh
- `jq` (JSON processor)
- `tailscale` (Tailscale CLI)
- SSH client

## Installation

### Quick Install (Universal)

```bash
# Clone the repository
git clone https://github.com/digitalcybersoft/tailscale-cli-helpers.git
cd tailscale-cli-helpers

# Run the setup script (auto-detects privileges)
./setup.sh              # Install for current user
sudo ./setup.sh         # Install system-wide (auto-detected)

# Or explicitly specify installation type
./setup.sh --user       # Force user installation
sudo ./setup.sh --system # Force system-wide installation
```

**System-wide installation locations:**
- Scripts: `/usr/share/tailscale-cli-helpers/`
- Shell loading: `/etc/profile.d/tailscale-cli-helpers.sh`
- Bash completion: `/etc/bash_completion.d/tailscale-cli-helpers`

**User installation locations:**
- Scripts: `~/.config/tailscale-cli-helpers/`
- Shell loading: Added to `~/.bashrc` or `~/.zshrc`

### Fedora/RHEL (RPM)

#### Option 1: Build and install RPM
```bash
# Install build tools
sudo dnf install -y rpm-build rpmdevtools

# Setup build environment
rpmdev-setuptree

# Build the package
cd tailscale-cli-helpers
wget https://github.com/digitalcybersoft/tailscale-cli-helpers/archive/refs/tags/v0.1.tar.gz -O ~/rpmbuild/SOURCES/v0.1.tar.gz
rpmbuild -ba tailscale-cli-helpers.spec

# Install the package
sudo rpm -ivh ~/rpmbuild/RPMS/noarch/tailscale-cli-helpers-0.1-1.*.noarch.rpm
```

#### Option 2: Manual RPM installation
The RPM package installs to standard system locations:
- Scripts in `/usr/share/tailscale-cli-helpers/`
- Automatically loaded via `/etc/profile.d/tailscale-cli-helpers.sh`
- Bash completion in `/etc/bash_completion.d/tailscale-cli-helpers`

After installation, the `ts` command is immediately available in new shell sessions.

### Ubuntu/Debian (DEB)

#### Option 1: Build and install DEB
```bash
# Install build tools
sudo apt-get install -y build-essential debhelper

# Build the package
cd tailscale-cli-helpers
dpkg-buildpackage -us -uc

# Install the package
sudo dpkg -i ../tailscale-cli-helpers_0.1-1_all.deb
sudo apt-get install -f  # Install dependencies if needed
```

#### Option 2: Manual DEB installation
The DEB package installs to standard system locations:
- Scripts in `/usr/share/tailscale-cli-helpers/`
- Automatically loaded via `/etc/profile.d/tailscale-cli-helpers.sh`
- Bash completion in `/etc/bash_completion.d/tailscale-cli-helpers`

After installation, the `ts` command is immediately available in new shell sessions.

### macOS

```bash
# Install dependencies
brew install jq tailscale

# Clone and setup
git clone https://github.com/digitalcybersoft/tailscale-cli-helpers.git
cd tailscale-cli-helpers
./setup.sh

# macOS setup script will install to user locations:
# - Scripts: ~/.config/tailscale-cli-helpers/
# - Shell loading: Added to ~/.zshrc or ~/.bash_profile
```

## Usage

### Basic Commands

```bash
# Connect to a Tailscale node (defaults to root user)
ts hostname

# Connect as a specific user
ts user@hostname

# Enable verbose/debug mode
ts -v hostname

# Test the installation
./tests/test-tailscale-helper.sh
```

### Tab Completion

The `ts` command supports intelligent tab completion:

```bash
# Complete hostnames
ts host<TAB>              # Shows all matching Tailscale hosts

# Complete usernames
ts ro<TAB>                # Completes to "root@"
ts admin@<TAB>            # Shows all hosts for admin user

# Partial matching
ts @prod<TAB>             # Shows all hosts containing "prod"
```

### SSH Key Distribution

The package includes an enhanced `ssh-copy-id` that understands Tailscale hosts:

```bash
# Copy SSH key to a Tailscale node
ssh-copy-id user@hostname

# Use with ProxyJump
ssh-copy-id -J jumphost user@destination
```

## How It Works

1. **Host Resolution**: When you type `ts hostname`, the function:
   - Checks if the host exists in your Tailscale network
   - Uses MagicDNS names when available
   - Falls back to Tailscale IPs when MagicDNS is disabled
   - Tries regular SSH if the host isn't in Tailscale

2. **Fuzzy Matching**: Uses Levenshtein distance algorithm to find the closest matching hostname when multiple matches exist

3. **Completion**: Integrates with your shell's completion system to provide real-time suggestions

## Uninstallation

```bash
# Remove user installation
./setup.sh --uninstall

# Remove system-wide installation
sudo ./setup.sh --uninstall

# Or manually remove from your shell RC file
# Remove the tailscale-cli-helpers source lines from ~/.bashrc or ~/.zshrc
```

## Troubleshooting

### Functions not available after installation
- Source your shell configuration: `source ~/.bashrc` or `source ~/.zshrc`
- Start a new shell session

### Tab completion not working
- Ensure bash-completion or zsh-completions is installed
- Check that the functions are properly sourced

### Missing dependencies
- Fedora/RHEL: `sudo dnf install jq tailscale`
- Ubuntu/Debian: `sudo apt-get install jq tailscale`
- macOS: `brew install jq tailscale`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.