# Tailscale CLI Helpers

Bash and Zsh wrappers around `ssh`, `scp`, `sftp`, `rsync`, and friends that resolve
Tailscale hostnames for you. Type a partial name and the helpers look it up in
`tailscale status`, fall back to MagicDNS or the node's IP, and hand off to the real
tool. Tab completion and fuzzy matching are included, and plain SSH still works for
hosts that aren't on your tailnet.

## Quick Start

```bash
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/v0.3.6.tar.gz
tar -xzf v0.3.6.tar.gz && cd tailscale-cli-helpers-0.3.6
./setup.sh
```

Then:

```bash
tssh myhost                     # SSH to a Tailscale host
tscp file.txt myhost:/path/     # Copy files (scp)
tsftp myhost                    # Interactive SFTP session
trsync -av dir/ myhost:/        # Sync directories (rsync)
tsping myhost                   # Ping a host
tssh_copy_id myhost             # Install your SSH key
tsexit                          # Pick an exit node from a menu
tmussh -h "web-*" -c "uptime"   # Run a command on many hosts (needs mussh)
```

## Commands

| Command | What it does |
|---------|--------------|
| `tssh` / `ts` | SSH to a host by name; `ts` also dispatches the subcommands below |
| `tscp` | File copy over scp |
| `tsftp` | Interactive SFTP session |
| `trsync` | Directory sync over rsync |
| `tsping` / `ts ping` | Ping a host (resolves the name, pings the IP) |
| `tssh_copy_id` | Install SSH keys via ssh-copy-id, including through a ProxyJump |
| `tsexit` / `ts exit` | Interactive exit node menu with Mullvad country grouping |
| `tmussh` | Parallel SSH across multiple hosts (requires mussh) |

All of them accept the underlying tool's flags (`-p`, `-i`, `-r`, `-o ...`, and so on)
and pass them straight through. `tscp`, `tsftp`, `trsync`, and `tmussh` only load when
the tool they wrap is actually installed.

Hostname resolution uses a Levenshtein-distance match, so partial names work and
completion results are ordered by similarity. Mullvad exit nodes are excluded from the
SSH/copy/sync completions so they don't clutter the list.

## Requirements

Required:

- Bash 4.0+ or Zsh
- `tailscale`, installed and running
- `jq`
- `ssh`

Optional (each enables the matching command when present): `scp`, `sftp`, `rsync`, `mussh`.

## Installation

### From a release tarball

```bash
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/v0.3.6.tar.gz
tar -xzf v0.3.6.tar.gz
cd tailscale-cli-helpers-0.3.6

./setup.sh                # current user
sudo ./setup.sh --system  # system-wide

./tests/test-both-shells.sh   # optional: verify
```

### Packages

RPM (Fedora/RHEL/CentOS):

```bash
sudo rpm -i tailscale-cli-helpers-0.3.6-1.noarch.rpm
sudo rpm -i tailscale-cli-helpers-mussh-0.3.6-1.noarch.rpm   # optional, for tmussh
```

DEB (Ubuntu/Debian):

```bash
sudo dpkg -i tailscale-cli-helpers_0.3.6-2_all.deb
sudo dpkg -i tailscale-cli-helpers-mussh_0.3.6-2_all.deb     # optional, for tmussh
```

Homebrew (macOS):

```bash
brew install https://raw.githubusercontent.com/DigitalCyberSoft/tailscale-cli-helpers/main/tailscale-cli-helpers.rb
```

### From a clone

```bash
git clone https://github.com/digitalcybersoft/tailscale-cli-helpers.git
cd tailscale-cli-helpers

./setup.sh          # current user; asks whether to install the ts dispatcher
sudo ./setup.sh     # system-wide; includes the ts dispatcher
```

`setup.sh` auto-detects privileges. Use `--user` or `--system` to force one.

System-wide install locations:

- Scripts: `/usr/share/tailscale-cli-helpers/`
- Shell loader: `/etc/profile.d/tailscale-cli-helpers.sh`
- Bash completion: `/etc/bash_completion.d/tailscale-cli-helpers`

User install locations:

- Scripts: `~/.config/tailscale-cli-helpers/`
- Shell loader: appended to `~/.bashrc` or `~/.zshrc`

### Updating

```bash
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/v0.3.6.tar.gz
tar -xzf v0.3.6.tar.gz
cd tailscale-cli-helpers-0.3.6
./setup.sh

# or, for packages
sudo rpm -U tailscale-cli-helpers-0.3.6-1.noarch.rpm
sudo dpkg -i tailscale-cli-helpers_0.3.6-2_all.deb
```

### macOS notes

```bash
brew install jq tailscale
```

Then install from a tarball as above. On macOS everything goes to the user locations
and the loader is added to `~/.zshrc` or `~/.bash_profile`.

## Usage

### SSH

