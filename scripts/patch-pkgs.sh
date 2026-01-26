#!/usr/bin/env bash
# Combined utility script for managing vendor/pkgs kernel configurations
# Combines functionality from clean-kernel-config.sh, update-rpi-kernel.sh, and merge-config-yq.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

usage() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
    clean-config <input-file> [output-file]
        Remove comments from kernel config file that don't end with "is not set"
        If output-file is not specified, overwrites input-file

    update-kernel <kernel-ref>
        Update Raspberry Pi kernel version in vendor/pkgs
        Example refs: stable_20250428, rpi-6.18.y

    merge-config -c <config-file> -y <config-yaml> [-v]
        Merge kernel configs from YAML into kernel .config file

Examples:
    $0 clean-config vendor/pkgs/kernel/build/config-arm64
    $0 update-kernel stable_20250428
    $0 merge-config -c vendor/pkgs/kernel/build/config-arm64 -y config.yaml

EOF
    exit 1
}

# ============================================================================
# CLEAN CONFIG COMMAND
# ============================================================================
cmd_clean_config() {
    if [ $# -lt 1 ]; then
        error "clean-config requires at least 1 argument"
        echo "Usage: $0 clean-config <input-file> [output-file]"
        exit 1
    fi

    local INPUT_FILE="$1"
    local OUTPUT_FILE="${2:-$INPUT_FILE}"

    if [ ! -f "$INPUT_FILE" ]; then
        error "Input file '$INPUT_FILE' does not exist"
        exit 1
    fi

    # Create temp file
    local TEMP_FILE=$(mktemp)
    trap "rm -f $TEMP_FILE" EXIT

    # Process the file:
    # - Keep all non-comment lines (lines not starting with #)
    # - Keep comment lines ending with "is not set"
    # - Remove all other comment lines
    awk '
        # Non-comment line - keep it
        !/^#/ { print; next }
        
        # Comment line ending with "is not set" - keep it
        /is not set$/ { print; next }
        
        # All other comment lines - skip them
    ' "$INPUT_FILE" > "$TEMP_FILE"

    # Move temp file to output
    mv "$TEMP_FILE" "$OUTPUT_FILE"

    info "Cleaned config written to: $OUTPUT_FILE"
}

# ============================================================================
# UPDATE KERNEL COMMAND
# ============================================================================
cmd_update_kernel() {
    if [[ "$#" -ne 1 ]]; then
        error "update-kernel requires exactly 1 argument"
        echo "Usage: $0 update-kernel <kernel-ref>"
        echo "Example: $0 update-kernel stable_20250428"
        exit 1
    fi

    local KERNEL_REF="$1"
    local REPO_URL="https://github.com/raspberrypi/linux"
    local PKGFILE="${PROJECT_DIR}/vendor/pkgs/Pkgfile"
    local PKG_YAML="${PROJECT_DIR}/vendor/pkgs/kernel/prepare/pkg.yaml"

    echo "Updating Raspberry Pi kernel to: ${KERNEL_REF}"
    echo ""

    echo "Getting commit hash..."
    # Try as a branch first, then as a tag
    local COMMIT_SHA=$(curl -fsSL "https://api.github.com/repos/raspberrypi/linux/git/refs/heads/${KERNEL_REF}" 2>/dev/null | \
        grep '"sha"' | head -1 | sed -E 's/.*"sha": "([^"]*)".*/\1/')

    if [[ -z "${COMMIT_SHA}" ]]; then
        # Try as a tag
        COMMIT_SHA=$(curl -fsSL "https://api.github.com/repos/raspberrypi/linux/git/refs/tags/${KERNEL_REF}" 2>/dev/null | \
            grep '"sha"' | head -1 | sed -E 's/.*"sha": "([^"]*)".*/\1/')
    fi

    if [[ -z "${COMMIT_SHA}" ]]; then
        error "Could not retrieve commit hash for ref ${KERNEL_REF}"
        exit 1
    fi

    # Use commit SHA for stable tarball URL
    local TARBALL_URL="${REPO_URL}/archive/${COMMIT_SHA}.tar.gz"

    if [[ ! -f "${PKGFILE}" ]]; then
        error "Pkgfile not found at ${PKGFILE}"
        exit 1
    fi

    if [[ ! -f "${PKG_YAML}" ]]; then
        error "pkg.yaml not found at ${PKG_YAML}"
        exit 1
    fi

    # Download tarball to temporary location
    local TEMP_DIR=$(mktemp -d)
    local TARBALL="${TEMP_DIR}/linux.tar.gz"

    trap 'rm -rf "$TEMP_DIR"' EXIT

    echo "Downloading kernel tarball..."
    if ! curl -fsSL "${TARBALL_URL}" -o "${TARBALL}"; then
        error "Failed to download ${TARBALL_URL}"
        echo "Please verify the ref exists: ${REPO_URL}/branches or ${REPO_URL}/tags"
        exit 1
    fi

    echo "Calculating checksums..."
    local SHA256=$(shasum -a 256 "${TARBALL}" | awk '{print $1}')
    local SHA512=$(shasum -a 512 "${TARBALL}" | awk '{print $1}')

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
    info "Successfully updated kernel to ${KERNEL_REF}"
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
}

# ============================================================================
# MERGE CONFIG COMMAND
# ============================================================================
cmd_merge_config() {
    local CONFIG_FILE=""
    local CONFIG_YAML=""
    local VERBOSE=false

    while getopts "c:y:vh" opt; do
        case ${opt} in
            c) CONFIG_FILE="${OPTARG}" ;;
            y) CONFIG_YAML="${OPTARG}" ;;
            v) VERBOSE=true ;;
            h) 
                echo "Usage: $0 merge-config -c <config_file> -y <config_yaml> [-v]"
                echo ""
                echo "Options:"
                echo "  -c <config_file>    Path to kernel config file to modify"
                echo "  -y <config_yaml>    Path to config.yaml file"
                echo "  -v                  Verbose output"
                exit 0
                ;;
            *) 
                error "Invalid option for merge-config"
                exit 1
                ;;
        esac
    done

    if [[ -z "${CONFIG_FILE}" ]] || [[ -z "${CONFIG_YAML}" ]]; then
        error "Config file and config.yaml are required"
        echo "Usage: $0 merge-config -c <config_file> -y <config_yaml> [-v]"
        exit 1
    fi

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi

    if [[ ! -f "${CONFIG_YAML}" ]]; then
        error "config.yaml not found: ${CONFIG_YAML}"
        exit 1
    fi

    ${VERBOSE} && echo "Merging kernel config using yq..."
    ${VERBOSE} && echo "  Base config: ${CONFIG_FILE}"
    ${VERBOSE} && echo "  Config YAML: ${CONFIG_YAML}"

    # Create temp directory
    local TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    # Step 1: Extract header comments from original file
    grep -E '^#' "${CONFIG_FILE}" | grep -v 'is not set' > "${TEMP_DIR}/header.txt" || true

    # Step 2: Convert base config file to props format (CONFIG_X=value or CONFIG_X=n for disabled)
    ${VERBOSE} && echo "Converting base config to props format..."
    grep -E '^CONFIG_[A-Z0-9_]+=.*' "${CONFIG_FILE}" > "${TEMP_DIR}/base.props" || true
    grep -E '^# CONFIG_[A-Z0-9_]+ is not set' "${CONFIG_FILE}" | \
        sed 's/^# CONFIG_\([A-Z0-9_]*\) is not set/CONFIG_\1=n/' >> "${TEMP_DIR}/base.props" || true

    # Step 3: Extract configs from config.yaml and convert to props format
    ${VERBOSE} && echo "Extracting configs from config.yaml..."
    yq eval '.configs | to_entries | .[] | .key + "=" + .value' "${CONFIG_YAML}" > "${TEMP_DIR}/yaml.props"

    # Step 4: Merge using yq - yaml configs override base
    ${VERBOSE} && echo "Merging with yq..."
    yq eval-all '. as $item ireduce ({}; . * $item)' \
        -p props -o props \
        "${TEMP_DIR}/base.props" "${TEMP_DIR}/yaml.props" | \
        sed 's/ *= */=/g' | \
        sort > "${TEMP_DIR}/merged.props"

    # Step 5: Convert back to kernel config format
    ${VERBOSE} && echo "Converting back to kernel config format..."
    {
        # Preserve header
        [[ -s "${TEMP_DIR}/header.txt" ]] && cat "${TEMP_DIR}/header.txt" && echo ""
        
        # Convert props back to kernel format
        while IFS='=' read -r key value; do
            [[ -z "${key}" ]] && continue
            if [[ "${value}" == "n" ]]; then
                echo "# ${key} is not set"
            else
                echo "${key}=${value}"
            fi
        done < "${TEMP_DIR}/merged.props"
    } > "${TEMP_DIR}/final.config"

    # Step 6: Replace original file
    mv "${TEMP_DIR}/final.config" "${CONFIG_FILE}"

    info "Config merged using yq"
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================
if [ $# -lt 1 ]; then
    usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
    clean-config)
        cmd_clean_config "$@"
        ;;
    update-kernel)
        cmd_update_kernel "$@"
        ;;
    merge-config)
        cmd_merge_config "$@"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        error "Unknown command: $COMMAND"
        usage
        ;;
esac
