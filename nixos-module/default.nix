{ overlays }:

{
  invoice-ninja = import ./invoice-ninja.nix;
  overlayNixpkgsForThisInstance = 
    { pkgs, ... }: {
      nixpkgs = {
        inherit overlays;
      };
    };
}
