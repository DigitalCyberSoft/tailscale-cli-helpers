# Development Guide

**IMPORTANT: Never mention Claude in commit messages, release notes, or any user-facing documentation. Always use "Built by Digital Cyber Soft" instead.**

## Version Updates

To release a new version:

1. Update version in `tailscale-cli-helpers.spec` and `debian/changelog`
2. Update Homebrew formula SHA256 hash (if needed)
3. Commit changes and create git tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
4. Build packages (see below)
5. Create GitHub release with packages attached

## Package Building

### RPM Package
```bash
# Download source
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/refs/tags/vX.Y.Z.tar.gz -O ~/rpmbuild/SOURCES/vX.Y.Z.tar.gz

# Update spec file to use correct version in %setup
# Build RPM
rpmbuild -ba tailscale-cli-helpers.spec

# Output: ~/rpmbuild/RPMS/noarch/tailscale-cli-helpers-X.Y.Z-1.fc42.noarch.rpm
```

### DEB Package
```bash
# Convert from RPM using alien
fakeroot alien --to-deb ~/rpmbuild/RPMS/noarch/tailscale-cli-helpers-X.Y.Z-1.fc42.noarch.rpm

# Output: tailscale-cli-helpers_X.Y.Z-2_all.deb
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
git commit -m "Description

Built by Digital Cyber Soft"
git push origin main

# Release workflow  
git tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z --title "Title" --notes "Notes

Built by Digital Cyber Soft" package.rpm package.deb
```

## File Structure

- `tailscale-ssh-helper.sh` - Main loader script
- `tailscale-functions.sh` - Core ts command logic
- `tailscale-completion.sh` - Tab completion system
- `setup.sh` - Universal installer
- `tailscale-cli-helpers.spec` - RPM packaging
- `tailscale-cli-helpers.rb` - Homebrew formula
- `debian/` - DEB packaging metadata
- `tests/` - Test scripts (not packaged)

## Installation Methods

1. **Universal**: `./setup.sh` (works on all platforms)
2. **RPM**: For Fedora/RHEL/CentOS systems
3. **DEB**: For Ubuntu/Debian systems  
4. **Homebrew**: For macOS users (`brew install https://raw.githubusercontent.com/...`)

## Release Guidelines

- Only update versions for functional changes
- Don't version bump for documentation or installation method additions
- Always test on both bash and zsh before releasing
- Include all package types in GitHub releases