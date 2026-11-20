# invoiceninja-nixos

A Nix flake that packages [Invoice Ninja](https://github.com/invoiceninja/invoiceninja) and provides a NixOS
module (`services.invoiceninja`) to deploy it as a full service: PHP-FPM, nginx or Caddy, MariaDB, Redis, a
queue-worker, and a scheduler — all wired together, with headless-Chromium PDF generation included.

This repo is packaging/deployment code only; there's no Invoice Ninja application source here.

## Usage

Add the flake as an input and import the module:

```nix
{
  inputs.invoiceninja.url = "git+https://gitea.awkawb.cloud/awkawb/invoiceninja-nixos.git";

  outputs = { self, nixpkgs, invoiceninja, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        invoiceninja.nixosModules.invoiceninja
        {
          services.invoiceninja = {
            enable = true;
            hostname = "invoice.example.com";

            # Must already exist on the target machine before first switch.
            # Contents: APP_KEY, UPDATE_SECRET, and any other .env values
            # that shouldn't land in the Nix store.
            secretFile = "/root/invoiceninja.env-secrets";

            adminAccount.email = "admin@example.com";
            # Must also already exist on the target machine.
            adminAccount.passwordFile = "/root/invoiceninja.admin-password";
          };
        }
      ];
    };
  };
}
```

By default this provisions MariaDB and Redis locally and serves over nginx. Pass
`services.invoiceninja.proxy.server = "caddy"` to use Caddy instead.

Once deployed, use `invoiceninja-manage <artisan-args>` (added to `environment.systemPackages`) to run Laravel
artisan commands by hand, e.g. `invoiceninja-manage migrate:status` or `invoiceninja-manage ninja:create-account`.

See `nixos-module/invoiceninja.nix` for the full set of options (mail, database, PHP-FPM tuning, upload size
limits, etc.) — most Laravel `.env` keys can also be set directly via the freeform `services.invoiceninja.settings`.

## Developing

This project uses [`just`](https://github.com/casey/just) and Nix directly:

- `just build-vm [nginx|caddy]` — build a click-around test VM.
- `just boot-vm` — boot it; Invoice Ninja is served on `localhost:8080`, root login `toor`.
- `just test` — run the automated test suite (`nix flake check -L`).
- `just update` — bump to the latest upstream invoiceninja/ui versions and recompute hashes.
- `just push-cache` — build and push results to the `invoiceninja-nixos` Cachix cache.

A GitHub Actions workflow (`.github/workflows/update.yml`) runs `just update`/`just push-cache` automatically
every other day against a GitHub mirror of this repo, pushing any version-bump commit back here.

See `CLAUDE.md` for a detailed architecture walkthrough.
