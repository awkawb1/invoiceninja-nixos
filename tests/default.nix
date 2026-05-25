{ pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../nixos-module/invoiceninja.nix
  ];

  system.stateVersion = "25.11";

  nixpkgs.config.allowUnfree = true;

  users.users.test = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "test";
  };

  services.invoiceninja = {
    enable = true;
    proxy.server = "nginx";
    adminAccount.passwordFile = ./invoice_ninja_test_password;
    secretFile = ./test.env;
    settings.APP_DEBUG = true;
  };

  networking.firewall.enable = false;

  services.resolved.enable = true;
}

