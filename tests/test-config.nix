{ config, pkgs, modulesPath, ... }:

let
  invoice-ninja-script = pkgs.writers.writeBashBin "create-invoice-ninja-user" ''
    invoice-ninja-manage ninja:
  '';
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../invoice-ninja.nix
  ];

  system.stateVersion = "24.05";

  nixpkgs.config.allowUnfree = true;

  users.users.test-user = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "testing";
  };

  services.invoice-ninja = {
    enable = true;
    database.createLocally = true;
    nginx = { };
    secretFile = ./test-secrets.env;
  };

  networking.firewall.enable = false;

  services.resolved.enable = true;

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
}
