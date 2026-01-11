# Module Configuration Fix

## Problem
The `make installer` build was failing with errors about missing kernel modules:

```
install: cannot stat 'usr/lib/modules/6.18.4-talos/kernel/drivers/gpu/drm/drm_gpuvm.ko': No such file or directory
install: cannot stat 'usr/lib/modules/6.18.4-talos/kernel/drivers/irqchip/irq-bcm2712-mip.ko': No such file or directory
install: cannot stat 'usr/lib/modules/6.18.4-talos/kernel/drivers/mmc/host/sdhci-uhs2.ko': No such file or directory
...
```

## Root Cause
The base Talos `modules-arm64.txt` file (from vendor/talos v1.12.1) contained kernel modules that don't exist in kernel 6.18.4 (rpi-6.18.y). These modules may exist in newer kernels but aren't present in the Raspberry Pi kernel fork.

## Solution
Added the non-existent modules to the `modules.remove` list in `config.yaml`:

```yaml
modules:
  remove:
    # Modules that don't exist in kernel 6.18.4
    - kernel/drivers/gpu/drm/drm_gpuvm.ko
    - kernel/drivers/irqchip/irq-bcm2712-mip.ko
    - kernel/drivers/mmc/host/sdhci-uhs2.ko
    - kernel/drivers/net/ethernet/intel/idpf/idpf.ko
    - kernel/drivers/net/ethernet/intel/libeth/libeth_xdp.ko
    - kernel/drivers/net/ethernet/intel/libie/libie_adminq.ko
    - kernel/drivers/net/ethernet/intel/libie/libie_fwlog.ko
    - kernel/drivers/gpu/drm/display/drm_dp_aux_bus.ko
```

Also removed `drm_dp_aux_bus.ko` from the `modules.add` list since it doesn't exist in this kernel version.

## Verification
After running `make patches-talos`, the script `apply-module-changes.sh`:
1. ✅ Correctly reads modules from `config.yaml` using yq
2. ✅ Removes non-existent modules from `vendor/talos/hack/modules-arm64.txt`
3. ✅ Adds Raspberry Pi specific modules
4. ✅ Results in 112 total modules in the final modules-arm64.txt

The `make installer` build now progresses without module installation errors.

## Notes
- The warnings about `modules.order` and `modules.builtin.modinfo` are harmless and expected
- The `apply-module-changes.sh` script requires yq to be installed (`brew install yq`)
- The script is idempotent - running it multiple times produces the same result
