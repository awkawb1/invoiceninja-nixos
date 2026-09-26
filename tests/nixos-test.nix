{ nixpkgsPath, system }:

let
  # nixosTest forbids setting `nixpkgs.config` on a node once `pkgs` is externally supplied,
  # so allowUnfree (required to build pkgs.chromium) has to be baked into this pkgs instance
  # up front rather than set from within common.nix like the interactive VM does.
  pkgs = import nixpkgsPath {
    inherit system;
    config.allowUnfree = true;
  };

  adminEmail = "admin@email.com";
  adminPassword = pkgs.lib.strings.trim (builtins.readFile ./invoice_ninja_test_password);
in
pkgs.testers.nixosTest {
  name = "invoiceninja";

  nodes.machine = {
    imports = [ ./common.nix ];
  };

  testScript = ''
    machine.start()

    machine.wait_for_unit("mysql.service")
    machine.wait_for_unit("redis-invoiceninja.service")
    machine.wait_for_unit("phpfpm-invoiceninja.service")
    machine.wait_for_unit("invoiceninja-queue-worker.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(80)

    # phpfpm-invoiceninja/invoiceninja-queue-worker both Require= invoiceninja-data-setup,
    # so systemd already waited for it to finish above. Confirm the one-time setup steps
    # it guards actually completed, rather than just that the unit exited.
    with subtest("one-time setup (migrate, seed, admin account) completed"):
        machine.succeed("test -f /var/lib/invoiceninja/.initial-migration")
        machine.succeed("test -f /var/lib/invoiceninja/.db-seeded")
        machine.succeed("test -f /var/lib/invoiceninja/.admin-created")

    with subtest("application shell is served over HTTP"):
        response = machine.succeed("curl -sf http://localhost/")
        assert "Invoice Ninja" in response, f"unexpected response from /: {response}"

    with subtest("web UI login page is served"):
        # The UI is a client-side-routed React SPA, so curl (no JS) only sees the same
        # index.html shell as "/" - this confirms nginx/Laravel resolve the /login route
        # to that shell instead of 404ing, which is what a browser needs before it can
        # render the actual login form.
        login_page = machine.succeed("curl -sf http://localhost/login")
        assert "Invoice Ninja" in login_page, f"unexpected response from /login: {login_page}"

    with subtest("invoiceninja-manage wrapper can run artisan commands"):
        machine.succeed("invoiceninja-manage migrate:status")

    with subtest("admin account can log in via the API"):
        login_response = machine.succeed(
            "curl -sf -X POST http://localhost/api/v1/login "
            + "-H 'Content-Type: application/json' "
            + "-d '{\"email\":\"${adminEmail}\",\"password\":\"${adminPassword}\"}'"
        )
        assert "${adminEmail}" in login_response, f"login did not succeed: {login_response}"
  '';
}
