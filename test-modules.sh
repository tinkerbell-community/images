#!/usr/bin/env bash
# Test script to verify module changes

set -e

cd "$(dirname "$0")"

echo "=== Testing apply-module-changes.sh ==="
echo "1. Checking if yq is installed..."
if ! command -v yq &> /dev/null; then
    echo "   ❌ yq is NOT installed"
    echo "   Installing yq..."
    brew install yq
else
    echo "   ✓ yq is installed: $(which yq)"
    yq --version
fi

echo ""
echo "2. Running apply-module-changes.sh..."
bash -x scripts/apply-module-changes.sh

echo ""
echo "3. Verifying modules-arm64.txt..."
MODULES_FILE="vendor/talos/hack/modules-arm64.txt"
if [ -f "$MODULES_FILE" ]; then
    TOTAL_LINES=$(wc -l < "$MODULES_FILE" | tr -d ' ')
    echo "   ✓ File exists with $TOTAL_LINES lines"
    
    echo ""
    echo "4. Checking for problematic modules that should NOT be present..."
    PROBLEMATIC_MODULES=(
        "kernel/drivers/gpu/drm/drm_gpuvm.ko"
        "kernel/drivers/irqchip/irq-bcm2712-mip.ko"
        "kernel/drivers/mmc/host/sdhci-uhs2.ko"
        "kernel/drivers/net/ethernet/intel/idpf/idpf.ko"
        "kernel/drivers/net/ethernet/intel/libeth/libeth_xdp.ko"
        "kernel/drivers/net/ethernet/intel/libie/libie_adminq.ko"
        "kernel/drivers/net/ethernet/intel/libie/libie_fwlog.ko"
    )
    
    FOUND_PROBLEMS=0
    for module in "${PROBLEMATIC_MODULES[@]}"; do
        if grep -Fq "$module" "$MODULES_FILE"; then
            echo "   ❌ Found: $module (should be removed!)"
            FOUND_PROBLEMS=$((FOUND_PROBLEMS + 1))
        fi
    done
    
    if [ $FOUND_PROBLEMS -eq 0 ]; then
        echo "   ✓ All problematic modules removed"
    else
        echo "   ❌ Found $FOUND_PROBLEMS problematic modules"
        exit 1
    fi
else
    echo "   ❌ File not found: $MODULES_FILE"
    exit 1
fi

echo ""
echo "=== All tests passed! ==="
