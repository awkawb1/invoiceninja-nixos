{
  description = "An Invoice Ninja package and module.";

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
      nixosConfigurations.test = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./tests ];
      };

      overlays.default = final: prev: { invoice-ninja = final.callPackage ./package.nix { }; };

      packages = forEachSystem (system: {
        invoiceninja = pkgsBySystem.${system}.invoiceninja;
        default = pkgsBySystem.${system}.invoiceninja;
      });

      nixosModules = import ./nixos-module { overlays = overlayList; };
    };
}
