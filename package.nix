{ buildNpmPackage
, npmHooks
, fetchFromGitHub
, fetchNpmDeps
, php82
, nodejs_22
, npm-lockfile-fix
, dataDir ? "/var/lib/invoiceninja"
, runtimeDir ? "/run/invoiceninja"
}:

let
  pname = "invoiceninja";

  version = "5.13.19";
  src = fetchFromGitHub {
    name = "${pname}";
    owner = pname;
    repo = pname;
    rev = "v${version}";
    hash = "sha256-pvZNTiGGX6OqOEqcDrDqqpLD1Ohc/TA4nIRjm2jEp74=";

    postFetch = ''
      # add missing integrity fields to lockfile
      ${npm-lockfile-fix}/bin/npm-lockfile-fix $out/package-lock.json
    '';
  };

  uiVersion = "03.05.2026.1";
  uiSrc = fetchFromGitHub {
    name = "${pname}-ui";
    owner = pname;
    repo = "ui";
    tag = uiVersion;
    hash = "sha256-BTaWNHTE+9NvavUYs56DdJHmqXy36N5k/crj3rU2Npg=";

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
  
    npmDepsHash = "sha256-JA5TfXeg7iHVjQdjeU6SSD2JFSLISad8hPowaR1roQw=";

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

  nativeBuildInputs = [
    nodejs_22
    npmHooks.npmConfigHook
    npmHooks.npmBuildHook
  ];

  vendorHash = "sha256-2CyWKlyCyoCt/WdY7Ta0oEXW2KIkGwhilHtzpBJ5Wnk=";

  # Upstream composer.json has invalid license, webpatser/laravel-countries package is pointing
  # to commit-ref, and php required in require and require-dev
  composerStrictValidation = false;

  CYPRESS_INSTALL_BINARY = 0;

  npmDeps = fetchNpmDeps {
    name = "${pname}-${version}-npm-deps";
    inherit src;
    hash = "sha256-WCadsQVj9eusYWJEOaEp5DIkVcbmPFGe6bmKi9NZDDg=";
  };

  preConfigure = ''
    cp -r ${ui}/dist/* public/
    cp public/index.html resources/views/react/index.blade.php
  '';

  postInstall = ''
    mv "$out/share/php/${finalAttrs.pname}"/* $out

    # Remove JS/CSS build artifacts
    rm -rf $out/node_modules

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
