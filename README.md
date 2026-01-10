# talos-images

Raw Talos Images in OCI format, published to GitHub Container Registry.

An extensible build framework for creating Talos Linux raw images with custom configurations, overlays, and system extensions.

## Published OCI Images

Pre-built custom Talos images are automatically published to `ghcr.io` following this naming pattern:

```
ghcr.io/${owner}/talos/${ARCH}/${PLATFORM}:${VERSION}.${COMPRESSION}
```

### Available Images

Images are published for different profiles with varying architectures and platforms:

| Profile | Architecture | Platform | Image Path |
|---------|-------------|----------|------------|
| rpi-generic | arm64 | nocloud | `ghcr.io/tinkerbell-community/talos/arm64/nocloud:v1.12.1.xz` |
| generic-arm64 | arm64 | nocloud | `ghcr.io/tinkerbell-community/talos/arm64/nocloud:v1.12.1.xz` |
| generic-amd64 | amd64 | nocloud | `ghcr.io/tinkerbell-community/talos/amd64/nocloud:v1.12.1.xz` |

### Pulling Images with ORAS

To pull a Talos image:

```bash
# Pull a specific version for arm64/nocloud
oras pull ghcr.io/tinkerbell-community/talos/arm64/nocloud:v1.12.1.xz

# Pull a specific version for amd64/nocloud
oras pull ghcr.io/tinkerbell-community/talos/amd64/nocloud:v1.12.1.xz

# Pull the latest version for a platform
oras pull ghcr.io/tinkerbell-community/talos/arm64/nocloud:latest
```

### Using the Images

The pulled file will be a compressed raw disk image (`.raw.xz` format) that can be:
- Written directly to a disk using `dd` or similar tools
- Used with virtualization platforms
- Decompressed and used in bare metal deployments

Example:
```bash
# Pull the image
oras pull ghcr.io/tinkerbell-community/talos/amd64/nocloud:v1.12.1.xz

# Decompress and write to disk
xz -d nocloud-amd64.raw.xz
dd if=nocloud-amd64.raw of=/dev/sdX bs=4M status=progress
```

## Features

- **Profile-based Configuration**: Define build configurations in simple YAML files
- **Extensible**: Easy to add new profiles for different hardware platforms
- **Flexible**: Support for overlays, system extensions, and custom configurations
- **Simple**: Clean CLI interface with Make targets for common builds
- **Automated Publishing**: GitHub Actions automatically build and publish OCI images

## Building Images Locally

### Prerequisites

- Docker installed and running
- Bash shell
- Make (optional, for convenience targets)

### Building an Image

Using Make (recommended):
```bash
# Build Raspberry Pi image
make rpi-generic

# Build generic ARM64 image
make generic-arm64

# Build with custom profile
make build PROFILE=your-profile
```

Using the build script directly:
```bash
# Build with a specific profile
./build.sh --profile rpi-generic

# Show help
./build.sh --help
```

### Available Profiles

List all available build profiles:
```bash
make list-profiles
```

Current profiles:
- **rpi-generic**: Raspberry Pi with generic overlay
- **generic-arm64**: Generic ARM64 platform without overlays
- **generic-amd64**: Generic AMD64/x86_64 platform without overlays

## Creating Custom Profiles

Profiles are stored in the `profiles/` directory as YAML files. Each profile defines:

- Imager version and image
- Architecture and platform
- Security settings (secure boot)
- Overlays (for hardware-specific customizations)
- System extensions
- Output configuration (disk format, size, compression)

### Example Profile

Create a new file `profiles/my-device.yaml`:

```yaml
# My Custom Device Profile
# Description of what this profile builds

# Imager configuration
imager:
  version: "v1.12.1"
  image: "ghcr.io/siderolabs/imager"

# Architecture and platform
arch: "arm64"
platform: "nocloud"

# Security settings
secureboot: false

# Overlay configuration (optional)
overlay:
  name: "my_overlay"
  image: "ghcr.io/my-org/my-overlay:v1.0.0"

# System extensions to include in the image
system_extensions:
  - "ghcr.io/siderolabs/iscsi-tools:v0.2.0"
  - "ghcr.io/siderolabs/util-linux-tools:2.41.2"

# Output configuration
output:
  kind: "image"
  disk_format: "raw"
  disk_size: 1306902528  # ~1.25GB in bytes
  compression: "xz"
```

Then build it:
```bash
./build.sh --profile my-device
# or
make build PROFILE=my-device
```

## Configuration Options

### Imager Settings
- `imager.version`: Version of the Talos imager to use
- `imager.image`: Container image for the imager

