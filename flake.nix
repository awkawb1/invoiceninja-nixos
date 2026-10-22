{
  description = "An Invoice Ninja package and module.";

  nixConfig = {
    extra-substituters = [ "https://invoiceninja-nixos.cachix.org" ];
    extra-trusted-public-keys = [
      "invoiceninja-nixos.cachix.org-1:TmRZaji8FFVjjIw9KZmvLrxMxfP+JDThOyOX04z526A="
    ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

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
      nixosConfigurations = {
        test-nginx = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (import ./tests/default.nix { proxyServer = "nginx"; }) ];
        };
        test-caddy = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ (import ./tests/default.nix { proxyServer = "caddy"; }) ];
        };
      };

      overlays.default = final: prev: { invoiceninja = final.callPackage ./package.nix { }; };

      packages = forEachSystem (system: {
        invoiceninja = pkgsBySystem.${system}.invoiceninja;
        default = pkgsBySystem.${system}.invoiceninja;
      });

      checks = forEachSystem (system: {
        invoiceninja = import ./tests/nixos-test.nix { inherit system; nixpkgsPath = nixpkgs; };
      });

      nixosModules = import ./nixos-module { overlays = overlayList; };
    };
}
