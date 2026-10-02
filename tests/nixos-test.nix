{ nixpkgsPath, system }:

let
  pkgs = import nixpkgsPath { inherit system; };

  adminEmail = "admin@email.com";
  adminPassword = pkgs.lib.strings.trim (builtins.readFile ./invoice_ninja_test_password);
in
pkgs.testers.nixosTest {
  name = "invoiceninja";

  nodes = {
    nginx.imports = [ (import ./common.nix { proxyServer = "nginx"; }) ];
    caddy.imports = [ (import ./common.nix { proxyServer = "caddy"; }) ];
  };

  testScript = ''
    import json

    def api_get(machine, path, token):
        return json.loads(machine.succeed(f"curl -sf http://localhost{path} -H 'X-API-TOKEN: {token}'"))

    def api_post(machine, path, payload, token=None):
        auth_header = f"-H 'X-API-TOKEN: {token}' " if token else ""
        return json.loads(machine.succeed(
            f"curl -sf -X POST http://localhost{path} "
            + auth_header
            + "-H 'Content-Type: application/json' "
            + f"-d '{json.dumps(payload)}'"
        ))

    def check_invoiceninja(machine, proxy_unit):
        machine.wait_for_unit("mysql.service")
        machine.wait_for_unit("redis-invoiceninja.service")
        machine.wait_for_unit("phpfpm-invoiceninja.service")
        machine.wait_for_unit("invoiceninja-queue-worker.service")
        machine.wait_for_unit(proxy_unit)
        machine.wait_for_open_port(80)

        # phpfpm-invoiceninja/invoiceninja-queue-worker both Require= invoiceninja-data-setup,
        # so systemd already waited for it to finish above. Confirm the one-time setup steps
        # it guards actually completed, rather than just that the unit exited. (Migrations run
        # unconditionally on every activation rather than being marker-gated, so there's no
        # marker file to check for them here.)
        with subtest("one-time setup (seed, admin account) completed"):
            machine.succeed("test -f /var/lib/invoiceninja/.db-seeded")
            machine.succeed("test -f /var/lib/invoiceninja/.admin-created")

        with subtest("application shell is served over HTTP"):
            response = machine.succeed("curl -sf http://localhost/")
            assert "Invoice Ninja" in response, f"unexpected response from /: {response}"

        with subtest("web UI login page is served"):
            # The UI is a client-side-routed React SPA, so curl (no JS) only sees the same
            # index.html shell as "/" - this confirms the proxy/Laravel resolve the /login route
            # to that shell instead of 404ing, which is what a browser needs before it can
            # render the actual login form.
            login_page = machine.succeed("curl -sf http://localhost/login")
            assert "Invoice Ninja" in login_page, f"unexpected response from /login: {login_page}"

        with subtest("invoiceninja-manage wrapper can run artisan commands"):
            machine.succeed("invoiceninja-manage migrate:status")

        with subtest("scheduler timer is enabled and schedule:run succeeds"):
            # Without this, the app's dashboard reports "cron jobs are not enabled".
            machine.succeed("systemctl is-active invoiceninja-scheduler.timer")
            machine.succeed("systemctl start --wait invoiceninja-scheduler.service")

        with subtest("admin account can log in via the API"):
            login_response = api_post(machine, "/api/v1/login", {"email": "${adminEmail}", "password": "${adminPassword}"})
            assert "${adminEmail}" in json.dumps(login_response), f"login did not succeed: {login_response}"
            token = login_response["data"][0]["token"]["token"]

        with subtest("full language list is available, not just the af/ca/id migration's 3"):
            # Regression check: migration 2025_08_31_224356_additional_languages_af_ca_id.php runs
            # during `migrate`, before db:seed's LanguageSeeder has populated the other 42 rows, and
            # does Cache::forever('languages', Language::all()) - permanently caching just the 3
            # languages it sees at that moment. invoiceninja-data-setup works around this with
            # `invoiceninja-manage cache:forget languages`; this confirms the workaround is in place.
            language_count = len(api_get(machine, "/api/v1/statics", token)["languages"])
            assert language_count > 40, f"expected ~45 languages, got {language_count}"

        with subtest("PDF generation works (chromium/snappdf)"):
            # /api/v1/preview with no entity falls back to a self-contained mock PDF (no invoice/client
            # setup needed), exercising the same chromium/snappdf pipeline real invoice PDFs use.
            # This fallback only triggers when the company has no invoices/invitations at all yet
            # (PreviewController::blankEntity), so this must run before the client/invoice/payment
            # subtest below creates one.
            machine.succeed(
                "curl -sf -X POST http://localhost/api/v1/preview "
                + f"-H 'X-API-TOKEN: {token}' -H 'Content-Type: application/json' "
                + "-d '{}' -o /tmp/preview.pdf"
            )
            magic_bytes = machine.succeed("head -c 4 /tmp/preview.pdf")
            assert magic_bytes == "%PDF", f"expected a PDF, got: {magic_bytes!r}"

        with subtest("a client can be created, invoiced, and pay that invoice in full"):
            client = api_post(machine, "/api/v1/clients", {"name": "Test Client"}, token)["data"]

            invoice = api_post(machine, "/api/v1/invoices", {
                "client_id": client["id"],
                "line_items": [
                    {"quantity": 1, "cost": 100, "product_key": "test-product", "notes": "test line item"},
                ],
            }, token)["data"]
            assert invoice["amount"] == 100, f"unexpected invoice amount: {invoice}"

            # Mirrors the normal workflow of sending an invoice to a client before it's paid,
            # rather than relying on the fact that draft invoices also happen to be payable.
            api_get(machine, f"/api/v1/invoices/{invoice['id']}/mark_sent", token)

            payment = api_post(machine, "/api/v1/payments", {
                "client_id": client["id"],
                "amount": invoice["amount"],
                "invoices": [{"invoice_id": invoice["id"], "amount": invoice["amount"]}],
            }, token)["data"]
            assert payment["applied"] == invoice["amount"], f"payment not fully applied: {payment}"

            paid_invoice = api_get(machine, f"/api/v1/invoices/{invoice['id']}", token)["data"]
            # status_id 4 == STATUS_PAID
            assert paid_invoice["status_id"] == "4", f"invoice not marked paid: {paid_invoice}"
            assert paid_invoice["balance"] == 0, f"invoice balance not zero: {paid_invoice}"


    nginx.start()
    caddy.start()

    check_invoiceninja(nginx, "nginx.service")
    check_invoiceninja(caddy, "caddy.service")
  '';
}
