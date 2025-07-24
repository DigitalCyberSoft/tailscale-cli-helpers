# Tailscale CLI Helpers

Comprehensive Bash/Zsh functions for secure SSH, file transfer, and parallel operations on Tailscale nodes with advanced hostname completion and fuzzy matching.

## 🚀 Quick Start

```bash
# One-line install
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/v0.2.1.tar.gz
tar -xzf v0.2.1.tar.gz && cd tailscale-cli-helpers-0.2.1
./setup.sh

# Then use commands
tssh myhost                     # SSH to Tailscale host
tscp file.txt myhost:/path/     # Copy files (SCP)
tsftp myhost                    # Secure file transfer (SFTP)
trsync -av dir/ myhost:/        # Sync directories (rsync)
tmussh -h "web-*" -c "uptime"   # Parallel SSH execution
tssh_copy_id myhost             # Copy SSH keys
ts ssh_copy_id myhost           # Via dispatcher
```

## ✨ Features

### 🔐 Secure SSH & File Operations
- **Quick SSH connections**: Use `tssh hostname` or `ts hostname` to connect to any Tailscale node
- **SSH options passthrough**: Full support for SSH flags like `-p 2222`, `-i keyfile`, etc.
- **SSH key management**: `tssh_copy_id` and `ts ssh_copy_id` for secure key distribution
- **Security hardened**: Input validation, command injection prevention, and secure argument handling

### 📁 Multiple File Transfer Methods
- **SCP support**: `tscp` for traditional file transfers with Tailscale hostname resolution
- **Modern SFTP**: `tsftp` command as secure alternative to deprecated SCP protocol
- **Rsync support**: `trsync` for efficient file synchronization with Tailscale hosts
- **Conditional loading**: Commands only load when underlying tools (scp, sftp, rsync) are available

### 🚀 Advanced Features
- **Parallel SSH**: `tmussh` for executing commands on multiple hosts simultaneously (requires mussh)
- **Version-aware completion**: Detects mussh version and offers appropriate parameters
- **Wildcard support**: Use patterns like `"web-*"` for multi-host operations
- **Intelligent tab completion**: Autocomplete Tailscale hostnames with Levenshtein distance sorting
- **Fuzzy matching**: Find hosts even with partial names, sorted by similarity

### 🔧 Smart Resolution & Compatibility
- **Smart resolution**: Automatically uses MagicDNS when available, falls back to IPs
- **SSH fallback**: Seamlessly falls back to regular SSH for non-Tailscale hosts
- **Multi-shell support**: Works with both Bash and Zsh with full compatibility
- **Conditional features**: Only enables commands when required tools are installed
- **Clean completion**: Internal functions hidden from tab completion

## 📋 Requirements

### Core Requirements
- **Shell**: Bash 4.0+ or Zsh
- **JSON processor**: `jq` for parsing Tailscale status
- **Tailscale CLI**: `tailscale` command must be installed and running
- **SSH client**: Standard `ssh` command

### Optional Dependencies (Auto-detected)
- **scp**: For `tscp` file transfer functionality
- **sftp**: For `tsftp` secure file transfer functionality  
- **rsync**: For `trsync` synchronization functionality
- **mussh**: For `tmussh` parallel SSH execution

**Note**: Commands are conditionally loaded - only available tools will be enabled.

## Installation

### 🚀 Quick Install (Recommended)

```bash
# Download latest release
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/v0.2.1.tar.gz
tar -xzf v0.2.1.tar.gz
cd tailscale-cli-helpers-0.2.1

# Install for current user
./setup.sh

# OR install system-wide (requires sudo)
sudo ./setup.sh --system

# Test installation
./tests/test-both-shells.sh
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

### 📦 Package Installation

#### Fedora/RHEL/CentOS (RPM)
```bash
# Download and install RPM package
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/releases/download/v0.2.1/tailscale-cli-helpers-0.2.1-1.noarch.rpm
sudo rpm -i tailscale-cli-helpers-0.2.1-1.noarch.rpm
```

#### Ubuntu/Debian (DEB)
```bash
# Download and install DEB package
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/releases/download/v0.2.1/tailscale-cli-helpers_0.2.1-2_all.deb
sudo dpkg -i tailscale-cli-helpers_0.2.1-2_all.deb
```

#### Package Installation Details
Both packages install to standard system locations:
- **Scripts**: `/usr/share/tailscale-cli-helpers/`
- **Auto-loading**: `/etc/profile.d/tailscale-cli-helpers.sh`
- **Bash completion**: `/etc/bash_completion.d/tailscale-cli-helpers`
- **Setup command**: `/usr/bin/tailscale-cli-helpers-setup`

After installation, all commands are immediately available in new shell sessions.

### 🔄 Updating

```bash
# Update to latest version (manual installation)
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/v0.2.1.tar.gz
tar -xzf v0.2.1.tar.gz
cd tailscale-cli-helpers-0.2.1
./setup.sh  # Will update existing installation

# Update package installations
sudo rpm -U tailscale-cli-helpers-0.2.1-1.noarch.rpm     # RPM systems
sudo dpkg -i tailscale-cli-helpers_0.2.1-2_all.deb       # DEB systems
```

### 🍎 macOS Installation

```bash
# Install dependencies first
brew install jq tailscale

# Download and install
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/v0.2.1.tar.gz
tar -xzf v0.2.1.tar.gz
cd tailscale-cli-helpers-0.2.1
./setup.sh

