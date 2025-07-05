# Development Guide

## Version Updates

To release a new version:

1. Update version in `tailscale-cli-helpers.spec` and `debian/changelog`
2. Commit changes and create git tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
3. Build packages (see below)
4. Create GitHub release with packages attached

## Package Building

### RPM Package
```bash
# Download source
wget https://github.com/DigitalCyberSoft/tailscale-cli-helpers/archive/refs/tags/vX.Y.Z.tar.gz -O ~/rpmbuild/SOURCES/vX.Y.Z.tar.gz

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

- `tailscale-ssh-helper.sh` - Main loader script
- `tailscale-functions.sh` - Core ts command logic
- `tailscale-completion.sh` - Tab completion system
- `setup.sh` - Universal installer
- `tailscale-cli-helpers.spec` - RPM packaging
- `debian/` - DEB packaging metadata
- `tests/` - Test scripts (not packaged)