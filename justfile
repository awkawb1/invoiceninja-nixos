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
    rm nixos.qcow2 > /dev/null 2>&1
    pkill qemu
    exit 0

[doc('Build virtual machine for testing')]
[group('main')]
build-vm: clean
    nom build ".#nixosConfigurations.test.config.system.build.vm"

[doc('Run virtual machine in current terminal')]
[group('main')]
boot-vm:
    #!/usr/bin/env bash
    [ -x result/bin/run-nixos-vm ] && \
        ./result/bin/run-nixos-vm
    reset

