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

  # `just boot-vm` forwards the guest's port 80 to host port 8080 (QEMU_NET_OPTS in the justfile),
  # but the backend builds absolute URLs (e.g. the stored company logo path) from APP_URL, which
  # defaults to plain "http://localhost" with no port. The SPA's own relative URLs are fine (they
  # inherit whatever port the browser is already on), but any backend-generated absolute URL then
  # points at host port 80 - where nothing is listening - instead of the forwarded 8080, giving a
  # silent net::ERR_CONNECTION_REFUSED for things like the logo image. Override to match the actual
  # forwarded port.
  services.invoiceninja.settings.APP_URL = "http://localhost:8080";

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