### Build Settings
- `arch`: Target architecture (e.g., `arm64`, `amd64`)
- `platform`: Target platform (e.g., `nocloud`, `aws`, `gcp`)
- `secureboot`: Enable/disable secure boot (`true`/`false`)

### Overlay (Optional)
- `overlay.name`: Name of the overlay
- `overlay.image`: Container image containing the overlay

### System Extensions
- `system_extensions`: List of system extension images to include

### Output Settings
- `output.kind`: Output type (typically `image`)
- `output.disk_format`: Disk format (e.g., `raw`, `qcow2`)
- `output.disk_size`: Disk size in bytes
- `output.compression`: Compression format (e.g., `xz`, `gz`)

## Output

Built images are saved to the `_out/` directory with the following naming:
- Format: `<platform>-<arch>-<version>.<format>.<compression>`
- Example: `nocloud-arm64-v1.12.1.raw.xz`

## Cleaning Up

Remove all build artifacts:
```bash
make clean
```

## Advanced Usage

### Custom Imager Versions

To use a different version of the Talos imager, update the profile:

```yaml
imager:
  version: "v1.13.0"
```

### Multiple System Extensions

Add as many system extensions as needed:

```yaml
system_extensions:
  - "ghcr.io/siderolabs/iscsi-tools:v0.2.0"
  - "ghcr.io/siderolabs/util-linux-tools:2.41.2"
  - "ghcr.io/siderolabs/intel-ucode:20231114"
  - "ghcr.io/siderolabs/tailscale:1.56.1"
```

### Different Architectures

Profiles support different architectures:

```yaml
arch: "amd64"  # For x86_64 systems
```

## Troubleshooting

### Docker Permission Issues

If you get permission errors, ensure your user is in the docker group:
```bash
sudo usermod -aG docker $USER
```

Then log out and back in.

### Build Fails

1. Check Docker is running: `docker ps`
2. Verify the profile exists: `make list-profiles`
3. Check Docker can pull images: `docker pull ghcr.io/siderolabs/imager:v1.12.1`

## Contributing

To add a new profile:

1. Create a new YAML file in `profiles/`
2. Follow the structure of existing profiles
3. Test the build: `./build.sh --profile your-profile`
4. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines and examples.

## License

See [LICENSE](LICENSE) file for details.

## Automation

The repository includes automated GitHub Actions workflows for building and publishing Talos images.

### Custom Profile Builds

**Workflow**: `Build and Push Custom Profiles`

Automatically builds custom Talos images using the profile-based framework:
- **Automatic builds** - Runs when profiles or build scripts are updated
- **Weekly schedule** - Rebuilds all profiles weekly with latest configurations
- **Manual trigger** - Build specific profiles on demand

Images are published following this naming pattern:
```
ghcr.io/${owner}/talos/${ARCH}/${PLATFORM}:${VERSION}.${COMPRESSION}
```

**Manual Trigger**:
1. Go to the "Actions" tab in GitHub
2. Select "Build and Push Custom Profiles" workflow
3. Click "Run workflow"
4. Optionally specify a profile (leave empty to build all profiles)

### Official Talos Image Publishing

**Workflow**: `Build and Push Talos Images`

Automatically builds and publishes official Talos OS images from GitHub releases:
- **Check for new releases** - Runs every 6 hours to detect new Talos versions
- **Create PRs** - Automatically creates PRs when new versions are found
- **Build and push** - Downloads and publishes official images when versions are updated

**Manual Trigger**:
1. Go to the "Actions" tab in GitHub
2. Select "Build and Push Talos Images" workflow
3. Click "Run workflow"
4. Enter the Talos version (e.g., `v1.8.3`)

## Image Formats

### Custom Profile Images

Custom images built from profiles are published with:
- **Artifact Type**: `application/vnd.acme.rocket.config`
- **Naming Pattern**: `ghcr.io/${owner}/talos/${ARCH}/${PLATFORM}:${VERSION}.${COMPRESSION}`
- **Format**: Compressed raw disk images (`.raw.xz` or `.raw.gz`)

### Official Talos Images

Official Talos images are published with:
- **Artifact Type**: `application/vnd.talos.image.raw.xz`
- **Naming Pattern**: `ghcr.io/${owner}/talos-images/talos-${ARCH}:${VERSION}`
- **Format**: XZ-compressed raw disk images

## Contributing

To add a new profile:
1. Create a new YAML file in `profiles/`
2. Follow the structure of existing profiles
3. Test the build: `./build.sh --profile your-profile`
4. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines and examples.

To add or update official Talos versions, modify the `talos-versions.json` file and create a pull request.
