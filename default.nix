{ lib
, php
, openssl
, writers
, fetchFromGitHub
, dataDir ? "/var/lib/invoice-ninja"
, runtimeDir ? "/run/invoice-ninja"
}:

php.buildComposerProject (finalAttrs: {
  pname = "invoice-ninja";
  version = "5.10.29";

  src = fetchFromGitHub {
    owner = "invoiceninja";
    repo = "invoiceninja";
    rev = "v${finalAttrs.version}";
    hash = "sha256-nhLt3DXW0q07ZhDq23mHwbVmqHZor+p925/yrKXum54=";
  };

  vendorHash = "sha256-NVvx1aKhbC5XuXt2+gS2c3ulNWoCKrYNnEleBuAcftQ=";

  # Patch sources to allow more restrictive permissions
  # patches = [ ./config-filesystems.patch ];

  # Upstream composer.json has invalid license, webpatser/laravel-countries package is pointing
  # to commit-ref, and php required in require and require-dev
  composerStrictValidation = false;

  postInstall = ''
    mv "$out/share/php/${finalAttrs.pname}"/* $out
    rm -R $out/bootstrap/cache

    rm -rf $out/public/storage

    # Move static contents for the NixOS module to pick it up, if needed.
    mv $out/bootstrap $out/bootstrap-static
    mv $out/storage $out/storage-static

    # Link NixOS module files to derivation output
    ln -s ${dataDir}/.env $out/.env
    ln -s ${dataDir}/storage $out/
    ln -s ${runtimeDir} $out/bootstrap
    ln -s ${dataDir}/storage/app/public $out/public/storage
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

