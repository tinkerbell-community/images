# talos-images

Raw Talos Images in OCI format, published to GitHub Container Registry.

## Overview

This repository automatically builds and publishes Talos OS raw disk images as OCI artifacts using [ORAS](https://oras.land/). Images are available at `ghcr.io/tinkerbell-community/talos-images`.

## Available Images

Images are published for multiple Talos versions and architectures:
- **Architectures**: `amd64`, `arm64`
- **Versions**: See [talos-versions.json](talos-versions.json) for the list of tracked versions

## Usage

### Pulling Images with ORAS

To pull a Talos image:

```bash
# Pull a specific version for amd64
oras pull ghcr.io/tinkerbell-community/talos-images/talos-amd64:v1.8.3

# Pull a specific version for arm64
oras pull ghcr.io/tinkerbell-community/talos-images/talos-arm64:v1.8.3

# Pull the latest version
oras pull ghcr.io/tinkerbell-community/talos-images/talos-amd64:latest
```

### Using the Images

The pulled file will be a compressed raw disk image (`.raw.xz` format) that can be:
- Written directly to a disk using `dd` or similar tools
- Used with virtualization platforms
- Decompressed and used in bare metal deployments

Example:
```bash
# Pull the image
oras pull ghcr.io/tinkerbell-community/talos-images/talos-amd64:v1.8.3

# Decompress and write to disk
xz -d metal-amd64.raw.xz
dd if=metal-amd64.raw of=/dev/sdX bs=4M status=progress
```

## Automation

### Automatic Version Detection

The repository includes automated workflows that:
1. **Check for new releases** - Runs every 6 hours to detect new Talos versions
2. **Create PRs** - Automatically creates PRs when new versions are found
3. **Build and push** - Builds and publishes images when versions are updated

### Manual Trigger

You can manually trigger a build for a specific version:
1. Go to the "Actions" tab in GitHub
2. Select "Build and Push Talos Images" workflow
3. Click "Run workflow"
4. Enter the Talos version (e.g., `v1.8.3`)

## Image Format

Images are published with the following characteristics:
- **Artifact Type**: `application/vnd.talos.image.raw.xz`
- **Media Type**: `application/vnd.talos.image.layer.v1+xz`
- **Format**: XZ-compressed raw disk images

## Contributing

To add or update Talos versions, modify the `talos-versions.json` file and create a pull request.
