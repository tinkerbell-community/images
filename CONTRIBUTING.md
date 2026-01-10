# Contributing to Talos Images

We welcome contributions to the Talos Images build framework! This document provides guidelines for contributing new profiles and improvements.

## Adding New Build Profiles

The easiest way to contribute is by adding new build profiles for different hardware platforms or use cases.

### Profile Structure

Each profile is a YAML file in the `profiles/` directory with the following structure:

```yaml
# Profile Name/Description
# Brief description of what this profile builds

# Imager configuration
imager:
  version: "v1.12.1"              # Talos imager version
  image: "ghcr.io/siderolabs/imager"  # Imager container image

# Architecture and platform
arch: "arm64"                      # Target architecture (arm64, amd64, etc.)
platform: "nocloud"                # Target platform (nocloud, aws, gcp, etc.)

# Security settings
secureboot: false                  # Enable/disable secure boot

# Overlay configuration (optional - omit if not needed)
overlay:
  name: "my_overlay"              # Overlay name
  image: "ghcr.io/org/overlay:tag"  # Overlay container image

# System extensions to include in the image
system_extensions:
  - "ghcr.io/siderolabs/ext1:tag"
  - "ghcr.io/siderolabs/ext2:tag"

# Output configuration
output:
  kind: "image"                   # Output kind (typically "image")
  disk_format: "raw"              # Disk format (raw, qcow2, etc.)
  disk_size: 1306902528          # Disk size in bytes
  compression: "xz"               # Compression format (xz, gz, etc.)
```

### Steps to Add a Profile

1. **Create the profile file**: `profiles/my-device.yaml`
2. **Test the profile**: `./build.sh --profile my-device --dry-run`
3. **Add a Makefile target** (optional but recommended):
   ```makefile
   my-device:
   	./build.sh --profile my-device
   ```
4. **Update README.md**: Add your profile to the list of available profiles
5. **Submit a pull request**: Include a description of the hardware/use case

### Profile Examples

#### Raspberry Pi with Custom Extensions

```yaml
imager:
  version: "v1.12.1"
  image: "ghcr.io/siderolabs/imager"

arch: "arm64"
platform: "nocloud"
secureboot: false

overlay:
  name: "rpi_generic"
  image: "ghcr.io/tinkerbell-community/sbc-raspberrypi:9fc24c1"

system_extensions:
  - "ghcr.io/siderolabs/iscsi-tools:v0.2.0"
  - "ghcr.io/siderolabs/util-linux-tools:2.41.2"
  - "ghcr.io/siderolabs/tailscale:1.56.1"

output:
  kind: "image"
  disk_format: "raw"
  disk_size: 1306902528
  compression: "xz"
```

#### Cloud Platform (AWS)

```yaml
imager:
  version: "v1.12.1"
  image: "ghcr.io/siderolabs/imager"

arch: "amd64"
platform: "aws"
secureboot: false

system_extensions:
  - "ghcr.io/siderolabs/iscsi-tools:v0.2.0"

output:
  kind: "image"
  disk_format: "raw"
  disk_size: 2147483648
  compression: "gz"
```

## Testing Your Changes

Before submitting a pull request:

1. **Validate YAML syntax**: Ensure your profile is valid YAML
2. **Test in dry-run mode**: `./build.sh --profile your-profile --dry-run`
3. **Review the generated configuration**: Check that it matches your expectations
4. **Test a real build** (if possible): `./build.sh --profile your-profile`

## Code Contributions

If you're contributing code changes to the build script or framework:

1. **Maintain backward compatibility**: Don't break existing profiles
2. **Test all existing profiles**: Ensure they still work with your changes
3. **Update documentation**: Reflect any new features or changes in README.md
4. **Follow the existing code style**: Match the style of the existing code

## Reporting Issues

If you encounter problems:

1. Check the [README.md](README.md) for troubleshooting tips
2. Search existing issues on GitHub
3. Create a new issue with:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Your profile configuration (if relevant)

## Questions?

Feel free to open an issue for questions or discussions about:
- New profile ideas
- Feature requests
- Framework improvements
- Documentation clarifications

Thank you for contributing to Talos Images!
