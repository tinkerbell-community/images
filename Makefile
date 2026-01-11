# Build Configuration - extracted from Pkgfile
PKGS_VERSION ?= $(shell yq '.pkgs_version' Pkgfile)
TALOS_VERSION ?= $(shell yq '.talos_version' Pkgfile)
SBCOVERLAY_VERSION ?= $(shell yq '.overlay_version' Pkgfile)
RPI_KERNEL_REF ?= rpi-6.18.y

# Determine major version for patch selection
TALOS_MAJOR_VERSION = $(shell echo $(TALOS_VERSION) | sed 's/v\([0-9]*\)\.\([0-9]*\)\..*/v\1.\2/')

REGISTRY ?= ghcr.io
REGISTRY_USERNAME ?= tinkerbell-community

TAG ?= $(shell git describe --tags --exact-match)

# Kernel build configuration
PLATFORM ?= linux/arm64
PROGRESS ?= auto
PUSH ?= true
CI_ARGS ?=

EXTENSIONS ?= ghcr.io/siderolabs/gvisor:20250505.0@sha256:d7503b59603f030b972ceb29e5e86979e6c889be1596e87642291fee48ce380c

PKG_REPOSITORY = https://github.com/siderolabs/pkgs.git
TALOS_REPOSITORY = https://github.com/siderolabs/talos.git
SBCOVERLAY_REPOSITORY = https://github.com/$(REGISTRY_USERNAME)/sbc-raspberrypi.git

VENDOR_DIRECTORY := $(PWD)/vendor
PATCHES_DIRECTORY := $(PWD)/patches

.PHONY: help clean list-profiles build rpi arm64 amd64
.PHONY: vendor vendor-clean patches-pkgs patches-talos patches
.PHONY: kernel overlay installer
.PHONY: release release-kernel release-overlay release-installer
.PHONY: download-push-talos

#
# Help
#
help:
	@echo "Talos Images Build Framework"
	@echo ""
	@echo "=== Machine-image Builds ==="
	@echo "  rpi            - Build Raspberry Pi image"
	@echo "  arm64          - Build generic ARM64 image"
	@echo "  amd64          - Build generic AMD64 image"
	@echo ""
	@echo "=== Advanced Build Targets ==="
	@echo "  vendor         - Clone repositories required for the build"
	@echo "  patches        - Apply all patches (kernel + config + modules)"
	@echo "  kernel         - Build kernel"
	@echo "  overlay        - Build Raspberry Pi 5 overlay"
	@echo "  installer      - Build installer docker image and disk image"
	@echo "  release        - Tag images with current Git tag (for final release)"
	@echo ""
	@echo "=== Configuration ==="
	@echo "  RPI_KERNEL_REF - Raspberry Pi kernel tag (default: stable_20250428)"
	@echo ""
	@echo "=== Maintenance ==="
	@echo "  clean          - Remove build artifacts and vendor"
	@echo ""
	@echo "Examples:"
	@echo "  make rpi"
	@echo "  make build PROFILE=rpi-generic"
	@echo "  make vendor patches kernel overlay installer"

#
# Checkouts
#
vendor:
	@mkdir -p "$(VENDOR_DIRECTORY)"

$(VENDOR_DIRECTORY)/pkgs:
	git clone -c advice.detachedHead=false --branch "$(PKGS_VERSION)" "$(PKG_REPOSITORY)" "$(VENDOR_DIRECTORY)/pkgs"

$(VENDOR_DIRECTORY)/talos:
	git clone -c advice.detachedHead=false --branch "$(TALOS_VERSION)" "$(TALOS_REPOSITORY)" "$(VENDOR_DIRECTORY)/talos"

$(VENDOR_DIRECTORY)/sbc-raspberrypi:
	git clone -c advice.detachedHead=false --branch "$(SBCOVERLAY_VERSION)" "$(SBCOVERLAY_REPOSITORY)" "$(VENDOR_DIRECTORY)/sbc-raspberrypi"

vendor-clean:
	rm -rf "$(VENDOR_DIRECTORY)/pkgs"
	rm -rf "$(VENDOR_DIRECTORY)/talos"
	rm -rf "$(VENDOR_DIRECTORY)/sbc-raspberrypi"

.PHONY: vendor-all
vendor-all: vendor $(VENDOR_DIRECTORY)/pkgs $(VENDOR_DIRECTORY)/talos $(VENDOR_DIRECTORY)/sbc-raspberrypi

