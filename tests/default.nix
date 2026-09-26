{ proxyServer ? "nginx" }:
{ pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    # Not imported by default for a plain nixosSystem in this nixpkgs (only nixosTest nodes get it
    # automatically) - needed explicitly so virtualisation.cores/memorySize below are real options.
    (modulesPath + "/virtualisation/qemu-vm.nix")
    (import ./common.nix { inherit proxyServer; })
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

  # The qemu-vm module's defaults (1 core, 1024MB) are too tight for real interactive use: MySQL +
  # Redis + PHP-FPM + chromium (PDF generation, spawned per request - each is a full multi-process
  # browser, not a lightweight renderer) running concurrently can exhaust 1GB fast, and this VM
  # boots with panic_on_oom - so it's not a graceful slowdown, the whole VM goes down. Confirmed by
  # reproducing a "logo upload hangs" report this way: at the 1024MB default, even a couple of
  # concurrent PDF-generation requests triggered `redis-server invoked oom-killer` and a kernel
  # panic. 2 cores / 2560MB comfortably handles 2 concurrent PDF generations alongside normal
  # traffic (verified: ~1.4GB still free afterward); a deliberate flood of many concurrent PDF
  # requests can still exhaust even this, since each is a full chromium instance - if that's a
  # concern for your deployment, consider capping `phpfpm.settings."pm.max_children"` below its
  # default of 8, or provisioning more RAM.
  virtualisation.cores = 2;
  virtualisation.memorySize = 2560;
}
