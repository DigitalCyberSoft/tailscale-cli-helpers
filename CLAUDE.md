# Development Guide

**IMPORTANT: Never mention Claude in commit messages, release notes, or any user-facing documentation.**

## Version Updates

To release a new version:

1. Update version in multiple locations:
   - `VERSION` (main version file)
   - `lib/common.sh` (TAILSCALE_CLI_HELPERS_VERSION)
   - `tailscale-cli-helpers.spec` (Version field)
   - `tailscale-cli-helpers-tmussh.spec` (Version field)
   - `debian/changelog` 
   - `debian-tmussh/changelog`
2. Update Homebrew formula SHA256 hash (if needed)
3. Commit changes and create git tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
4. Build packages (see below)
5. Create GitHub release with packages attached

## Package Building

### RPM Package
```bash
# Create RPM build directories
mkdir -p ~/rpmbuild/{SOURCES,SPECS,BUILD,RPMS,SRPMS}

# Create source tarball (from project directory)
tar czf ~/rpmbuild/SOURCES/vX.Y.Z.tar.gz --transform 's,^,tailscale-cli-helpers-X.Y.Z/,' \
    bin/ lib/ man/ \
    *.spec *.sh *.md LICENSE VERSION tailscale-completion.sh

# Alternative: Download from GitHub (for released versions)
# wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/refs/tags/vX.Y.Z.tar.gz -O ~/rpmbuild/SOURCES/vX.Y.Z.tar.gz

# Copy spec files
cp tailscale-cli-helpers.spec ~/rpmbuild/SPECS/
cp tailscale-cli-helpers-tmussh.spec ~/rpmbuild/SPECS/

# IMPORTANT: Verify changelog dates match correct day of week before building
# Build main package
rpmbuild -ba ~/rpmbuild/SPECS/tailscale-cli-helpers.spec

# Build tmussh package (optional)
rpmbuild -ba ~/rpmbuild/SPECS/tailscale-cli-helpers-tmussh.spec

# Copy to packages directory
mkdir -p packages
cp ~/rpmbuild/RPMS/noarch/tailscale-cli-helpers-X.Y.Z-1.noarch.rpm packages/
cp ~/rpmbuild/SRPMS/tailscale-cli-helpers-X.Y.Z-1.src.rpm packages/
cp ~/rpmbuild/RPMS/noarch/tailscale-cli-helpers-tmussh-X.Y.Z-1.noarch.rpm packages/
cp ~/rpmbuild/SRPMS/tailscale-cli-helpers-tmussh-X.Y.Z-1.src.rpm packages/
```

### DEB Package
```bash
# Convert from RPM using alien (--scripts preserves post-install scripts)
fakeroot alien --scripts --to-deb ~/rpmbuild/RPMS/noarch/tailscale-cli-helpers-X.Y.Z-1.noarch.rpm
fakeroot alien --scripts --to-deb ~/rpmbuild/RPMS/noarch/tailscale-cli-helpers-tmussh-X.Y.Z-1.noarch.rpm

# Copy to packages directory
mv tailscale-cli-helpers_X.Y.Z-2_all.deb packages/
mv tailscale-cli-helpers-tmussh_X.Y.Z-2_all.deb packages/
```

### Homebrew Formula
When releasing new versions, update the SHA256 hash:
```bash
# Get new hash
curl -L https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/refs/tags/vX.Y.Z.tar.gz | sha256sum

# Update tailscale-cli-helpers.rb with new URL and hash
```

## Testing

Run tests after changes:
```bash
./tests/test-both-shells.sh
./tests/test-summary.sh
```

## Git Commands

```bash
# Standard workflow
git add -A
git commit -m "Description"
git push origin main

# Release workflow  
git tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z --title "Title" --notes "Notes" package.rpm package.deb
```

## File Structure

- `bin/` - Executable scripts (ts, tssh, tscp, tsftp, trsync, tssh_copy_id, tmussh)
- `lib/` - Shared libraries (common.sh, tailscale-resolver.sh)
- `man/man1/` - Man pages for all commands
- `tailscale-completion.sh` - Tab completion system
- `setup.sh` - Universal installer
- `tailscale-cli-helpers.spec` - Main RPM packaging
- `tailscale-cli-helpers-tmussh.spec` - tmussh RPM packaging
- `tailscale-cli-helpers.rb` - Homebrew formula
- `debian/` - Main DEB packaging metadata
- `debian-tmussh/` - tmussh DEB packaging metadata
- `tests/` - Test scripts (not packaged)

## Installation Methods

1. **Universal**: `./setup.sh` (works on all platforms, installs binaries to /usr/local/bin)
2. **RPM**: For Fedora/RHEL/CentOS systems (`tailscale-cli-helpers` + optional `tailscale-cli-helpers-tmussh`)
3. **DEB**: For Ubuntu/Debian systems (`tailscale-cli-helpers` + optional `tailscale-cli-helpers-tmussh`)
4. **Homebrew**: For macOS users (`brew install https://raw.githubusercontent.com/...`)

## Release Guidelines

- Only update versions for functional changes
- Don't version bump for documentation or installation method additions
- Always test on both bash and zsh before releasing
- Include all package types in GitHub releases
