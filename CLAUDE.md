# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Nix flake that packages [Invoice Ninja](https://github.com/invoiceninja/invoiceninja) (a PHP/Laravel app with a
separate React frontend) and provides a NixOS module (`services.invoiceninja`) to deploy it as a full service:
PHP-FPM pool, nginx or Caddy reverse proxy, MariaDB, Redis, a queue-worker systemd unit, and a one-shot
migration/setup unit.

There is no application source code here — this is packaging/deployment code only. All behavior changes come from
editing Nix expressions.

## Commands

This project uses `just` (see `justfile`) and Nix directly.

- `just build-vm [proxy]` — cleans previous artifacts and builds the test VM (`nixosConfigurations.test-<proxy>`)
  via `nom build`. `proxy` is `nginx` (default) or `caddy`.
- `just boot-vm` — boots the built VM (`result/bin/run-nixos-vm`) in the current terminal. Serves Invoice Ninja on
  `localhost:8080` (see `QEMU_NET_OPTS` in the `justfile`) with root login `toor`.
- `just clean` — removes `result`/`nixos.qcow2` and kills any running `qemu` process.
- `just test` — runs the automated test suite (`nix flake check -L`).
- `nix build .#invoiceninja` — build just the Invoice Ninja package.
- `nix build .#checks.x86_64-linux.invoiceninja -L` — run only the automated VM test, with build/test log output.
- `nix flake check` — evaluate the flake (module options, overlay, package derivation) and run the automated test.

### `tests/`

- `common.nix` — the shared `services.invoiceninja` config used by both the interactive VM and the automated test:
  imports the module and points at the checked-in test fixtures (`invoice_ninja_test_password`, `test.env`). It's a
  function taking `{ proxyServer ? "nginx" }` so callers can pick which proxy backend to test.
- `default.nix` — the interactive VM config (`nixosConfigurations.test-nginx`/`test-caddy` in `flake.nix`), used
  for manual, click-around verification via `just build-vm [proxy]` / `just boot-vm`. It's also a function taking
  `{ proxyServer ? "nginx" }`, forwarded straight through to `common.nix`, so `flake.nix` can instantiate one
  `nixosConfigurations` entry per proxy backend. Adds the qemu-guest profile, a root login, and
  `nixpkgs.config.allowUnfree = true` (required to build `pkgs.chromium`). It also sets a dummy `fileSystems."/"`
  and disables `boot.loader.grub` purely to satisfy NixOS's built-in assertions when `nix flake check` evaluates
  `config.system.build.toplevel` directly — the qemu-vm module overrides both with a tmpfs root and direct kernel
  boot when actually building `config.system.build.vm` (what `just build-vm` uses), so these values are otherwise
  unused.
- `nixos-test.nix` — the automated test (`pkgs.testers.nixosTest`, exposed as `checks.<system>.invoiceninja` in
  `flake.nix`). Builds its own `pkgs` (with `allowUnfree` baked in — `nixosTest` forbids setting `nixpkgs.config`
  on a node once `pkgs` is externally supplied) and boots two nodes from `common.nix` — one with
  `proxyServer = "nginx"`, one with `proxyServer = "caddy"` — so both proxy backends get exercised. The shared
  assertion suite (factored into a `check_invoiceninja(machine, proxy_unit)` function in the test script) runs
  against each node: waits for mysql/redis/phpfpm/queue-worker/proxy to be active, checks the
  `invoiceninja-data-setup` marker files (`.initial-migration`, `.db-seeded`, `.admin-created`) to confirm the
  one-time setup actually completed (not just that the oneshot unit exited), curls `/` for the app shell, exercises
  the `invoiceninja-manage` wrapper, and logs in via `/api/v1/login` using the test admin credentials as an
  end-to-end check that migrations/seeding/account creation all worked. This is the only automated test in the
  repo — there is no separate unit-test suite.

## Architecture

### `package.nix`

Builds Invoice Ninja in two stages:

1. **`ui`** — the separate `invoiceninja/ui` React frontend repo, built with `buildNpmPackage`. Patches
   `.env.example` to disable test mode and swaps in `vite.config.ts.react` before building.
2. **Main package** — built with `php82.buildComposerProject` from the `invoiceninja/invoiceninja` PHP repo. The
   `ui` build's `dist/` output is copied into `public/` before the PHP build (`preConfigure`), and
   `public/index.html` is copied to `resources/views/react/index.blade.php` so Laravel serves the React shell.

Both source fetches (`fetchFromGitHub`) run their lockfiles through `npm-lockfile-fix` in `postFetch` to patch
missing integrity fields — required for `fetchNpmDeps`/`buildNpmPackage` to work with these upstream lockfiles.

Because Laravel needs writable directories that can't live in the read-only Nix store, `postInstall` renames
`bootstrap` → `bootstrap-static` and `storage` → `storage-static` inside the derivation, then symlinks
`$out/.env`, `$out/storage`, `$out/public/storage`, and `$out/bootstrap` to paths under the module's `dataDir` /
`runtimeDir`. This means **the package output is only fully functional when paired with the NixOS module** (or
something else that populates those runtime paths the same way) — building the package alone will produce
dangling symlinks.