#
# Patches
#
.PHONY: patches-pkgs patches-talos patches
patches-pkgs: $(VENDOR_DIRECTORY)/pkgs
	@echo "Merging RPI5 kernel config fragment (using yq)..."
	./scripts/merge-config-yq.sh -c $(VENDOR_DIRECTORY)/pkgs/kernel/build/config-arm64 -y config/kernel.yaml
	@echo "Updating Raspberry Pi kernel version..."
	./scripts/update-rpi-kernel.sh $(RPI_KERNEL_REF)

patches-talos: $(VENDOR_DIRECTORY)/talos
	@echo "Applying module changes for Raspberry Pi 5..."
	./scripts/apply-module-changes.sh

patches: patches-pkgs patches-talos

PKGS_TAG = $(shell cd $(VENDOR_DIRECTORY)/pkgs && git describe --tag --always --dirty --match v[0-9]\*)

#
# Kernel
#
kernel: patches-pkgs
	cd "$(VENDOR_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PLATFORM=$(PLATFORM) \
			PROGRESS=$(PROGRESS) \
			CI_ARGS="$(CI_ARGS)" \
			kernel

#
# Overlay
#
overlay: | $(VENDOR_DIRECTORY)/sbc-raspberrypi
	cd "$(VENDOR_DIRECTORY)/sbc-raspberrypi" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_VERSION) PUSH=$(PUSH) \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_VERSION) \
			INSTALLER_ARCH=arm64 PLATFORM=$(PLATFORM) \
			PROGRESS=$(PROGRESS) \
			CI_ARGS="$(CI_ARGS)" \
			sbc-raspberrypi

TALOS_TAG = $(shell cd $(VENDOR_DIRECTORY)/talos && git describe --tag --always --dirty --match v[0-9]\*)

#
# Installer/Image
#
installer: patches-talos
	cd "$(VENDOR_DIRECTORY)/talos" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=$(PUSH) \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_VERSION) \
			INSTALLER_ARCH=arm64 PLATFORM=$(PLATFORM) \
			PROGRESS=$(PROGRESS) \
			CI_ARGS="$(CI_ARGS)" \
			IMAGER_ARGS="--overlay-name=rpi_generic --base-installer-image=$(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_TAG) --overlay-image=$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_VERSION) --system-extension-image=$(EXTENSIONS)" \
			kernel initramfs imager installer-base installer

#
# Release
#
release-kernel:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_VERSION) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_VERSION) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_VERSION) $(REGISTRY)/$(REGISTRY_USERNAME)/kernel:latest && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/kernel:latest

release-overlay:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_VERSION) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_VERSION) $(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:latest && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:latest

release-installer:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_VERSION) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_VERSION) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_VERSION) $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:latest && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:latest && \
		docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_VERSION) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_VERSION) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_VERSION) $(REGISTRY)/$(REGISTRY_USERNAME)/installer:latest && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer:latest && \
		docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_VERSION) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_VERSION) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_VERSION) $(REGISTRY)/$(REGISTRY_USERNAME)/imager:latest && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/imager:latest

release: release-kernel release-overlay release-installer

#
# Machine Images
#
rpi:
	./scripts/build.sh \
		--arch arm64 \
		--platform nocloud \
		--version $(TALOS_VERSION) \
		--imager $(REGISTRY)/$(REGISTRY_USERNAME)/imager \
		--overlay-name rpi_generic \
		--overlay-image $(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_VERSION) \
		--base-installer $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_VERSION) \
		--extension ghcr.io/siderolabs/iscsi-tools:v0.2.0 \
		--extension ghcr.io/siderolabs/util-linux-tools:2.41.2 \
		--disk-size 1306902528

arm64:
	./scripts/build.sh \
		--arch arm64 \
		--platform nocloud \
		--version $(TALOS_VERSION) \
		--base-installer $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_VERSION) \
		--imager $(REGISTRY)/$(REGISTRY_USERNAME)/imager

amd64:
	./scripts/build.sh \
		--arch amd64 \
		--platform nocloud \
		--version $(TALOS_VERSION) \
		--imager $(REGISTRY)/$(REGISTRY_USERNAME)/imager \
		--base-installer $(REGISTRY)/$(REGISTRY_USERNAME)/installer-base:$(TALOS_VERSION) \
		--extension ghcr.io/siderolabs/iscsi-tools:v0.2.0 \
		--extension ghcr.io/siderolabs/util-linux-tools:2.41.2 \
		--extension ghcr.io/siderolabs/intel-ucode:20231114

#
# Clean
#
clean: vendor-clean
	rm -rf _out/
	@echo "Build artifacts removed"
