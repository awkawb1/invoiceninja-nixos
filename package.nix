{ lib
, buildNpmPackage
, npmHooks
, fetchFromGitHub
, fetchNpmDeps
, jq
, php82
, nodejs_22
, npm-lockfile-fix
, dataDir ? "/var/lib/invoiceninja"
, runtimeDir ? "/run/invoiceninja"
}:

let
  pname = "invoiceninja";

  version = "5.13.53";
  src = fetchFromGitHub {
    name = "${pname}";
    owner = pname;
    repo = pname;
    rev = "v${version}";
    hash = "sha256-KQMb1W2S1YrRZOgjV3NPDpQaz5BbF/xtziNFd34wvxo=";

    postFetch = ''
      # add missing integrity fields to lockfile
      ${npm-lockfile-fix}/bin/npm-lockfile-fix $out/package-lock.json
    '';
  };

  uiVersion = "18.10.2026.1";
  uiSrc = fetchFromGitHub {
    name = "${pname}-ui";
    owner = pname;
    repo = "ui";
    tag = uiVersion;
    hash = "sha256-56szHmIWU9De04Orykp2RxrW0RV87JxB7Y1yvdrSJm4=";

    postFetch = ''
      # add missing integrity fields to lockfile
      ${npm-lockfile-fix}/bin/npm-lockfile-fix $out/package-lock.json
    '';
  };
  
  # React frontend
  ui = buildNpmPackage {
    pname = "${pname}-ui";
    version = uiVersion;
    src = uiSrc;

    nodejs = nodejs_22;
  
    npmDepsHash = "sha256-j5XocHvBfMvzNrkaVkTsck2+yPraYWrXQxAbf3EYfIk=";

    preConfigure = ''
      sed -i 's/VITE_IS_TEST=true/VITE_IS_TEST=false/' .env.example

      cp .env.example .env
      cp ${src}/vite.config.ts.react ./vite.config.js
    '';

    installPhase = ''
      runHook preInstall

      mkdir $out
      cp -a * $out

      runHook postInstall
    '';
  };
in

php82.buildComposerProject (finalAttrs: {
  inherit src version;
  pname = "${pname}-composer";

  passthru.ui = ui;

  nativeBuildInputs = [
    jq
    nodejs_22
    npmHooks.npmConfigHook
    npmHooks.npmBuildHook
  ];

  vendorHash = "sha256-sFpfnCt8jv8z9cLoFE8utPQiGz7q/KkqUXabEhcJP3M=";

  # Upstream composer.json has invalid license, webpatser/laravel-countries package is pointing
  # to commit-ref, and php required in require and require-dev
  composerStrictValidation = false;

  CYPRESS_INSTALL_BINARY = 0;

  npmDeps = fetchNpmDeps {
    name = "${pname}-${version}-npm-deps";
    inherit src;
    hash = "sha256-ditAbluBzs5OV/fCMV5Q4w1amao6ofOlee4YXMpZ37I=";
  };

  preConfigure = ''
    cp -r ${ui}/dist/* public/
    cp public/index.html resources/views/react/index.blade.php
  '';

  postInstall = ''
    mv "$out/share/php/${finalAttrs.pname}"/* $out

    # Remove JS/CSS build artifacts
    rm -rf $out/node_modules

    # composer.lock and vendor/composer/installed.json record each package's "dist.url" as the
    # store path of the composer-repository mirror it was installed from, which otherwise drags
    # that whole (500+MB) fixed-output derivation into the runtime closure for no reason -- it's
    # provenance metadata, not something Laravel's package manifest (which only reads
    # name/extra) or Composer\InstalledVersions (which reads vendor/composer/installed.php, not
    # this file) consult at runtime.
    jq '(.packages[]?.dist.url) |= "removed"' $out/vendor/composer/installed.json > $out/vendor/composer/installed.json.tmp
    mv $out/vendor/composer/installed.json.tmp $out/vendor/composer/installed.json
    jq '(.packages[]?.dist.url, .["packages-dev"][]?.dist.url) |= "removed"' $out/composer.lock > $out/composer.lock.tmp
    mv $out/composer.lock.tmp $out/composer.lock

    rm -r $out/bootstrap/cache
    rm -rf $out/public/storage

    # Move static contents for the NixOS module to pick it up, if needed.
    mv $out/bootstrap $out/bootstrap-static
    mv $out/storage $out/storage-static

    # Link NixOS module files to derivation output
    ln -s ${dataDir}/.env $out/.env
    ln -s ${dataDir}/storage $out/
    ln -s ${dataDir}/storage/app/public $out/public/storage
    ln -s ${runtimeDir} $out/bootstrap
  '';
})
