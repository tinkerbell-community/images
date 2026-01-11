#!/usr/bin/env bash
set -uo pipefail

# Apply Raspberry Pi 5 module changes to Talos modules-arm64.txt
# This script reads the config.yaml file to extract module additions and removals,
# then applies those changes to the modules-arm64.txt file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

CONFIG_FILE="$PROJECT_DIR/config.yaml"
MODULES_FILE="$PROJECT_DIR/vendor/talos/hack/modules-arm64.txt"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

if [[ ! -f "$MODULES_FILE" ]]; then
    echo "Error: Modules file not found: $MODULES_FILE" >&2
    exit 1
fi

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed. Please install yq to parse YAML files." >&2
    echo "Install with: brew install yq" >&2
    exit 1
fi

# Parse config file to extract modules to add and remove
echo "Parsing config file: $CONFIG_FILE"

ADDITIONS=$(mktemp)
REMOVALS=$(mktemp)

trap 'rm -f "$ADDITIONS" "$REMOVALS"' EXIT

# Extract modules to remove using yq
yq eval '.modules.remove[]' "$CONFIG_FILE" > "$REMOVALS"

# Extract modules to add using yq
yq eval '.modules.add[]' "$CONFIG_FILE" > "$ADDITIONS"

ADDITIONS_COUNT=$(wc -l < "$ADDITIONS" | tr -d ' ')
REMOVALS_COUNT=$(wc -l < "$REMOVALS" | tr -d ' ')

echo "Found $REMOVALS_COUNT modules to remove"
echo "Found $ADDITIONS_COUNT modules to add"

# Create temp file for modified modules list
TEMP_MODULES=$(mktemp)
trap 'rm -f "$ADDITIONS" "$REMOVALS" "$TEMP_MODULES"' EXIT

echo ""
echo "Applying changes to $MODULES_FILE..."

# Step 1: Remove modules that should be deleted
removed=0
while IFS= read -r module; do
    if grep -Fxq "$module" "$MODULES_FILE"; then
        echo "  Removing: $module"
        ((removed++)) || true
    fi
done < "$REMOVALS"

# Filter out removals
if [[ -s "$REMOVALS" ]]; then
    grep -Fxvf "$REMOVALS" "$MODULES_FILE" > "$TEMP_MODULES" || cp "$MODULES_FILE" "$TEMP_MODULES"
else
    cp "$MODULES_FILE" "$TEMP_MODULES"
fi

# Step 2: Find where to insert new modules (before modules.* footer)
# Read temp file into array to find insertion point
mapfile -t current_modules < "$TEMP_MODULES"

# Find first modules.* line from the end
footer_start=${#current_modules[@]}
for ((i=${#current_modules[@]}-1; i>=0; i--)); do
    if [[ "${current_modules[i]}" == modules.* ]]; then
        footer_start=$i
    elif [[ $footer_start -lt ${#current_modules[@]} ]]; then
        # Found non-modules.* line after modules.* lines, stop
        break
    fi
done

# Step 3: Add missing modules before footer
added=0
while IFS= read -r module; do
    if ! grep -Fxq "$module" "$TEMP_MODULES"; then
        # Insert at footer_start position
        current_modules=("${current_modules[@]:0:$footer_start}" "$module" "${current_modules[@]:$footer_start}")
        ((footer_start++))
        ((added++))
        echo "  Adding: $module"
    fi
done < <(sort "$ADDITIONS")

# Write final result
printf '%s\n' "${current_modules[@]}" > "$MODULES_FILE"

total=${#current_modules[@]}

echo ""
echo "✓ Complete!"
echo "  Removed: $removed modules"
echo "  Added: $added modules"
echo "  Total modules: $total"
