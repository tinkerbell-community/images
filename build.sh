#!/usr/bin/env bash

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="${SCRIPT_DIR}/profiles"
OUTPUT_DIR="${SCRIPT_DIR}/_out"

# Default values
PROFILE=""
SHOW_HELP=false
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print usage information
print_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Build Talos raw images using profile-based configuration.

OPTIONS:
  -p, --profile PROFILE    Name of the build profile (required)
  -d, --dry-run           Show configuration without building
  -h, --help              Show this help message

EXAMPLES:
  $0 -p rpi-generic
  $0 --profile generic-arm64
  $0 --profile rpi-generic --dry-run

AVAILABLE PROFILES:
$(list_profiles)

EOF
}

# List available profiles
list_profiles() {
  if [[ -d "${PROFILES_DIR}" ]]; then
    for profile in "${PROFILES_DIR}"/*.yaml; do
      if [[ -f "${profile}" ]]; then
        basename "${profile}" .yaml | sed 's/^/  - /'
      fi
    done
  fi
}

# Parse YAML value (simple parser for our use case)
parse_yaml_value() {
  local file="$1"
  local key="$2"
  local default="${3:-}"
  local value=""
  
  # Handle nested keys (e.g., "imager.version")
  if [[ "${key}" == *.* ]]; then
    local parent="${key%%.*}"
    local child="${key#*.}"
    # Increased context lines to handle larger sections
    value=$(grep -A 30 "^${parent}:" "${file}" | grep "${child}:" | head -1)
  else
    value=$(grep "^${key}:" "${file}" | head -1)
  fi
  
  # Extract the value, handling both quoted and unquoted
  if [[ -z "${value}" ]]; then
    echo "${default}"
    return
  fi
  
  # Try to extract quoted value first
  if echo "${value}" | grep -q '"'; then
    echo "${value}" | sed 's/.*: *"\([^"]*\)".*/\1/'
  else
    # Unquoted value - remove comments and trailing whitespace
    echo "${value}" | sed 's/.*: *\([^# ]*\).*/\1/'
  fi
}

# Parse YAML array (simple parser for our use case)
parse_yaml_array() {
  local file="$1"
  local key="$2"
  
  # Use sed to extract array items with flexible indentation
  sed -n "/^${key}:/,/^[^ ]/p" "${file}" | grep "^[[:space:]]*- " | sed 's/^[[:space:]]*- "\?\([^"]*\)"\?/\1/'
}

# Check if overlay section exists in YAML
has_overlay() {
  local file="$1"
  # Optimize by storing overlay section once and checking both fields
  local overlay_section
  overlay_section=$(grep -A 5 "^overlay:" "${file}" 2>/dev/null)
  [[ -n "${overlay_section}" ]] && echo "${overlay_section}" | grep -q "name:" && echo "${overlay_section}" | grep -q "image:"
}

# Build extensions YAML
build_extensions_yaml() {
  local -a extensions=("$@")
  for ext in "${extensions[@]}"; do
    echo "    - imageRef: ${ext}"
  done
}

