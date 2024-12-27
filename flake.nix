{
  description = "An Invoice Ninja package and a module which can be added to a NixOS configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs =
    { self, nixpkgs, nix, }:
    let
      systems = [ "x86_64-linux" ];
      forEachSystem = nixpkgs.lib.genAttrs systems;

      overlayList = [ self.overlays.default ];

      pkgsBySystem = forEachSystem (
        system:
        import nixpkgs {
          inherit system;
          overlays = overlayList;
        }
      );

    in
    rec {

      # A Nixpkgs overlay that provides a 'Invoice Ninja' package.
      overlays.default = final: prev: { invoice-ninja = final.callPackage ./package.nix { }; };

      packages = forEachSystem (system: {
        invoice-ninja = pkgsBySystem.${system}.invoice-ninja;
        default = pkgsBySystem.${system}.invoice-ninja;
      });

      nixosModules = import ./nixos-module { overlays = overlayList; };

    };
}
