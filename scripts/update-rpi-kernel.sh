#!/usr/bin/env bash

set -euo pipefail

# Script to update Raspberry Pi kernel version in vendor/pkgs
# Downloads the kernel tarball, calculates checksums, and updates Pkgfile and pkg.yaml
#
# Usage: update-rpi-kernel.sh <kernel-tag-or-branch>
# Example: update-rpi-kernel.sh stable_20250428
# Example: update-rpi-kernel.sh rpi-6.18.y

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

PKGFILE="${PROJECT_DIR}/vendor/pkgs/Pkgfile"
PKG_YAML="${PROJECT_DIR}/vendor/pkgs/kernel/prepare/pkg.yaml"

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 <kernel-tag-or-branch>"
    echo "Example: $0 stable_20250428"
    echo "Example: $0 rpi-6.18.y"
    exit 1
fi

KERNEL_REF="$1"
REPO_URL="https://github.com/raspberrypi/linux"

echo "Updating Raspberry Pi kernel to: ${KERNEL_REF}"
echo ""

echo "Getting commit hash..."
# Try as a branch first, then as a tag
COMMIT_SHA=$(curl -fsSL "https://api.github.com/repos/raspberrypi/linux/git/refs/heads/${KERNEL_REF}" 2>/dev/null | \
    grep '"sha"' | head -1 | sed -E 's/.*"sha": "([^"]*)".*/\1/')

if [[ -z "${COMMIT_SHA}" ]]; then
    # Try as a tag
    COMMIT_SHA=$(curl -fsSL "https://api.github.com/repos/raspberrypi/linux/git/refs/tags/${KERNEL_REF}" 2>/dev/null | \
        grep '"sha"' | head -1 | sed -E 's/.*"sha": "([^"]*)".*/\1/')
fi

if [[ -z "${COMMIT_SHA}" ]]; then
    echo "Error: Could not retrieve commit hash for ref ${KERNEL_REF}"
    exit 1
fi

# Use commit SHA for stable tarball URL
TARBALL_URL="${REPO_URL}/archive/${COMMIT_SHA}.tar.gz"

if [[ ! -f "${PKGFILE}" ]]; then
    echo "Error: Pkgfile not found at ${PKGFILE}"
    exit 1
fi

if [[ ! -f "${PKG_YAML}" ]]; then
    echo "Error: pkg.yaml not found at ${PKG_YAML}"
    exit 1
fi

# Download tarball to temporary location
TEMP_DIR=$(mktemp -d)
TARBALL="${TEMP_DIR}/linux.tar.gz"

trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Downloading kernel tarball..."
if ! curl -fsSL "${TARBALL_URL}" -o "${TARBALL}"; then
    echo "Error: Failed to download ${TARBALL_URL}"
    echo "Please verify the ref exists: ${REPO_URL}/branches or ${REPO_URL}/tags"
    exit 1
fi

echo "Calculating checksums..."
SHA256=$(shasum -a 256 "${TARBALL}" | awk '{print $1}')
SHA512=$(shasum -a 512 "${TARBALL}" | awk '{print $1}')

echo ""
echo "Kernel Ref:    ${KERNEL_REF}"
echo "Commit SHA:    ${COMMIT_SHA}"
echo "SHA256:        ${SHA256}"
echo "SHA512:        ${SHA512}"
echo ""

# Update Pkgfile
echo "Updating ${PKGFILE}..."

# Create backup
cp "${PKGFILE}" "${PKGFILE}.bak"

# Update linux_ref
sed -i.tmp "s/linux_version: .*/linux_ref: ${COMMIT_SHA}/" "${PKGFILE}"

# Update linux_sha256
sed -i.tmp "s/linux_sha256: .*/linux_sha256: ${SHA256}/" "${PKGFILE}"

# Update linux_sha512
sed -i.tmp "s/linux_sha512: .*/linux_sha512: ${SHA512}/" "${PKGFILE}"

rm -f "${PKGFILE}.tmp"

# Update kernel/prepare/pkg.yaml
echo "Updating ${PKG_YAML}..."

# Create backup
cp "${PKG_YAML}" "${PKG_YAML}.bak"

# Check if it's already using the GitHub URL
if grep -q "cdn.kernel.org" "${PKG_YAML}"; then
    # Replace kernel.org URL with GitHub URL
    sed -i.tmp 's|url: https://cdn.kernel.org/pub/linux/kernel/v{{ regexReplaceAll.*|url: "https://github.com/raspberrypi/linux/archive/{{ .linux_ref }}.tar.gz"|' "${PKG_YAML}"
    
    # Update destination filename
    sed -i.tmp 's/destination: linux.tar.xz/destination: linux.tar.gz/' "${PKG_YAML}"
    
    # Update tar extraction command from xz to gzip
    sed -i.tmp 's/tar -xJf linux.tar.xz/tar -xzf linux.tar.gz/' "${PKG_YAML}"
    
    rm -f "${PKG_YAML}.tmp"
    
    echo "  → Converted from kernel.org to GitHub URL"
else
    echo "  → Already using GitHub URL (no changes needed)"
fi

echo ""
echo "✓ Successfully updated kernel to ${KERNEL_REF}"
echo ""
echo "Changes made:"
echo "  - Updated linux_ref to: ${COMMIT_SHA}"
echo "  - Updated checksums"
echo "  - Configured to use GitHub tarball"
echo ""
echo "Backup files created:"
echo "  - ${PKGFILE}.bak"
echo "  - ${PKG_YAML}.bak"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff vendor/pkgs/"
echo "  2. Test build: make vendor-all"
echo "  3. Commit changes if successful"
