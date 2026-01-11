#!/usr/bin/env bash

set -euo pipefail

# Script to apply kernel config changes from config.yaml
# Usage: apply-config-changes.sh <config-file>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <config-file>"
    echo "Example: $0 vendor/talos/kernel/build/config-arm64"
    exit 1
fi

CONFIG_FILE="$1"
YAML_FILE="$PROJECT_DIR/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Kernel config file not found: $CONFIG_FILE"
    exit 1
fi

if [ ! -f "$YAML_FILE" ]; then
    echo "Error: YAML config file not found: $YAML_FILE"
    exit 1
fi

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed. Please install yq to parse YAML files."
    echo "Install with: brew install yq"
    exit 1
fi

echo "Applying config changes from: $YAML_FILE"
echo "To config file: $CONFIG_FILE"

# Create temporary file for processing
TEMP_FILE=$(mktemp)
cp "$CONFIG_FILE" "$TEMP_FILE"

# Extract config changes from YAML file
declare -A removed_configs
declare -A added_configs
declare -A disabled_configs

# Process configs to remove (these have specific values in the original)
while IFS= read -r config_line; do
    if [[ -z "$config_line" || "$config_line" == "null" ]]; then
        continue
    fi
    
    # Extract config name
    if [[ "$config_line" =~ ^(CONFIG_[A-Z0-9_]+)= ]]; then
        config_name="${BASH_REMATCH[1]}"
        removed_configs["$config_name"]="$config_line"
    fi
done < <(yq eval '.configs.remove[]' "$YAML_FILE")

# Process configs to add (these will be set to specific values)
while IFS= read -r config_line; do
    if [[ -z "$config_line" || "$config_line" == "null" ]]; then
        continue
    fi
    
    # Extract config name
    if [[ "$config_line" =~ ^(CONFIG_[A-Z0-9_]+)= ]]; then
        config_name="${BASH_REMATCH[1]}"
        added_configs["$config_name"]="$config_line"
    fi
done < <(yq eval '.configs.add[]' "$YAML_FILE")

# Process configs to disable (these will be set to "# CONFIG_NAME is not set")
while IFS= read -r config_name; do
    if [[ -z "$config_name" || "$config_name" == "null" ]]; then
        continue
    fi
    
    disabled_configs["$config_name"]="# $config_name is not set"
done < <(yq eval '.configs.disable[]' "$YAML_FILE")

# Apply changes to the config file
change_count=0

# First, apply all additions (enable configs with specific values)
for config_name in "${!added_configs[@]}"; do
    added_line="${added_configs[$config_name]}"
    
    echo "Enabling: $config_name"
    echo "  Setting to: $added_line"
    
    # Remove any existing form of this config (both "is not set" comment and old value)
    sed -i.bak "/^# ${config_name} is not set\$/d; /^${config_name}=/d" "$TEMP_FILE"
    rm -f "${TEMP_FILE}.bak"
    
    # Append the new config
    echo "$added_line" >> "$TEMP_FILE"
    ((change_count++))
done

# Second, apply all disables (configs that should be "# CONFIG_NAME is not set")
for config_name in "${!disabled_configs[@]}"; do
    disabled_line="${disabled_configs[$config_name]}"
    
    echo "Disabling: $config_name"
    echo "  Setting to: $disabled_line"
    
    # Remove any existing form of this config (both old value and old comment)
    sed -i.bak "/^# ${config_name} is not set\$/d; /^${config_name}=/d" "$TEMP_FILE"
    rm -f "${TEMP_FILE}.bak"
    
    # Append the disabled comment
    echo "$disabled_line" >> "$TEMP_FILE"
    ((change_count++))
done

# Third, handle removals (configs that should be completely removed)
for config_name in "${!removed_configs[@]}"; do
    # Skip if this config is being handled by add or disable
    if [ -n "${added_configs[$config_name]:-}" ] || [ -n "${disabled_configs[$config_name]:-}" ]; then
        continue
    fi
    
    removed_line="${removed_configs[$config_name]}"
    
    echo "Removing: $config_name"
    echo "  Was: $removed_line"
    
    # Remove the config line
    removed_escaped=$(printf '%s\n' "$removed_line" | sed 's/[[\.*^$/]/\\&/g')
    sed -i.bak "/^${removed_escaped}\$/d" "$TEMP_FILE"
    rm -f "${TEMP_FILE}.bak"
    ((change_count++))
done

# Replace original file with modified version
mv "$TEMP_FILE" "$CONFIG_FILE"

echo ""
echo "Applied $change_count config changes to $CONFIG_FILE"
