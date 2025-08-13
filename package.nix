{ lib
, php
, openssl
, writers
, fetchFromGitHub
, dataDir ? "/var/lib/invoiceninja"
, runtimeDir ? "/run/invoiceninja"
}:

php.buildComposerProject (finalAttrs: {
  pname = "invoiceninja";
  version = "5.12.13";

  src = fetchFromGitHub {
    owner = "invoiceninja";
    repo = "invoiceninja";
    rev = "v${finalAttrs.version}";
    hash = "sha256-/+dmZUxDeC33bBuM2oZwU9wOVtJY0X5/dkhlpbfLkYg=";
  };

  vendorHash = "sha256-NzFOh3XpKC3Ia1Ns9I6xN9N6y1F5dFSEk7bxq/eKZIc=";

  patches = [
    ./disable-react-for-admin.patch
  ];

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
    ln -s ${dataDir}/storage/app/public $out/public/storage
    ln -s ${runtimeDir} $out/bootstrap
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

