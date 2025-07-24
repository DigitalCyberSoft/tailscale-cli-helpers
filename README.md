# Tailscale CLI Helpers

Bash/Zsh functions for easy SSH access to Tailscale nodes with hostname completion and fuzzy matching.

## 🚀 Quick Start

```bash
# One-line install
curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash

# Then use commands
tssh myhost                    # SSH to Tailscale host
tscp file.txt myhost:/path/    # Copy files
ts rsync -av dir/ myhost:/     # Sync directories (if ts dispatcher installed)
```

## Features

- **Quick SSH connections**: Use `tssh hostname` or `ts hostname` to connect to any Tailscale node
- **SSH options passthrough**: Full support for SSH flags like `-p 2222`, `-i keyfile`, etc.
- **SCP support**: Use `tscp` for file transfers with Tailscale hostname resolution
- **Rsync support**: Use `trsync` for efficient file synchronization with Tailscale hosts
- **Parallel SSH**: Use `tmussh` for executing commands on multiple hosts (requires mussh)
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

### 🚀 Quick Install (One-line)

```bash
# Install for current user (prompts for ts dispatcher)
curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash

# System-wide install (includes ts dispatcher)
curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | sudo bash -s -- --system

# Install without ts dispatcher
curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash -s -- --no-dispatcher

# Uninstall
curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash -s -- --uninstall
```

### Manual Install (Local Development)

```bash
# Clone the repository
git clone https://github.com/digitalcybersoft/tailscale-cli-helpers.git
cd tailscale-cli-helpers

# Run the setup script (auto-detects privileges)
./setup.sh              # Install for current user (asks about ts dispatcher)
sudo ./setup.sh         # Install system-wide (includes ts dispatcher)

# Or explicitly specify installation type
./setup.sh --user       # Force user installation (asks about ts dispatcher)
sudo ./setup.sh --system # Force system-wide installation (includes ts dispatcher)
```

**Note:** The one-line installer automatically downloads the latest version from GitHub. When installing manually, you'll be asked whether to install the `ts` dispatcher command.

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

### 🔄 Updating

To update to the latest version, simply re-run the installation command:

```bash
# Update user installation
curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | bash

# Update system-wide installation
curl -fsSL https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/install.sh | sudo bash -s -- --system
```

The installer will automatically overwrite existing files with the latest versions and display version information during installation.

### Debian-based Systems (DEB)

#### Option 1: Download and install pre-built DEB
```bash
# Download the latest DEB package
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/releases/download/v0.1/tailscale-cli-helpers_0.1-2_all.deb

# Install the package (works on all DEB-based systems)
sudo dpkg -i tailscale-cli-helpers_0.1-2_all.deb
sudo apt-get install -f  # Install dependencies if needed
```

#### Option 2: Build and install DEB from source
```bash
# Install build tools (adjust package manager as needed)
sudo apt-get install -y build-essential debhelper    # Debian/Ubuntu
# sudo apt install -y build-essential debhelper      # Ubuntu/Mint

# Build the package
cd tailscale-cli-helpers
dpkg-buildpackage -us -uc

# Install the package
sudo dpkg -i ../tailscale-cli-helpers_0.1-1_all.deb
sudo apt-get install -f  # Install dependencies if needed
```

#### Package Installation Details
The DEB package installs to standard system locations:
- Scripts in `/usr/share/tailscale-cli-helpers/`
- Automatically loaded via `/etc/profile.d/tailscale-cli-helpers.sh`
- Bash completion in `/etc/bash_completion.d/tailscale-cli-helpers`

After installation, the `ts` command is immediately available in new shell sessions.

### macOS

#### Option 1: Homebrew (Recommended)
```bash
# Install via Homebrew (includes dependencies)
brew install https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/tailscale-cli-helpers.rb
```

#### Option 2: Manual Installation
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

## Usage

### SSH Connections

The main command is `tssh`, with `ts` as a multi-command dispatcher:

```bash
# Direct tssh usage
tssh hostname             # Connects as root@hostname
tssh user@hostname        # With specific user

# ts dispatcher usage
ts hostname               # SSH to hostname (default)
ts ssh hostname           # Explicit SSH command
ts ssh user@hostname      # SSH with user

# With SSH options
tssh hostname -p 2222                    # Custom port
tssh hostname -i ~/.ssh/custom_key       # Custom key
ts ssh hostname -o StrictHostKeyChecking=no # SSH options via dispatcher

# Debug mode
tssh -v hostname          # Shows verbose debug output
```

### ts Dispatcher Command

The `ts` command works as a dispatcher for all Tailscale operations:

```bash
# Show available commands
ts                        # Shows help and available subcommands

# SSH (default behavior)
ts hostname               # SSH to hostname
ts ssh hostname           # Explicit SSH

# File operations
ts scp file.txt host:/path    # Copy files
ts rsync -av dir/ host:/path/ # Sync directories

# Parallel operations (if mussh installed)
ts mussh -h host1 host2 -c "uptime"  # Execute on multiple hosts
```

### File Transfers with tscp

The `tscp` command provides SCP functionality with Tailscale hostname resolution:

```bash
# Copy file to remote host
tscp localfile.txt hostname:/remote/path/
tscp localfile.txt user@hostname:/remote/path/

# Copy from remote host
tscp hostname:/remote/file.txt ./
tscp user@hostname:/remote/file.txt ./

# With SCP options
tscp -r local_dir/ hostname:/remote/path/  # Recursive copy
tscp -P 2222 file.txt hostname:/path/      # Custom port
```

### File Synchronization with trsync

The `trsync` command provides rsync functionality with Tailscale hostname resolution:

```bash
# Sync directory to remote host
trsync -av local_dir/ hostname:/remote/path/
trsync -av local_dir/ user@hostname:/remote/path/

# Sync from remote host
trsync -av hostname:/remote/path/ local_dir/
trsync -av user@hostname:/remote/path/ local_dir/

# Common rsync options work as expected
trsync -avz --delete source/ hostname:/dest/     # Compress, delete removed files
trsync -av --exclude='*.log' dir/ hostname:/dir/ # Exclude patterns
trsync -av --dry-run source/ hostname:/dest/     # Preview changes

# Debug mode shows hostname resolution
trsync -v source/ hostname:/dest/                # Shows resolved hostname/IP
```

### Parallel SSH with tmussh

When `mussh` is installed, `tmussh` provides parallel SSH execution across multiple Tailscale nodes:

```bash
# Execute command on multiple hosts
tmussh -h host1 host2 host3 -c "uptime"

# Using wildcards (resolved to Tailscale hosts)
tmussh -h "web-*" -c "systemctl status nginx"

# With parallel execution limit
tmussh -m 5 -h "prod-*" -c "df -h"

# Different users per host
tmussh -h admin@web1 root@web2 -c "whoami"

# From host file
tmussh -H hostlist.txt -c "hostname"
```

### Tab Completion

All commands support intelligent tab completion:

```bash
# Complete hostnames
tssh host<TAB>            # Shows all matching Tailscale hosts
ts host<TAB>              # Same with alias

# Complete usernames
tssh ro<TAB>              # Completes to "root@"
tssh admin@<TAB>          # Shows all hosts for admin user

# Partial matching
tssh @prod<TAB>           # Shows all hosts containing "prod"
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