# macOS installs to user locations:
# - Scripts: ~/.config/tailscale-cli-helpers/
# - Shell loading: Added to ~/.zshrc or ~/.bash_profile
```

## 🎯 Usage

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

### 🔑 SSH Key Management

Secure SSH key distribution with Tailscale hostname resolution:

```bash
# Copy SSH key to Tailscale node
tssh_copy_id hostname                    # As root
tssh_copy_id user@hostname               # As specific user

# Via ts dispatcher
ts ssh_copy_id hostname                  # Same functionality
ts ssh_copy_id user@hostname

# With ProxyJump (auto-resolves both hosts)
tssh_copy_id -J jumphost user@destination

# Standard ssh-copy-id options work
tssh_copy_id -i ~/.ssh/custom_key.pub hostname
```

### 🗂️ Modern File Transfer (SFTP)

Secure file transfer using SFTP protocol:

```bash
# Interactive SFTP session
tsftp hostname                           # Connect as root
tsftp user@hostname                      # Connect as specific user

# Via ts dispatcher
ts sftp hostname                         # Same functionality
ts sftp user@hostname

# SFTP with options
tsftp -P 2222 hostname                   # Custom port
tsftp -i ~/.ssh/custom_key hostname      # Custom identity file

# Example SFTP session:
# sftp> put localfile.txt /remote/path/
# sftp> get /remote/file.txt ./
# sftp> ls -la
# sftp> quit
```

## 🔧 How It Works

### 🎯 Intelligent Host Resolution
When you type `ts hostname`, the system:
1. **Queries Tailscale**: Gets current network status via `tailscale status --json`
2. **Security validation**: Validates JSON structure and sanitizes inputs
3. **Fuzzy matching**: Uses Levenshtein distance algorithm for partial matches
4. **Smart DNS**: Uses MagicDNS names when available, falls back to IPs
5. **SSH fallback**: Tries regular SSH if host isn't in Tailscale network

### 🛡️ Security Features
- **Input validation**: Prevents command injection through hostname validation
- **JSON security**: Validates Tailscale JSON structure before processing
- **Pattern sanitization**: Prevents regex injection in search patterns
- **Safe argument handling**: Uses `--` parameter separation to prevent option injection
- **Secure jq queries**: Uses `--arg` parameter binding instead of string interpolation

### ⚡ Performance & Efficiency
- **One-time checks**: Command availability checked once at load time
- **Conditional loading**: Only loads functionality for installed tools
- **Shared code**: Single hostname resolution function eliminates duplication
- **Smart caching**: Reuses Tailscale status data across operations

### 🎮 Tab Completion Intelligence
- **Levenshtein sorting**: Results sorted by similarity to your input
- **Version awareness**: Detects tool versions and offers appropriate options
- **Context sensitivity**: Different completions for different command contexts
- **Shell compatibility**: Works seamlessly in both Bash and Zsh

## Uninstallation

```bash
# Remove user installation
./setup.sh --uninstall

# Remove system-wide installation
sudo ./setup.sh --uninstall

# Or manually remove from your shell RC file
# Remove the tailscale-cli-helpers source lines from ~/.bashrc or ~/.zshrc
```

## 🔍 Troubleshooting

### Functions not available after installation
```bash
# Reload shell configuration
source ~/.bashrc        # For Bash
source ~/.zshrc         # For Zsh

# OR start a new shell session
exec $SHELL

# Verify installation
type tssh               # Should show function definition
type ts                 # Should show function definition
```

### Tab completion not working
```bash
# Install completion systems
sudo dnf install bash-completion        # Fedora/RHEL
sudo apt install bash-completion        # Ubuntu/Debian
brew install bash-completion            # macOS

# For Zsh users, ensure completion system is enabled
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
source ~/.zshrc

# Test completion
ts <TAB><TAB>           # Should show available commands/hosts
```

### Commands missing (tscp, tsftp, trsync, tmussh)
```bash
# These commands are conditionally loaded - install missing tools:
sudo dnf install openssh-clients rsync          # Fedora/RHEL (scp, sftp, rsync)
sudo apt install openssh-client rsync           # Ubuntu/Debian (scp, sftp, rsync)
brew install rsync                              # macOS (rsync)

# For tmussh (parallel SSH)
sudo dnf install mussh                          # If available in repos
# OR build from source: https://github.com/DigitalCyberSoft/mussh

# Reload to detect new tools
source ~/.bashrc
```

### Tailscale connection issues
```bash
# Verify Tailscale is running
tailscale status

# Check network connectivity
ping 100.100.100.100    # Tailscale DNS server

# Debug hostname resolution
tssh -v hostname        # Shows detailed resolution process
```

### Version/compatibility issues
```bash
# Check versions
bash --version          # Needs 4.0+
zsh --version           # Any recent version
jq --version            # Any version
tailscale version       # Any version

# Run comprehensive tests
./tests/test-both-shells.sh             # Test both shells
./tests/test-comprehensive-commands.sh   # Test all commands
./tests/test-security-hardening.sh      # Test security features
```

### Installation issues
```bash
# Remove and reinstall
./setup.sh --uninstall     # Remove current installation
./setup.sh                 # Clean reinstall

# Check installation paths
ls -la ~/.config/tailscale-cli-helpers/          # User installation
ls -la /usr/share/tailscale-cli-helpers/         # System installation
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.