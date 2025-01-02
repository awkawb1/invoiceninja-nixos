{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../nixos-module/invoiceninja.nix
  ];

  system.stateVersion = "24.11";

  nixpkgs.config.allowUnfree = true;

  users.users.test = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "test";
  };

  services.invoiceninja = {
    enable = true;
    proxy.server = "caddy";
    adminAccount.passwordFile = ./invoice_ninja_test_password;
    secretFile = ./test.env;
  };

  networking.firewall.enable = false;

  services.resolved.enable = true;
}

