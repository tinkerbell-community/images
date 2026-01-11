# Talos Raspberry Pi 5 Patches

## Overview

This repository contains patches for Raspberry Pi 5 support in Talos Linux. Patches are organized by Talos major version to ensure compatibility.

## Patch Structure

```
patches/
└── siderolabs/
    ├── pkgs/
    │   ├── v1.11/
    │   │   └── 0001-Patched-for-Raspberry-Pi-5.patch
    │   └── v1.12/
    │       └── 0001-Patched-for-Raspberry-Pi-5.patch
    └── talos/
        ├── v1.11/
        │   └── 0001-Patched-for-Raspberry-Pi-5.patch
        └── v1.12/
            └── 0001-Add-Raspberry-Pi-5-modules.patch
```

## Version-Specific Patches

### Talos v1.11.x

**PKG Patches (`pkgs/v1.11/0001-Patched-for-Raspberry-Pi-5.patch`)**:

- Switches to Raspberry Pi Linux kernel (stable_20250428)
- Updates kernel configuration for BCM2712 (Raspberry Pi 5)
- Enables 16K pages (required for Raspberry Pi 5)
- Adds RPi5-specific drivers and hardware support
- Comprehensive kernel config changes

**Talos Patches (`talos/v1.11/0001-Patched-for-Raspberry-Pi-5.patch`)**:

- Complete rewrite of `hack/modules-arm64.txt`
- Adds RPi5-specific kernel modules
- Includes GPU drivers (vc4, v3d, panfrost)
- Adds bcm2835_smi support

### Talos v1.12.x

**PKG Patches (`pkgs/v1.12/0001-Patched-for-Raspberry-Pi-5.patch`)**:

- Same as v1.11 (kernel patches are compatible)

**Talos Patches (`talos/v1.12/0001-Patched-for-Raspberry-Pi-5.patch`)**:

- Comprehensive module changes matching v1.11 approach
- Compatible with v1.12.1 base module list
- **Adds**:
  - RPi5 GPU drivers (vc4, v3d, panfrost)
  - BCM2835 SMI driver
  - USB network drivers (all USB-Ethernet adapters)
  - USB webcam/UVC drivers for camera support
  - ALSA/sound drivers for audio
  - Filesystem support (btrfs, nfsd)
  - Crypto modules (blake2b, xxhash, zstd)
  - Chelsio network drivers
  - Media/video subsystem support
  - Thunderbolt drivers
- **Removes**:
  - Unnecessary HID drivers (specific keyboard/mouse brands)
  - Intel server NICs (e1000, ixgbe, etc.)
  - ATA/PATA drivers
  - Server-specific MMC/SD card readers
  - x86-specific hardware modules
  - Server performance monitoring tools

## Key Differences

### v1.11 vs v1.12

Both v1.11 and v1.12 patches now follow the same comprehensive approach:

- **v1.11**: Complete rewrite of modules list for v1.11.5
- **v1.12**: Same comprehensive changes adapted for v1.12.1 module list

Both patches remove unnecessary server/x86 hardware and add Raspberry Pi specific functionality (GPU, USB, media, sound). The v1.12 patch accounts for differences in the upstream v1.12 module list (e.g., additional VDPA support, new driver subsystems).

## Applying Patches

Patches are automatically applied by the Makefile based on the `TALOS_VERSION` variable:

```bash
make patches
```

The Makefile automatically selects the correct patch directory based on the Talos major version (e.g., v1.12.1 → v1.12 patches).

## Updating for New Versions

When adding support for a new Talos version:

1. Create new directories:

   ```bash
   mkdir -p patches/siderolabs/pkgs/v1.XX
   mkdir -p patches/siderolabs/talos/v1.XX
   ```

2. Test if existing patches apply:

   ```bash
   cd vendor/talos
   git checkout v1.XX.Y
   patch -p1 --dry-run < ../../patches/siderolabs/talos/v1.12/0001-Add-Raspberry-Pi-5-modules.patch
   ```

3. If patches fail, create new version-specific patches

4. Update `TALOS_VERSION` in Makefile

## Notes

- PKG patches (kernel configuration) are generally stable across minor versions
- Talos patches (module lists) may need adjustment between major versions
- Always test patches before committing to ensure they apply cleanly