```bash
tssh hostname                   # connects as root@hostname
tssh user@hostname
tssh hostname -p 2222           # custom port
tssh hostname -i ~/.ssh/key     # custom key
tssh -v hostname                # verbose resolution output

ts hostname                     # same as tssh hostname
ts ssh hostname                 # explicit
ts ssh hostname -o StrictHostKeyChecking=no
```

### The ts dispatcher

`ts` on its own prints the available subcommands. Otherwise:

```bash
ts hostname                     # SSH (default)
ts ssh hostname
ts scp file.txt host:/path
ts rsync -av dir/ host:/path/
ts ping host
ts mussh -h host1 host2 -c "uptime"
```

### tscp

```bash
tscp localfile.txt hostname:/remote/path/
tscp hostname:/remote/file.txt ./
tscp -r local_dir/ hostname:/remote/path/
tscp -P 2222 file.txt hostname:/path/
```

### trsync

```bash
trsync -av local_dir/ hostname:/remote/path/
trsync -av hostname:/remote/path/ local_dir/
trsync -avz --delete source/ hostname:/dest/
trsync -av --exclude='*.log' dir/ hostname:/dir/
trsync -av --dry-run source/ hostname:/dest/
trsync -v source/ hostname:/dest/           # shows the resolved host/IP
```

### tmussh

Needs `mussh`. Runs a command across several hosts in parallel:

```bash
tmussh -h host1 host2 host3 -c "uptime"
tmussh -h "web-*" -c "systemctl status nginx"   # wildcards resolve to tailnet hosts
tmussh -m 5 -h "prod-*" -c "df -h"              # limit concurrency
tmussh -h admin@web1 root@web2 -c "whoami"      # per-host users
tmussh -H hostlist.txt -c "hostname"
```

### tssh_copy_id

```bash
tssh_copy_id hostname                        # as root
tssh_copy_id user@hostname
tssh_copy_id -J jumphost user@destination    # resolves both hosts
tssh_copy_id -i ~/.ssh/custom_key.pub hostname
ts ssh_copy_id hostname
```

### tsftp

```bash
tsftp hostname                   # connect as root
tsftp user@hostname
tsftp -P 2222 hostname
tsftp -i ~/.ssh/custom_key hostname
ts sftp hostname
```

### tsexit

Interactive menu for choosing an exit node. Mullvad nodes are detected and grouped by
country; your own tailnet devices show up in a separate section, and the current exit
node is marked. Works fine without a Mullvad subscription (you just see your own
devices).

```bash
tsexit            # arrow-key menu
tsexit --list     # non-interactive listing
ts exit
```

### tsping

```bash
tsping myhost
ts ping myhost
ts ping -c 4 myhost      # ping flags pass through
tsping -4 myhost
ts ping example.com      # non-tailnet names fall back to a normal ping
```

### Tab completion

```bash
tssh host<TAB>       # matching hosts
tssh ro<TAB>         # completes to root@
tssh admin@<TAB>     # hosts for the admin user
tssh @prod<TAB>      # hosts containing "prod"
```

## How it works

When you run `ts hostname`, the helpers query `tailscale status --json`, validate the
JSON, and match your input against the node list with a Levenshtein-distance sort. They
prefer MagicDNS names and fall back to the node's IP. If nothing matches, they hand the
name to plain `ssh` so non-tailnet hosts still work.

Hostnames are validated before use and jq queries bind values with `--arg` rather than
string interpolation, so a hostile hostname can't inject a command or a regex. Argument
lists use `--` separation to keep flags from being reinterpreted as options.

Tool availability is checked once at load time, resolution logic is shared across the
commands rather than duplicated, and status output is reused within an operation.

## Uninstall

```bash
./setup.sh --uninstall        # user install
sudo ./setup.sh --uninstall   # system-wide
```

You can also delete the source lines from `~/.bashrc` or `~/.zshrc` by hand.

## Troubleshooting

Functions not found after install: reload your shell (`source ~/.bashrc`,
`source ~/.zshrc`, or `exec $SHELL`) and check with `type tssh` / `type ts`.

Completion not working:

```bash
sudo dnf install bash-completion    # Fedora/RHEL
sudo apt install bash-completion    # Ubuntu/Debian
brew install bash-completion        # macOS

# Zsh
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc && source ~/.zshrc
```

A command is missing (`tscp`, `tsftp`, `trsync`, `tmussh`): the underlying tool isn't
installed. Install it, then reload your shell.

```bash
sudo dnf install openssh-clients rsync    # Fedora/RHEL
sudo apt install openssh-client rsync     # Ubuntu/Debian
brew install rsync                        # macOS
# tmussh needs mussh: https://github.com/DigitalCyberSoft/mussh
```

Tailscale problems:

```bash
tailscale status
ping 100.100.100.100     # Tailscale DNS
tssh -v hostname         # show resolution steps
```

Version checks:

```bash
bash --version           # need 4.0+
jq --version
tailscale version
./tests/test-both-shells.sh
```

## Contributing

Pull requests and issues are welcome.

## License

MIT. See [LICENSE](LICENSE).
