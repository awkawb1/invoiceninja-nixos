{ pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./common.nix
  ];

  # Required to build pkgs.chromium, which the module pulls in for PDF generation.
  nixpkgs.config.allowUnfree = true;

  # `nix flake check` evaluates config.system.build.toplevel directly, which asserts a real root
  # filesystem and bootloader are configured. `just build-vm` builds config.system.build.vm
  # instead, where the qemu-vm module overrides both of these with a tmpfs root and direct
  # kernel boot (virtualisation.useBootLoader defaults to false) - so these values just need to
  # satisfy the assertions and are otherwise unused.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.grub.enable = false;

  users.users.root = {
    initialPassword = "toor";
  };

  services.resolved.enable = true;
}