# Build the image
build_image() {
  local profile_file="$1"
  
  echo -e "${GREEN}Building image with profile: $(basename "${profile_file}" .yaml)${NC}"
  
  # Parse configuration from profile
  local imager_version=$(parse_yaml_value "${profile_file}" "imager.version" "v1.12.1")
  local imager_image=$(parse_yaml_value "${profile_file}" "imager.image" "ghcr.io/siderolabs/imager")
  local arch=$(parse_yaml_value "${profile_file}" "arch" "arm64")
  local platform=$(parse_yaml_value "${profile_file}" "platform" "nocloud")
  local secureboot=$(parse_yaml_value "${profile_file}" "secureboot" "false")
  local disk_format=$(parse_yaml_value "${profile_file}" "output.disk_format" "raw")
  local disk_size=$(parse_yaml_value "${profile_file}" "output.disk_size" "1306902528")
  local compression=$(parse_yaml_value "${profile_file}" "output.compression" "xz")
  
  # Parse overlay if present
  local overlay_name=""
  local overlay_image=""
  if has_overlay "${profile_file}"; then
    overlay_name=$(parse_yaml_value "${profile_file}" "overlay.name")
    overlay_image=$(parse_yaml_value "${profile_file}" "overlay.image")
  fi
  
  # Parse system extensions
  local -a system_extensions
  mapfile -t system_extensions < <(parse_yaml_array "${profile_file}" "system_extensions")
  
  # Create output directory
  mkdir -p "${OUTPUT_DIR}"
  
  echo -e "${YELLOW}Configuration:${NC}"
  echo "  Imager: ${imager_image}:${imager_version}"
  echo "  Architecture: ${arch}"
  echo "  Platform: ${platform}"
  echo "  Secureboot: ${secureboot}"
  if [[ -n "${overlay_name}" ]]; then
    echo "  Overlay: ${overlay_name} (${overlay_image})"
  fi
  echo "  System Extensions: ${#system_extensions[@]}"
  for ext in "${system_extensions[@]}"; do
    echo "    - ${ext}"
  done
  echo "  Output Format: ${disk_format} (${compression} compressed)"
  echo "  Disk Size: ${disk_size} bytes"
  echo ""
  
  # Build the imager configuration
  local imager_config="arch: ${arch}
platform: ${platform}
secureboot: ${secureboot}
version: ${imager_version}"
  
  # Add overlay if present
  if [[ -n "${overlay_name}" ]]; then
    imager_config="${imager_config}
overlay:
  name: ${overlay_name}
  image:
    imageRef: ${overlay_image}"
  fi
  
  # Add system extensions
  if [[ ${#system_extensions[@]} -gt 0 ]]; then
    imager_config="${imager_config}
input:
  systemExtensions:
$(build_extensions_yaml "${system_extensions[@]}")"
  fi
  
  # Add output configuration
  imager_config="${imager_config}
output:
  kind: image
  imageOptions:
    diskFormat: ${disk_format}
    diskSize: ${disk_size}
  outFormat: .${compression}"
  
  echo -e "${YELLOW}Running imager...${NC}"
  echo ""
  
  # Show the configuration that will be used
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}Imager Configuration (dry-run mode):${NC}"
    echo "${imager_config}"
    echo ""
    echo -e "${GREEN}Dry-run complete. No image was built.${NC}"
    return 0
  fi
  
  # Run the imager
  echo "${imager_config}" | docker run --rm -i \
    -v "${OUTPUT_DIR}:/out" \
    -v /dev:/dev \
    --privileged \
    "${imager_image}:${imager_version}" - --output /out
  
  echo ""
  echo -e "${GREEN}Build complete! Output saved to: ${OUTPUT_DIR}${NC}"
  ls -lh "${OUTPUT_DIR}"
}

# Main script
main() {
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -p|--profile)
        PROFILE="$2"
        shift 2
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        SHOW_HELP=true
        shift
        ;;
      *)
        echo -e "${RED}Error: Unknown option: $1${NC}" >&2
        print_usage
        exit 1
        ;;
    esac
  done
  
  # Show help if requested
  if [[ "${SHOW_HELP}" == "true" ]]; then
    print_usage
    exit 0
  fi
  
  # Validate profile
  if [[ -z "${PROFILE}" ]]; then
    echo -e "${RED}Error: Profile is required${NC}" >&2
    echo ""
    print_usage
    exit 1
  fi
  
  # Check if profile file exists
  local profile_file="${PROFILES_DIR}/${PROFILE}.yaml"
  if [[ ! -f "${profile_file}" ]]; then
    echo -e "${RED}Error: Profile not found: ${PROFILE}${NC}" >&2
    echo ""
    echo "Available profiles:"
    list_profiles
    exit 1
  fi
  
  # Build the image
  build_image "${profile_file}"
}

# Run main function
main "$@"