When bumping the Invoice Ninja or UI version in `package.nix`, all four hashes (`src.hash`, `uiSrc.hash`,
`ui`'s `npmDepsHash`, and the main package's `vendorHash`/`npmDeps.hash`) generally need to be recomputed —
expect Nix to report the correct hash on a failed build (or use `nix-prefetch`/`lib.fakeHash` workflow).

### `nixos-module/`

- `default.nix` — the flake's `nixosModules` output. Exposes the `invoiceninja` module and a small
  `overlayNixpkgsForThisInstance` module that applies the flake's overlay (registers `pkgs.invoiceninja`) to
  whatever nixpkgs instance imports it.
- `invoiceninja.nix` — the actual `services.invoiceninja` module. Key structural points:
  - `cfg.settings` is a submodule with a `freeformType` (`pkgs.formats.keyValue`), so any Laravel `.env` key can be
    set even if not explicitly declared as an option; explicitly declared options (APP_ENV, MAIL_MAILER,
    SESSION_DRIVER, etc.) exist mainly to add type-checking/enums and sensible computed defaults (e.g.
    SESSION_DRIVER/QUEUE_CONNECTION/CACHE_DRIVER default to redis → database → file depending on what's enabled).
  - **Secrets are deliberately kept out of `cfg.settings`/the Nix store.** `secretFile` (required) and
    `adminAccount.passwordFile` (required) are consumed via systemd `LoadCredential` in the
    `invoiceninja-data-setup` service, not written into the generated `.env` derivation. The final `.env` is
    assembled at activation time by concatenating the Nix-store-rendered non-secret settings with the secret file
    contents directly on disk in `dataDir`.
  - `invoiceninja-data-setup.service` (oneshot, runs on every activation) does all first-run and idempotent setup:
    clears bootstrap/opcode cache, rebuilds `.env`, rsyncs static storage into `dataDir`, symlinks the runtime
    `app.php`, and guards one-time actions (`migrate`, `db:seed`, admin account creation) behind marker files
    (`.initial-migration`, `.db-seeded`, `.admin-created`) in `dataDir`. `phpfpm-invoiceninja.service` and
    `invoiceninja-queue-worker.service` both depend on it.
  - `invoiceninja-scheduler.timer`/`.service` run `artisan schedule:run` every minute — this is what drives
    Invoice Ninja's own internal cron-scheduled jobs (recurring invoices, scheduled reports, etc.); without it the
    app's dashboard reports "cron jobs are not enabled". Laravel's scheduler is just a dispatcher, so this one
    timer is sufficient regardless of how many scheduled tasks Invoice Ninja itself defines.
  - `invoiceninja-manage` is a generated wrapper script (`invoiceninja-manage <artisan-args>`) that `cd`s into the
    package output and runs `php artisan` as the configured service user (via `sudo` if invoked as another user).
    It's added to `environment.systemPackages`, so it's the normal way to run artisan commands
    (`migrate`, `queue:work`, `ninja:create-account`, etc.) by hand on a deployed system.
  - Both `nginx` and `caddy` proxy backends are supported (`proxy.server`), each independently duplicating the
    PHP-FPM passthrough config — if changing one, check whether the other needs the same change. Neither sets
    CORS headers itself: Laravel's own CORS middleware already sends a complete set on every response, and an
    earlier version of this module additionally set a second, static set of `Access-Control-*` headers at the
    proxy level, which browsers reject as conflicting duplicates (server-to-server/curl checks don't notice,
    since only browsers enforce CORS header validation).
  - Caddy matches vhosts on the exact `Host` header, unlike nginx (where a single vhost acts as the default
    regardless of `Host`). When `hostname == "localhost"`, the caddy vhost adds `serverAliases` for
    `127.0.0.1:80`/`[::1]:80` too — otherwise visiting the VM via the IP literal instead of `localhost` matches no
    vhost and Caddy silently returns an empty `200 OK` (a blank page with no error anywhere).
  - Chromium is required at runtime for PDF generation (`PDF_GENERATOR=snappdf`, `SNAPPDF_CHROMIUM_PATH`) and is
    added to the PHP-FPM and data-setup services' `path`.

### `flake.nix`

Standard flake shape: `overlays.default` registers the package, `packages.<system>.invoiceninja` exposes it,
`nixosModules` re-exports `nixos-module/default.nix`, and `nixosConfigurations.test-nginx`/`test-caddy` each build
the VM defined in `tests/default.nix` with the corresponding `proxyServer`. Only `x86_64-linux` is currently
supported.

## Conventions

- Nix files: 2-space indentation (see `.editorconfig`); Unix line endings; final newline required.
- Prefer `lib.mkDefault`/`lib.mkIf`/`lib.mkMerge` for module config so downstream users can override cleanly —
  this is used pervasively in `invoiceninja.nix` and should be followed for new options/config.
