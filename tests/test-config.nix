{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../invoice-ninja.nix
  ];

  system.stateVersion = "24.05";

  nixpkgs.config.allowUnfree = true;

  environment.etc."msmtp-password" = {
    enable = true;
    user = "invoiceninja";
    group = "invoiceninja";
    mode = "0440";
    text = ''
      3t5h638t3a7y7275

    '';
  };

  users.users.test = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "test";
  };

  services.invoice-ninja = {
    enable = true;
    database.createLocally = true;
    webserver.caddy.enable = true;
    webserver.nginx.enable = false;
    mail.mailFromName = "Andrew Bryant";
    adminEmail = "billing@allpawcare.com";
    msmtp.accounts.invoice-ninja = {
      auth = true;
      tls = true;
      tls_starttls = false;
      from = "billing@allpawcare.com";
      host = "smtp.fastmail.com";
      port = 465;
      user = "awkawb@awkawb.cloud";
      passwordeval = "cat /etc/msmtp-password";
    };
    secretFile = ./test-secrets.env;
  };

  networking.firewall.enable = false;

  services.resolved.enable = true;
}
