{ ... }:

{
  imports = [ ../nixos-module/invoiceninja.nix ];

  services.invoiceninja = {
    enable = true;
    proxy.server = "nginx";
    adminAccount.passwordFile = ./invoice_ninja_test_password;
    secretFile = ./test.env;
    settings.APP_DEBUG = true;
  };

  networking.firewall.enable = false;
}
