{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../invoice-ninja.nix
  ];

  system.stateVersion = "24.05";

  nixpkgs.config.allowUnfree = true;

  users.users.test = {
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
}
