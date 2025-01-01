{ overlays }:

{
  invoiceninja = import ./invoiceninja.nix;
  overlayNixpkgsForThisInstance = 
    { pkgs, ... }: {
      nixpkgs = {
        inherit overlays;
      };
    };
}
