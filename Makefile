####
# Target definitions
####

# Disable echoing of target recipe commands
# Comment this for debugging
.SILENT:

# Run target recipes in one shell invocation
.ONESHELL:

# Since all targets are phony, all targets should be listed here
# One target per line
.PHONY: boot-vm \
	build-vm \
	clean \
	format-nix-files \
	help

# Show the help text
help:
	egrep -h '\s##\s' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'


format-nix-files: ## Format nix files using the nixpkgs-fmt tool
	find . -name "*.nix" -exec nixpkgs-fmt {} \;

clean: ## Clean build artifacts and shutdown running virtual machines
	rm result > /dev/null 2>&1
	rm nixos.qcow2 > /dev/null 2>&1
	pkill qemu
	exit 0

build-vm: clean ## Build virtual machine for testing
	nixos-rebuild build-vm \
		-I nixpkgs=http://nixos.org/channels/nixos-24.05/nixexprs.tar.xz \
		-I nixos-config=./tests/test-config.nix

boot-vm: ## Run virtual machine in current terminal
	QEMU_KERNEL_PARAMS=console=ttyS0 \
	QEMU_NET_OPTS=hostfwd=tcp::8080-:80 \
	./result/bin/run-nixos-vm \
		-nographic; \
	reset

