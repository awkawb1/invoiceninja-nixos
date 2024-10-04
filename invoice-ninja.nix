{ config, lib, pkgs, ... }:

let
  cfg = config.services.invoice-ninja;
  user = cfg.user;
  group = cfg.group;
  testing = pkgs.callPackage ./default.nix { inherit lib; php = pkgs.php; fetchFromGitHub = pkgs.fetchFromGitHub; };
  invoice-ninja = testing.override { inherit (cfg) dataDir runtimeDir; };
  configFile = pkgs.writeText "invoice-ninja-env" (lib.generators.toKeyValue { } cfg.settings);

  # PHP environment
  phpPackage = cfg.phpPackage.buildEnv {
    extensions = { enabled, all }: enabled ++ (with all;
      [ bcmath ctype curl fileinfo gd gmp iconv imagick mbstring mysqli openssl pdo tokenizer zip ]
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

    schedulerInterval = lib.mkOption {
      type = lib.types.str;
      default = "1d";
      description = "How often the Invoice Ninja cron task should run.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = ''
        FQDN for the Invoice Ninja instance.
      '';
    };

    phpfpm.settings = lib.mkOption {
      type = with lib.types; attrsOf (oneOf [ int str bool ]);
      default = {
        "listen.owner" = user;
        "listen.group" = group;
        "listen.mode" = "0660";

        "pm" = "dynamic";
        "pm.start_servers" = "2";
        "pm.min_spare_servers" = "2";
        "pm.max_spare_servers" = "4";
        "pm.max_children" = "8";
        "pm.max_requests" = "500";

        "request_terminate_timeout" = 300;

        "php_admin_value[error_log]" = "stderr";
        "php_admin_flag[log_errors]" = true;

        "catch_workers_output" = true;
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

    adminEmail = lib.mkOption {
      type = lib.types.str;
      default = "example@email.com";
      description = "Email address of the first (admin) account for this Invoice Ninja installation";
    };

    adminPassword = lib.mkOption {
      type = lib.types.str;
      default = "example";
      description = "Password of the first (admin) account for this Invoice Ninja installation";
    };

    database = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "a local database using UNIX socket authentication";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "invoiceninja";
        description = "Database name for Invoice Ninja.";
      };
    };

    caddy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable a preconfigured Caddy server to serve
        Invoice Ninja.
      '';
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

    services.invoice-ninja.settings =
      let
        app_http_url = "http://${cfg.domain}";
        app_https_url = "https://${cfg.domain}";
        react_http_url = "http://${cfg.domain}:3001";
        react_https_url = "https://${cfg.domain}:3001";
        chromium = lib.lists.findSingle (x: x == pkgs.chromium) "none" "multiple" extraPrograms;
      in
      lib.mkMerge [
        ({
          APP_NAME = lib.mkDefault "\"Invoice Ninja\"";
          APP_ENV = lib.mkDefault "production";
          APP_DEBUG = lib.mkDefault false;
          APP_URL = lib.mkDefault (if (cfg.domain != "localhost") then "${app_https_url}" else "${app_http_url}");
          REACT_URL = lib.mkDefault (if (cfg.domain != "localhost") then "${react_https_url}" else "${react_http_url}");
          DB_CONNECTION = lib.mkDefault "mysql";
          MULTI_DB_ENABLED = lib.mkDefault false;
          DEMO_MODE = lib.mkDefault false;
          BROADCAST_DRIVER = lib.mkDefault "log";
          LOG_CHANNEL = lib.mkDefault "stack";
          CACHE_DRIVER = lib.mkDefault "file";
          QUEUE_CONNECTION = lib.mkDefault "database";
          SESSION_DRIVER = lib.mkDefault "file";
          SESSION_LIFETIME = lib.mkDefault "120";
          REQUIRE_HTTPS = lib.mkDefault (if (cfg.domain != "localhost") then true else false);
          TRUSTED_PROXIES = lib.mkDefault "127.0.0.1";
          NINJA_ENVIRONMENT = lib.mkDefault "selfhost";
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
      inherit (cfg.phpfpm) settings;
    };

    users.users."${config.services.caddy.user}" = lib.mkIf (cfg.caddy != false) { extraGroups = [ cfg.group ]; };
    services.caddy =
      let
        caddyDomain = if (cfg.domain == "localhost") then ":80" else cfg.domain;
      in
      lib.mkIf (cfg.caddy != false) {
      enable = true;

      globalConfig = lib.mkIf (cfg.domain == "localhost") ''
        auto_https disable_redirects
      '';

      virtualHosts."${caddyDomain}".extraConfig = ''
        encode zstd gzip
        root * ${invoice-ninja}/public/
        php_fastcgi unix/${config.services.phpfpm.pools.invoice-ninja.socket}
        try_files {path} {path}/ /public/{path} /index.php?{query}
        file_server
      '';
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

    systemd.timers.invoice-ninja-cron = {
      description = "Invoice Ninja periodic tasks timer";
      after = [ "invoice-ninja-data-setup.service" ];
      requires = [ "phpfpm-invoice-ninja.service" ];
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = cfg.schedulerInterval;
        OnUnitActiveSec = cfg.schedulerInterval;
      };
    };

    systemd.services.invoice-ninja-cron = {
      description = "Invoice Ninja periodic tasks";

      serviceConfig = {
        ExecStart = "${invoice-ninja-manage}/bin/invoice-ninja-manage schedule:run";
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

                # Create Invoice Ninja admin account
                [[ ! -f ${cfg.dataDir}/.admin-created ]] \
                  && invoice-ninja-manage ninja:create-account --email=${cfg.adminEmail} --password=${cfg.adminPassword} \
                  && touch ${cfg.dataDir}/.admin-created
                
                # Recent releases make the React interface default
                # Currently this is broken so we switch back to the Flutter interface
                [[ ! -f ${cfg.dataDir}/.react-disabled ]] \
                  && mysql -D ${cfg.database.name} -e 'UPDATE accounts SET set_react_as_default_ap = 0;' \
                  && touch ${cfg.dataDir}/.react-disabled

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
        mode = "0770";
      };
    });
  };
}

