#!/bin/bash
set -euo pipefail

# Apply kernel config fragment using scripts/kconfig/merge_config.sh
# Uses the official kconfig merge tool from the Linux kernel

usage() {
    echo "Usage: $0 -c <config_file> -f <fragment_file> [-v]"
    echo ""
    echo "Options:"
    echo "  -c <config_file>    Path to kernel config file to modify"
    echo "  -f <fragment_file>  Path to config fragment file"
    echo "  -v                  Verbose output"
    echo ""
    echo "Example:"
    echo "  $0 -c vendor/pkgs/kernel/build/config-arm64 -f patches/rpi5-config.fragment"
    exit 1
}

CONFIG_FILE=""
FRAGMENT_FILE=""
VERBOSE=false

while getopts "c:f:vh" opt; do
    case ${opt} in
        c) CONFIG_FILE="${OPTARG}" ;;
        f) FRAGMENT_FILE="${OPTARG}" ;;
        v) VERBOSE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "${CONFIG_FILE}" ]] || [[ -z "${FRAGMENT_FILE}" ]]; then
    echo "Error: Config file and fragment file are required"
    usage
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Error: Config file not found: ${CONFIG_FILE}"
    exit 1
fi

if [[ ! -f "${FRAGMENT_FILE}" ]]; then
    echo "Error: Fragment file not found: ${FRAGMENT_FILE}"
    exit 1
fi

${VERBOSE} && echo "Merging kernel config using yq..."
${VERBOSE} && echo "  Base config: ${CONFIG_FILE}"
${VERBOSE} && echo "  Fragment: ${FRAGMENT_FILE}"

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Step 1: Convert both files to props format (CONFIG_X=value or CONFIG_X=n for disabled)
convert_to_props() {
    local input="$1"
    local output="$2"
    
    # Extract CONFIG_X=value lines directly
    grep -E '^CONFIG_[A-Z0-9_]+=.*' "${input}" > "${output}" || true
    
    # Convert "# CONFIG_X is not set" to "CONFIG_X=n" for yq processing
    grep -E '^# CONFIG_[A-Z0-9_]+ is not set' "${input}" | \
        sed 's/^# CONFIG_\([A-Z0-9_]*\) is not set/CONFIG_\1=n/' >> "${output}" || true
}

# Step 2: Extract header comments from original file
grep -E '^#' "${CONFIG_FILE}" | grep -v 'is not set' > "${TEMP_DIR}/header.txt" || true

# Step 3: Convert files to props
${VERBOSE} && echo "Converting to props format..."
convert_to_props "${CONFIG_FILE}" "${TEMP_DIR}/base.props"
convert_to_props "${FRAGMENT_FILE}" "${TEMP_DIR}/fragment.props"

# Step 4: Merge using yq - fragment overrides base
${VERBOSE} && echo "Merging with yq..."
yq eval-all '. as $item ireduce ({}; . * $item)' \
    -p props -o props \
    "${TEMP_DIR}/base.props" "${TEMP_DIR}/fragment.props" | \
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

# Step 7: Replace original file
mv "${TEMP_DIR}/final.config" "${CONFIG_FILE}"

echo "✓ Config merged using yq"
