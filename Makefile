.PHONY: help clean rpi-generic generic-arm64 list-profiles

# Default target
help:
	@echo "Talos Images Build Framework"
	@echo ""
	@echo "Available targets:"
	@echo "  help           - Show this help message"
	@echo "  list-profiles  - List all available build profiles"
	@echo "  rpi-generic    - Build Raspberry Pi generic image"
	@echo "  generic-arm64  - Build generic ARM64 image"
	@echo "  clean          - Remove build artifacts"
	@echo ""
	@echo "Custom builds:"
	@echo "  make build PROFILE=<profile-name>"
	@echo ""
	@echo "Examples:"
	@echo "  make rpi-generic"
	@echo "  make build PROFILE=rpi-generic"

# List available profiles
list-profiles:
	@echo "Available profiles:"
	@ls -1 profiles/*.yaml 2>/dev/null | sed 's/profiles\//  - /' | sed 's/\.yaml//' || echo "  No profiles found"

# Generic build target
build:
ifndef PROFILE
	@echo "Error: PROFILE is required"
	@echo "Usage: make build PROFILE=<profile-name>"
	@echo ""
	@make list-profiles
	@exit 1
endif
	./build.sh --profile $(PROFILE)

# Specific profile targets
rpi-generic:
	./build.sh --profile rpi-generic

generic-arm64:
	./build.sh --profile generic-arm64

# Clean build artifacts
clean:
	rm -rf _out/
	@echo "Build artifacts removed"
