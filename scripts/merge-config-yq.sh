#!/bin/bash
set -euo pipefail

# Apply kernel config from config.yaml using yq
# Merges kernel configs directly from YAML into kernel .config file

usage() {
    echo "Usage: $0 -c <config_file> -y <config_yaml> [-v]"
    echo ""
    echo "Options:"
    echo "  -c <config_file>    Path to kernel config file to modify"
    echo "  -y <config_yaml>    Path to config.yaml file"
    echo "  -v                  Verbose output"
    echo ""
    echo "Example:"
    echo "  $0 -c vendor/pkgs/kernel/build/config-arm64 -y config.yaml"
    exit 1
}

CONFIG_FILE=""
CONFIG_YAML=""
VERBOSE=false

while getopts "c:y:vh" opt; do
    case ${opt} in
        c) CONFIG_FILE="${OPTARG}" ;;
        y) CONFIG_YAML="${OPTARG}" ;;
        v) VERBOSE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "${CONFIG_FILE}" ]] || [[ -z "${CONFIG_YAML}" ]]; then
    echo "Error: Config file and config.yaml are required"
    usage
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Error: Config file not found: ${CONFIG_FILE}"
    exit 1
fi

if [[ ! -f "${CONFIG_YAML}" ]]; then
    echo "Error: config.yaml not found: ${CONFIG_YAML}"
    exit 1
fi

${VERBOSE} && echo "Merging kernel config using yq..."
${VERBOSE} && echo "  Base config: ${CONFIG_FILE}"
${VERBOSE} && echo "  Config YAML: ${CONFIG_YAML}"

# Create temp directory
TEMP_DIR=$(mktemp -d)
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

# Step 7: Replace original file
mv "${TEMP_DIR}/final.config" "${CONFIG_FILE}"

echo "✓ Config merged using yq"
