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
  version = "5.10.34";

  src = fetchFromGitHub {
    owner = "invoiceninja";
    repo = "invoiceninja";
    rev = "v${finalAttrs.version}";
    hash = "sha256-2lR2lT8TbDcJ0m3C2ZwdbICPJGSlF9U7I+RC8MxvtOY=";
  };

  vendorHash = "sha256-Z9gEjZqn8Ew2EnUNyD1dfjt0y+Y+5VjH/q1oFErrorg=";

  # Patch sources for more restrictive permissions
  patches = [
    ./fix-storage-permissions.patch
    ./disable-react-for-admin.patch

    # FIXME this patch should fix "Health Check" file permissions errors
    #./fix-base-permissions.patch
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

