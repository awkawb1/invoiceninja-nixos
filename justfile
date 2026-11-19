set quiet := true

# Passed to QEMU in boot-vm
export QEMU_KERNEL_PARAMS := "console=ttyS0"
export QEMU_NET_OPTS := "hostfwd=tcp::8080-:80"
export QEMU_OPTS := "-nographic"

[private]
_default:
	just --list

[doc('Clean build artifacts and shutdown running virtual machines')]
[group('maintenance')]
clean:
    #!/usr/bin/env bash
    rm result > /dev/null 2>&1
    # Scoped to this project's own disk image, not `pkill qemu` -- a bare
    # match on the process name would kill *any* QEMU VM on the host (this
    # one's forwarded port is the only reason we need to kill anything).
    pkill -f "$(pwd)/nixos.qcow2" > /dev/null 2>&1
    rm nixos.qcow2 > /dev/null 2>&1
    exit 0

[doc('Build virtual machine for testing (proxy: nginx or caddy)')]
[group('main')]
build-vm proxy="nginx": clean
    nom build ".#nixosConfigurations.test-{{proxy}}.config.system.build.vm"

[doc('Run virtual machine in current terminal')]
[group('main')]
boot-vm:
    #!/usr/bin/env bash
    [ -x result/bin/run-nixos-vm ] && \
        ./result/bin/run-nixos-vm
    reset

[doc('Run the automated NixOS VM test')]
[group('main')]
test:
    nix flake check -L

[doc('Update invoiceninja and ui to their latest upstream versions, recomputing hashes')]
[group('maintenance')]
update:
    ./scripts/update-versions.sh

[doc('Build the package and automated test, then push results to the invoiceninja-nixos cachix cache')]
[group('maintenance')]
push-cache:
    nix build --print-out-paths --no-link \
        ".#invoiceninja" \
        ".#invoiceninja.ui" \
        ".#checks.x86_64-linux.invoiceninja" \
        | cachix push invoiceninja-nixos

