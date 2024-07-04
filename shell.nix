{ pkgs ? import <nixpkgs> { config.allowUnfree = true; }
, lib ? import <nixpkgs/lib>
}:

let
  # Helper script to generate an APP_KEY for .env
  generate-invoice-ninja-app-key = pkgs.writers.writeBashBin "generate-laravel-key" ''
    echo "APP_KEY=base64:$(${pkgs.openssl}/bin/openssl rand -base64 32)"
  '';

  # Invoice Ninja derivation
  # Add to buildInputs to test in nix-shell environment
  invoice-ninja = pkgs.callPackage ./default.nix {
    inherit lib;
    php = pkgs.php;
    openssl = pkgs.openssl;
    fetchFromGitHub = pkgs.fetchFromGitHub;
  };
in
pkgs.mkShell {
  buildInputs = [
    generate-invoice-ninja-app-key
    pkgs.nixpkgs-fmt
  ];
}
  
