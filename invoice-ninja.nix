{ config
, lib
, pkgs
, modulesPath
, ... }:


let
  cfg = config.services.invoice-ninja;
  user = cfg.user;
  group = cfg.group;
  invoice-ninja = pkgs.callPackage ./default.nix { inherit (cfg) dataDir runtimeDir; };
  configFile = pkgs.writeText "invoice-ninja-env" (lib.generators.toKeyValue { } cfg.settings);

  # PHP environment
  phpPackage = cfg.phpPackage.buildEnv {
    extensions = { enabled, all }: enabled ++ (with all;
      [ bcmath ctype curl fileinfo gd gmp iconv imagick intl mbstring mysqli openssl pdo soap tokenizer zip ]
    );

    extraConfig = "memory_limit = 1024M";
  };

  # Chromium is required for PDF invoice generation
  extraPrograms = with pkgs; [ chromium ];

  # Management script
  invoice-ninja-manage = pkgs.writeShellScriptBin "invoice-ninja-manage" ''
    cd ${invoice-ninja}
    sudo=exec
    if [[ "$USER" != ${user} ]]; then
      sudo='exec /run/wrappers/bin/sudo -u ${user}'
    fi
    $sudo ${phpPackage}/bin/php artisan "$@"
  '';
in
{
  options.services.invoice-ninja = {
    enable = lib.mkEnableOption "invoice-ninja";

    package = lib.mkPackageOption pkgs "invoice-ninja" { };

    phpPackage = lib.mkPackageOption pkgs "php82" { };

    user = lib.mkOption {
      type = lib.types.str;
      default = "invoiceninja";
      description = ''
        User account under which Invoice Ninja runs.

        ::: {.note}
        If left as the default value this user will automatically be created
        on system activation, otherwise you are responsible for
        ensuring the user exists before the Invoice Ninja application starts.
        :::
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "invoiceninja";
      description = ''
        Group account under which Invoice Ninja runs.

        ::: {.note}
        If left as the default value this group will automatically be created
        on system activation, otherwise you are responsible for
        ensuring the group exists before the Invoice Ninja application starts.
        :::
      '';
    };

    mail = {
      mailer = lib.mkOption {
        type = lib.types.enum [ "sendmail" ];
        default = "sendmail";
        description = "Controls the method used by Invoice Ninja to send mail.";
      };
      mailFromName = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "Someone";
        description = "Set the 'To' email header name attribute.";
      };
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/invoice-ninja";
      description = ''
        State directory of the `invoice-ninja` user which holds
        the application's state and data.
      '';
    };

    runtimeDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/invoice-ninja";
      description = ''
        Rutime directory of the `invoice-ninja` user which holds
        the application's caches and temporary files.
      '';
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = ''
        FQDN for the Invoice Ninja instance.
      '';
    };

    phpfpm.settings = lib.mkOption {
      type = with lib.types; attrsOf (oneOf [ int str bool ]);
      default = {
        "pm" = "dynamic";
        "pm.start_servers" = "2";
        "pm.min_spare_servers" = "2";
        "pm.max_spare_servers" = "4";
        "pm.max_children" = "8";
        "pm.max_requests" = "500";

        "request_terminate_timeout" = 300;

        "php_admin_value[error_log]" = "stderr";
        "php_admin_flag[log_errors]" = true;
      };

      description = ''
        Options for Invoice Ninja's PHPFPM pool.
      '';
    };

    secretFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        A secret file to be sourced for the .env settings.
        Place `APP_KEY`, `UPDATE_SECRET`, and other settings that should not end up in the Nix store here.
      '';
    };

    settings = lib.mkOption {
      type = with lib.types; (attrsOf (oneOf [ bool int str ]));
      description = ''
        .env settings for Invoice Ninja.
        Secrets should use `secretFile` option instead.
      '';
    };

    adminAccount = {
      createAdmin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          When set to `true`, an admin account will be created for Invoice Ninja. If set to `false`
          Invoice Ninja will run a setup wizard on first use.
        '';
      };
      email = lib.mkOption {
        type = lib.types.str;
        default = "example@email.com";
        description = "Email address of the first (admin) account for this Invoice Ninja installation";
      };
      password = lib.mkOption {
        type = lib.types.str;
        default = "example";
        description = "Password of the first (admin) account for this Invoice Ninja installation";
      };
    };

    database = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Installs a local MariaDB server to use with Invoice Ninja.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "invoiceninja";
        description = "Name of the database to use for Invoice Ninja.";
      };
    };

    maxUploadSize = lib.mkOption {
      type = lib.types.str;
      default = "8M";
      description = "Maximum allowed upload size to Invoice Ninja.";
    };

    msmtp.accounts.invoice-ninja = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      example = {
        from = "someone@example.com";
        host = "smtp.example";
        port = 25;
        auth = true;
        tls = true;
        tls_starttls = true;
        user = "someone";
        passwordeval = "cat /secrets/password.txt";
      };
      description = ''
        Here we define the msmtp configuration for an invoice-ninja account which
        will be used by Invoice Ninja to send email message.

        It is advised to use the `passwordeval` setting to read the password
        from a secret file to avoid having it written in the world-readable
        nix store. The password file must end with a newline (`\n`).
      '';
    };

    proxy = {
      server = lib.mkOption {
        type = lib.types.enum [ "caddy" "nginx" "none" ];
        default = "nginx";
        example = "caddy";
        description = ''
          Choose the proxy server to serve Invoice Ninja. Setting this to
          `none` results in no proxy server being installed.
        '';
      };
      caddyConfig = lib.mkOption {
        type = lib.types.submodule (
          (import (modulesPath + "/services/web-servers/caddy/vhost-options.nix") { cfg = config.services.caddy; }) {
            inherit lib; config = cfg; name = (if (cfg.hostName == "localhost") then ":80" else cfg.hostName);
          }
        );
        default = { };
        description = ''
          Extra configuration for the Caddy virtual host of Invoice Ninja.
              Set to `{ }` to use the default configuration
        '';
      };
      nginxConfig = lib.mkOption {
        type = lib.types.submodule (
          (import (modulesPath + "/services/web-servers/nginx/vhost-options.nix") { inherit config lib; })
        );
        default = { };
        description = ''
          Extra configuration for the Nginx virtual host of Invoice Ninja.
              Set to `{ }` to use the default configuration
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.invoiceninja = lib.mkIf (cfg.user == "invoiceninja") {
      isSystemUser = true;
      home = cfg.dataDir;
      createHome = true;
      group = cfg.group;
    };

    users.groups.invoiceninja = lib.mkIf (cfg.group == "invoiceninja") { };

    environment.systemPackages = [ invoice-ninja-manage ] ++ extraPrograms;

    programs.msmtp = {
      inherit (cfg.msmtp) accounts;
      enable = true;
    };

    services.invoice-ninja.settings =
      let
        url = ({ hostName, react ? false }: 
          if (hostName == "localhost")
            then
              (if (react == true) then ("http://" + hostName + ":3001") else ("http://" + hostName))
            else
              (if (react == true) then ("https://" + hostName + ":3001") else ("https://" + hostName))
          );
        chromium = lib.lists.findSingle (x: x == pkgs.chromium) "none" "multiple" extraPrograms;
      in
      lib.mkMerge [
        ({
          APP_NAME = lib.mkDefault "\"Invoice Ninja\"";
          APP_ENV = lib.mkDefault "production";
          APP_DEBUG = lib.mkDefault false;
          EXPANDED_LOGGING = lib.mkDefault true;
          APP_URL = lib.mkDefault (url { hostName = cfg.hostName; });
          REACT_URL = lib.mkDefault (url { hostName = cfg.hostName; react = true; });
          MAIL_MAILER = lib.mkDefault cfg.mail.mailer;
          MAIL_SENDMAIL_PATH = lib.mkDefault (
            if (cfg.mail.mailer == "sendmail")
            then
              ''"/run/wrappers/bin/sendmail -t -a invoice-ninja"''
            else
              ""
          );
          MAIL_FROM_ADDRESS = lib.mkDefault "${cfg.msmtp.accounts.invoice-ninja.from}";
          MAIL_FROM_NAME = lib.mkDefault ''"${cfg.mail.mailFromName}"'';
          ERROR_EMAIL = lib.mkDefault "${cfg.msmtp.accounts.invoice-ninja.from}";
          DB_CONNECTION = lib.mkDefault "mysql";
          MULTI_DB_ENABLED = lib.mkDefault false;
          DEMO_MODE = lib.mkDefault false;
          BROADCAST_DRIVER = lib.mkDefault "pusher";
          LOG_CHANNEL = lib.mkDefault "stack";
          CACHE_DRIVER = lib.mkDefault "file";
          QUEUE_CONNECTION = lib.mkDefault "database";
          SESSION_DRIVER = lib.mkDefault "file";
          SESSION_LIFETIME = lib.mkDefault "120";
          REQUIRE_HTTPS = lib.mkDefault (if (cfg.hostName != "localhost") then true else false);
          TRUSTED_PROXIES = lib.mkDefault "127.0.0.1";
          NINJA_ENVIRONMENT = lib.mkDefault "selfhost";
          LOCAL_DOWNLOAD= lib.mkDefault false;
          PDF_GENERATOR = lib.mkDefault "snappdf";
          SNAPPDF_CHROMIUM_PATH = lib.mkDefault "${chromium}/bin/chromium";
          PRECONFIGURED_INSTALL = lib.mkDefault true;
        })
        (lib.mkIf (cfg.database.createLocally) {
          DB_CONNECTION = lib.mkDefault "mysql";
          DB_HOST = lib.mkDefault "localhost";
          DB_SOCKET = lib.mkDefault "/run/mysqld/mysqld.sock";
          DB_DATABASE = lib.mkDefault cfg.database.name;
          DB_USERNAME = lib.mkDefault user;
        })
      ];

    services.phpfpm.pools.invoice-ninja = {
      inherit user group phpPackage;

      settings = {
        "listen.owner" = user;
        "listen.group" = group;
        "listen.mode" = "0660";
        "catch_workers_output" = true;
      } // cfg.phpfpm.settings;

      phpOptions = ''
        post_max_size = ${cfg.maxUploadSize}
        upload_max_filesize = ${cfg.maxUploadSize}
        max_execution_time = 600;
      '';
    };

    users.users."${config.services.nginx.user}" = lib.mkIf (cfg.proxy.server == "nginx") { extraGroups = [ cfg.group ]; };
    services.nginx = lib.mkIf (cfg.proxy.server == "nginx") {
      enable = true;

      recommendedTlsSettings = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      recommendedOptimisation = true;

      clientMaxBodySize = cfg.maxUploadSize;

      virtualHosts."${cfg.hostName}" = lib.mkMerge [
        cfg.proxy.nginxConfig
        {
          root = lib.mkForce "${invoice-ninja}/public";
          locations = {
            "= /index.php".extraConfig = '' 
              fastcgi_split_path_info ^(.+\.php)(/.+)$;
              fastcgi_pass unix:${config.services.phpfpm.pools.invoice-ninja.socket};
              fastcgi_index index.php;
            '';
            "/" = {
              tryFiles = "$uri $uri/ /index.php?$query_string";
              extraConfig = ''
                if (!-e $request_filename) {
                    rewrite ^(.+)$ /index.php?q=$1 last;
                }
              '';
            };
            "~ \\.php$".extraConfig = "return 403;";
            "~ /\\.ht".extraConfig = "deny all;";
          };
          extraConfig = ''
            index index.html index.htm index.php;
            error_page 404 /index.php;
          '';
        }
      ];
    };

    users.users."${config.services.caddy.user}" = lib.mkIf (cfg.proxy.server == "caddy") { extraGroups = [ cfg.group ]; };
    services.caddy = lib.mkIf (cfg.proxy.server == "caddy") {
      enable = true;

      globalConfig = lib.mkIf (cfg.hostName == "localhost") ''
        auto_https disable_redirects
      '';

      virtualHosts."${cfg.hostName}" = lib.mkMerge [
        cfg.proxy.caddyConfig
        {
          extraConfig = ''
            encode zstd gzip
            root * ${invoice-ninja}/public
            php_fastcgi unix/${config.services.phpfpm.pools.invoice-ninja.socket}
            file_server
          '';
        }
      ];
    };

    services.mysql = lib.mkIf (cfg.database.createLocally) {
      enable = lib.mkDefault true;
      package = lib.mkDefault pkgs.mariadb;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [{
        name = user;
        ensurePermissions = { "${cfg.database.name}.*" = "ALL PRIVILEGES"; };
      }];
    };

    systemd.services.phpfpm-invoice-ninja.after = [ "invoice-ninja-data-setup.service" ];
    systemd.services.phpfpm-invoice-ninja.requires = [ "invoice-ninja-data-setup.service" ]
      ++ lib.optional cfg.database.createLocally "mysql.service";
    # Ensure chromium is available
    systemd.services.phpfpm-invoice-ninja.path = extraPrograms;

    systemd.services.invoice-ninja-worker = {
      description = "Invoice Ninja periodic tasks";
      after = [ "invoice-ninja-data-setup.service" ];
      requires = [ "phpfpm-invoice-ninja.service" ];
      wantedBy = [ "multi-user.target" ];
      reloadTriggers = [ invoice-ninja ];
      reload = "${invoice-ninja-manage}/bin/invoice-ninja-manage queue:restart";

      serviceConfig = {
        ExecStart = "${invoice-ninja-manage}/bin/invoice-ninja-manage queue:work";
        User = user;
        Group = group;
        StateDirectory = lib.mkIf (cfg.dataDir == "/var/lib/invoice-ninja") "invoice-ninja";
      };
    };

    systemd.services.invoice-ninja-data-setup = {
      description =
        "Invoice Ninja setup: migrations, environment file update, cache reload, data changes";
      wantedBy = [ "multi-user.target" ];
      after = lib.optional cfg.database.createLocally "mysql.service";
      requires = lib.optional cfg.database.createLocally "mysql.service";
      path = with pkgs; [ bash invoice-ninja-manage rsync config.services.mysql.package ] ++ extraPrograms;

      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        StateDirectory = lib.mkIf (cfg.dataDir == "/var/lib/invoice-ninja") "invoice-ninja";
        StateDirectoryMode = "0750";
        LoadCredential = "env-secrets:${cfg.secretFile}";
        UMask = "077";
      };

      script = ''
        # Before running any PHP program, cleanup the code cache.
        # It's necessary if you upgrade the application otherwise you might
        # try to import non-existent modules.
        rm -f ${cfg.runtimeDir}/app.php
        rm -rf ${cfg.runtimeDir}/cache/*

        # Concatenate non-secret .env and secret .env
        rm -f ${cfg.dataDir}/.env
        cp --no-preserve=all ${configFile} ${cfg.dataDir}/.env
        echo -e '\n' >> ${cfg.dataDir}/.env
        cat "$CREDENTIALS_DIRECTORY/env-secrets" >> ${cfg.dataDir}/.env

        # Link the static storage (package provided) to the runtime storage
        # Necessary for cities.json and static images.
        rsync -av --no-perms ${invoice-ninja}/storage-static/ ${cfg.dataDir}/storage
        
        # Link the app.php in the runtime folder.
        # We cannot link the cache folder only because bootstrap folder needs to be writeable.
        ln -sf ${invoice-ninja}/bootstrap-static/app.php ${cfg.runtimeDir}/app.php

        # Perform the first migration
        [[ ! -f ${cfg.dataDir}/.initial-migration ]] && invoice-ninja-manage migrate --force && touch ${cfg.dataDir}/.initial-migration

        # Seed database with records
        # Necessary for languages, currencies, countries, etc.
        [[ ! -f ${cfg.dataDir}/.db-seeded ]] && invoice-ninja-manage db:seed --force && touch ${cfg.dataDir}/.db-seeded

        # Create Invoice Ninja admin account
        [[ (! -f ${cfg.dataDir}/.admin-created) && (${if cfg.adminAccount.createAdmin then "true" else "false"} == "true") ]] \
          && invoice-ninja-manage ninja:create-account --email=${cfg.adminAccount.email} --password=${cfg.adminAccount.password} \
          && touch ${cfg.dataDir}/.admin-created
        
        invoice-ninja-manage route:cache
        invoice-ninja-manage view:cache
        invoice-ninja-manage config:cache
      '';
    };

    systemd.tmpfiles.settings."10-invoice-ninja" = lib.attrsets.genAttrs [
      cfg.dataDir
      "${cfg.dataDir}/storage"
      "${cfg.dataDir}/storage/app"
      "${cfg.dataDir}/storage/app/public"
      "${cfg.dataDir}/storage/framework"
      "${cfg.dataDir}/storage/framework/cache"
      "${cfg.dataDir}/storage/framework/sessions"
      "${cfg.dataDir}/storage/framework/testing"
      "${cfg.dataDir}/storage/framework/views"
      "${cfg.dataDir}/storage/logs"
    ] (n: {
      d = {
        user = user;
        group = group;
        mode = "0770";
      };
    }) // lib.attrsets.genAttrs [
      cfg.runtimeDir
      "${cfg.runtimeDir}/cache"
    ] (n: {
      d = {
        user = user;
        group = group;
        mode = "0750";
      };
    });
  };
}

