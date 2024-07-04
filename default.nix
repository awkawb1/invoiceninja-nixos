{ lib
, php
, openssl
, writers
, fetchFromGitHub
, dataDir ? "/var/lib/invoice-ninja"
, runtimeDir ? "/run/invoice-ninja"
}:

let
  # Helper script to generate an APP_KEY for .env
  generate-invoice-ninja-app-key = writers.writeBashBin "generate-laravel-key" ''
    echo "APP_KEY=base64:$(${openssl}/bin/openssl rand -base64 32)"
  '';
in
php.buildComposerProject (finalAttrs: {
  pname = "invoice-ninja";
  version = "5.10.3";

  src = fetchFromGitHub {
    owner = "invoiceninja";
    repo = "invoiceninja";
    rev = "v${finalAttrs.version}";
    hash = "sha256-QL6L+yT1yRQUTTGYGjaC4zbvzgw4ozgJSP2bYJCf014=";
  };

  vendorHash = "sha256-LGNBgaWWX2a8w9uE3+fVtBDqgbcv69FNnka4HjZKqsQ=";

  propagatedBuildInput = [ generate-invoice-ninja-app-key ];

  # Upstream composer.json has invalid license, webpatser/laravel-countries package is pointing
  # to commit-ref, and php required in require and require-dev
  composerStrictValidation = false;

  postInstall = ''
    mv "$out/share/php/${finalAttrs.pname}"/* $out
    rm -R $out/bootstrap/cache

    # Move static contents for the NixOS module to pick it up, if needed.
    mv $out/bootstrap $out/bootstrap-static
    mv $out/storage $out/storage-static
    mv $out/vite.config.ts $out/vite.config.ts.static
    mv $out/public/images $out/public/images-static
    mv $out/public/react $out/public/react-static

    ln -s ${dataDir}/public/images $out/public/
    ln -s ${dataDir}/public/react $out/public/
    ln -s ${dataDir}/vite.config.ts $out/
    ln -s ${dataDir}/.env $out/.env
    ln -s ${dataDir}/storage $out/
    ln -s ${runtimeDir} $out/bootstrap

    chmod +x $out/artisan
  '';

  meta = {
    description = "Open-source, self-hosted invoicing application";
    homepage = "https://www.invoiceninja.com/";
    license = with lib.licenses; {
      fullName = "Elastic License 2.0";
      shortName = "Elastic-2.0";
      free = false;
    };
    platforms = lib.platforms.all;
  };
})

