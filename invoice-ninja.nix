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
      [ bcmath ctype curl fileinfo gd gmp iconv mbstring mysqli openssl pdo tokenizer zip ]
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

    enableACME = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        				Whether an ACME certificate should be used to secure connections to the server.
        			'';
    };

    nginx = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule
        (import <nixpkgs/nixos/modules/services/web-servers/nginx/vhost-options.nix> {
          inherit config lib;
        }));
      default = null;
      example = ''
        {
          enableACME = true;
          forceHttps = true;
        }
      '';
      description = ''
        With this option, you can customize an nginx virtual host which already has sensible defaults
        for Invoice Ninja. Set to {} if you do not need any customization to the virtual host.
        If enabled, then by default, the {option}`serverName` is `''${domain}`. If this is set to
        null (the default), no nginx virtualHost will be configured.
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
        })
        (lib.mkIf (cfg.database.createLocally) {
          DB_CONNECTION = lib.mkDefault "mysql";
          DB_HOST = lib.mkDefault "localhost";
          DB_SOCKET = lib.mkDefault "/run/mysqld/mysqld.sock";
          DB_DATABASE = lib.mkDefault cfg.database.name;
          DB_USERNAME = lib.mkDefault user;
        })
      ];

    services.phpfpm.pools.invoiceninja = {
      inherit user group phpPackage;
      inherit (cfg.phpfpm) settings;
    };

    users.users."${config.services.nginx.user}" = lib.mkIf (cfg.nginx != null) { extraGroups = [ cfg.group ]; };
    services.nginx = lib.mkIf (cfg.nginx != null) {
      enable = true;

      clientMaxBodySize = "20m";

      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      appendHttpConfig = ''
        				# Add HSTS header with preloading to HTTPS requests.
        				# Adding this header to HTTP requests is discouraged
        				map $scheme $hsts_header {
        						https   "max-age=31536000; includeSubdomains; preload";
        				}
        				add_header Strict-Transport-Security $hsts_header;

        				# Minimize information leaked to other domains
        				add_header 'Referrer-Policy' 'origin-when-cross-origin';

        				# Disable embedding as a frame
        				add_header X-Frame-Options DENY;

        				# Prevent injection of code in other mime types (XSS Attacks)
        				add_header X-Content-Type-Options nosniff;

        				# This might create errors
        				proxy_cookie_path / "/; secure; HttpOnly; SameSite=strict";
        			'';

      virtualHosts."${cfg.domain}" = lib.mkMerge [
        cfg.nginx
        {
          inherit (cfg) enableACME;
          forceSSL = lib.mkDefault (if cfg.enableACME then true else false);
          root = lib.mkForce "${invoice-ninja}/public/";
          locations."= /index.php" = {
            extraConfig = ''
              							fastcgi_pass unix:${config.services.phpfpm.pools.invoiceninja.socket};
              							fastcgi_index index.php;
              						'';
          };
          locations."~ \\.php$" = {
            return = 403;
          };
          locations."/" = {
            tryFiles = "$uri $uri/ /index.php?$query_string";
            extraConfig = ''
              							# Add your rewrite rule for non-existent files
              							if (!-e $request_filename) {
              									rewrite ^(.+)$ /index.php?q=$1 last;
              							}
              						'';
          };
          locations."~ /\\.ht" = {
            extraConfig = ''
              							deny all;
              						'';
          };
          extraConfig = ''
            						index index.php index.html index.htm;
            						error_page 404 /index.php;
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
      path = with pkgs; [ bash invoice-ninja-manage rsync ] ++ extraPrograms;

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
                # echo -e '\n' >> ${cfg.dataDir}/.env
                cat "$CREDENTIALS_DIRECTORY/env-secrets" >> ${cfg.dataDir}/.env

                # Link the static storage (package provided) to the runtime storage
                # Necessary for cities.json and static images.
                mkdir -p ${cfg.dataDir}/storage
                rsync -av --no-perms ${invoice-ninja}/storage-static/ ${cfg.dataDir}/storage
                chmod -R +w ${cfg.dataDir}/storage

                chmod g+x ${cfg.dataDir}/storage ${cfg.dataDir}/storage/app
                chmod -R g+rX ${cfg.dataDir}/storage/app/public

                # Link the app.php in the runtime folder.
                # We cannot link the cache folder only because bootstrap folder needs to be writeable.
                ln -sf ${invoice-ninja}/bootstrap-static/app.php ${cfg.runtimeDir}/app.php

        				# Link the static public/images (package provided) to the runtime public/public/images
        				mkdir -p ${cfg.dataDir}/public/images
        				rsync -av --no-perms ${invoice-ninja}/public/images-static/ ${cfg.dataDir}/public/images
        				
        				# Link the static public/react (package provided) to the runtime public/public/react
        				mkdir -p ${cfg.dataDir}/public/react
        				rsync -av --no-perms ${invoice-ninja}/public/react-static/ ${cfg.dataDir}/public/react

        				chmod -R +w ${cfg.dataDir}/public
        				chmod -R g+rwX ${cfg.dataDir}/public
        				
        				# Link the static vite.config.ts (package provided to the runtime vite.config.ts
        				rsync -av --no-perms ${invoice-ninja}/vite.config.ts.static ${cfg.dataDir}/vite.config.ts
        				chmod +w ${cfg.dataDir}/vite.config.ts
        				chmod g+rw ${cfg.dataDir}/vite.config.ts

                invoice-ninja-manage route:cache
                invoice-ninja-manage view:cache
                invoice-ninja-manage config:cache
      '';
    };

    systemd.tmpfiles.rules = [
      # Cache must live across multiple systemd units runtimes.
      "d ${cfg.runtimeDir}/                         0700 ${user} ${group} - -"
      "d ${cfg.runtimeDir}/cache                    0700 ${user} ${group} - -"
    ];
  };
}

