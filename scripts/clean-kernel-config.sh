#!/usr/bin/env bash
# Remove comments from kernel config file that don't end with "is not set"
# Usage: ./clean-kernel-config.sh <input-file> [output-file]

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input-file> [output-file]"
    echo "  If output-file is not specified, overwrites input-file"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-$INPUT_FILE}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist"
    exit 1
fi

# Create temp file
TEMP_FILE=$(mktemp)
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

echo "Cleaned config written to: $OUTPUT_FILE"
