#!/usr/bin/env bash

set -euo pipefail

# Script to build Talos images using imager profiles
# Generates profile YAML from command-line arguments

# Defaults
ARCH="arm64"
PLATFORM="nocloud"
VERSION="v1.12.1"
IMAGER_IMAGE="ghcr.io/siderolabs/imager"
SECUREBOOT="false"
OUTPUT_DIR="_out"
DISK_FORMAT="raw"
DISK_SIZE="1306902528"
COMPRESSION="xz"
OVERLAY_NAME=""
OVERLAY_IMAGE=""
KERNEL_PATH=""
INITRAMFS_PATH=""
BASE_INSTALLER=""
declare -a SYSTEM_EXTENSIONS=()

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Build Talos images using the imager profile system.

OPTIONS:
  -a, --arch ARCH              Architecture (default: arm64)
  -p, --platform PLATFORM      Platform (default: nocloud)
  -v, --version VERSION        Talos version (default: v1.12.1)
  -i, --imager IMAGE           Imager image (default: ghcr.io/siderolabs/imager)
  -s, --secureboot             Enable SecureBoot
  -o, --output DIR             Output directory (default: _out)
  
  --disk-format FORMAT         Disk format: raw, qcow2, vhd, ova, etc (default: raw)
  --disk-size SIZE             Disk size in bytes (default: 1306902528)
  --compression TYPE           Compression: xz, gzip, zstd (default: xz)
  
  --overlay-name NAME          Overlay name
  --overlay-image REF          Overlay image reference or tarball path
  
  --kernel PATH                Kernel file path
  --initramfs PATH             Initramfs file path
  --base-installer REF         Base installer image/tarball (default: auto)
  
  -e, --extension REF          System extension (image ref or tarball)
                               Can be specified multiple times
  
  -h, --help                   Show this help

EXAMPLES:
  # Basic build
  $0 -a arm64 -p nocloud
  
  # With overlay
  $0 --overlay-name rpi_generic --overlay-image factory.talos.dev/...
  
  # With extensions (image refs)
  $0 -e ghcr.io/siderolabs/sbc-raspberrypi:v0.1.0-alpha.1-34-g2df11b7 \\
     -e ghcr.io/siderolabs/gasket-driver:20240916-v1.12.0-6-gff105b7
  
  # With extensions (tarballs)
  $0 -e tarball:./extensions/rpi.tar -e tarball:./extensions/gasket.tar
  
  # SecureBoot
  $0 --secureboot --base-installer ghcr.io/siderolabs/installer:v1.12.1

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--arch) ARCH="$2"; shift 2 ;;
    -p|--platform) PLATFORM="$2"; shift 2 ;;
    -v|--version) VERSION="$2"; shift 2 ;;
    -i|--imager) IMAGER_IMAGE="$2"; shift 2 ;;
    -s|--secureboot) SECUREBOOT="true"; shift ;;
    -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
    --disk-format) DISK_FORMAT="$2"; shift 2 ;;
    --disk-size) DISK_SIZE="$2"; shift 2 ;;
    --compression) COMPRESSION="$2"; shift 2 ;;
    --overlay-name) OVERLAY_NAME="$2"; shift 2 ;;
    --overlay-image) OVERLAY_IMAGE="$2"; shift 2 ;;
    --kernel) KERNEL_PATH="$2"; shift 2 ;;
    --initramfs) INITRAMFS_PATH="$2"; shift 2 ;;
    --base-installer) BASE_INSTALLER="$2"; shift 2 ;;
    -e|--extension) SYSTEM_EXTENSIONS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Build profile YAML
PROFILE_YAML="arch: ${ARCH}
platform: ${PLATFORM}
secureboot: ${SECUREBOOT}
version: ${VERSION}"

# Add input section if needed
if [[ -n "${KERNEL_PATH}" || -n "${INITRAMFS_PATH}" || -n "${BASE_INSTALLER}" || ${#SYSTEM_EXTENSIONS[@]} -gt 0 ]]; then
  PROFILE_YAML="${PROFILE_YAML}
input:"
  
  # Kernel
  if [[ -n "${KERNEL_PATH}" ]]; then
    PROFILE_YAML="${PROFILE_YAML}
  kernel:
    path: ${KERNEL_PATH}"
  fi
  
  # Initramfs
  if [[ -n "${INITRAMFS_PATH}" ]]; then
    PROFILE_YAML="${PROFILE_YAML}
  initramfs:
    path: ${INITRAMFS_PATH}"
  fi
  
  # Base installer
  if [[ -n "${BASE_INSTALLER}" ]]; then
    PROFILE_YAML="${PROFILE_YAML}
  baseInstaller:"
    # Check if it's a tarball or image ref
    if [[ "${BASE_INSTALLER}" == tarball:* ]]; then
      PROFILE_YAML="${PROFILE_YAML}
    tarballPath: ${BASE_INSTALLER#tarball:}"
    elif [[ "${BASE_INSTALLER}" == oci:* ]]; then
      PROFILE_YAML="${PROFILE_YAML}
    ociPath: ${BASE_INSTALLER#oci:}"
    else
      PROFILE_YAML="${PROFILE_YAML}
    imageRef: ${BASE_INSTALLER}"
    fi
  fi
  
  # System extensions
  if [[ ${#SYSTEM_EXTENSIONS[@]} -gt 0 ]]; then
    PROFILE_YAML="${PROFILE_YAML}
  systemExtensions:"
    for ext in "${SYSTEM_EXTENSIONS[@]}"; do
      if [[ "${ext}" == tarball:* ]]; then
        PROFILE_YAML="${PROFILE_YAML}
    - tarballPath: ${ext#tarball:}"
      elif [[ "${ext}" == oci:* ]]; then
        PROFILE_YAML="${PROFILE_YAML}
    - ociPath: ${ext#oci:}"
      else
        PROFILE_YAML="${PROFILE_YAML}
    - imageRef: ${ext}"
      fi
    done
  fi
fi

# Add overlay if specified
if [[ -n "${OVERLAY_NAME}" && -n "${OVERLAY_IMAGE}" ]]; then
  PROFILE_YAML="${PROFILE_YAML}
overlay:
  name: ${OVERLAY_NAME}
  image:"
  # Check if overlay is tarball, OCI, or image ref
  if [[ "${OVERLAY_IMAGE}" == tarball:* ]]; then
    PROFILE_YAML="${PROFILE_YAML}
    tarballPath: ${OVERLAY_IMAGE#tarball:}"
  elif [[ "${OVERLAY_IMAGE}" == oci:* ]]; then
    PROFILE_YAML="${PROFILE_YAML}
    ociPath: ${OVERLAY_IMAGE#oci:}"
  else
    PROFILE_YAML="${PROFILE_YAML}
    imageRef: ${OVERLAY_IMAGE}"
  fi
fi

PROFILE_YAML="${PROFILE_YAML}
output:
  kind: image
  imageOptions:
    diskFormat: ${DISK_FORMAT}
    diskSize: ${DISK_SIZE}
  outFormat: .${COMPRESSION}
"

echo "Profile:"
echo "${PROFILE_YAML}"

# Run imager with profile
echo "${PROFILE_YAML}" | docker run --rm -i \
            -v "${PWD}/${OUTPUT_DIR}:/out" \
            -v /dev:/dev \
            --privileged \
            "${IMAGER_IMAGE}:${VERSION}" -

echo ""
echo "Build complete! Output in: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"
