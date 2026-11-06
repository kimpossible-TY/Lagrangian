"""Isolated Homepage security, inventory and installed-asset contracts."""
from concurrent.futures import ThreadPoolExecutor
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
import re
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flow_reader.services.homepage import LOOPBACK_HOST, HomeInventory, reader_url
from flow_reader.services.home_account import HomeAccount
from flow_reader.services.chat_auth import ChatProviderError
from flow_reader.server.home import handler_for_home, home_assets, claim_host
from flow_reader.server.assets import reader_assets


class FakeAuth:
    def __init__(self, directory):
        self.path = directory / "fake-credentials.json"
        self.signed_in, self.pending, self.notice = False, False, ""
        self.calls = []

    def status(self):
        return {"signedIn": self.signed_in, "planEnabled": self.signed_in,
                "active": "private-registration", "accounts": [{"id": "private-registration", "label": "private@example.invalid"}],
                "pending": self.pending, "notice": self.notice}

    def login(self, registration=None):
        self.calls.append("login")
        self.pending = True
        return {"authUrl": "https://auth.openai.com/authorize?state=fake-state"}

    def close(self):
        self.calls.append("cancel")
        self.pending = False

    def logout(self):
        self.calls.append("logout")
        self.pending = self.signed_in = False
        self.notice = "Signed out locally. Remote revocation was not confirmed."
        return {"notice": self.notice, "revocationConfirmed": False}


class FakeProvider:
    def __init__(self):
        self.calls = 0
        self.fail = False

    def models(self):
        self.calls += 1
        if self.fail:
            raise ChatProviderError("Sign in again")
        return [{"id": "fixture-model", "label": "Fixture model"}]


class FakeManager:
    def __init__(self):
        self.mode = "ready"
        self.reads = 0

    def parent_profiles(self):
        self.reads += 1
        if self.mode == "error":
            raise ValueError("/private/source/secret.typ")
        if self.mode == "empty":
            return []
        return [{"id": "p1", "name": "편미분방정식", "port": 25001, "root": "/private/source",
                 "publicURL": "https://paged.example"},
                {"id": "p2", "name": "기하와 역학", "port": 25002, "publicURL": "javascript:alert(1)"}]

    def profiles(self):
        if self.mode == "empty":
            return []
        return [{"id": "html1", "parentID": "p1", "port": 25003, "publicURL": "https://html.example"}]

    def job_pid(self, _profile, **_kwargs):
        return None if self.mode == "stopped" else 42

    def request(self, *_args, **_kwargs):
        if self.mode == "timeout":
            raise TimeoutError()
        return {"revision": "accepted" if self.mode != "unavailable" else None,
                "compiling": self.mode == "compiling"}


class HomeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="home-tests-")
        self.addCleanup(self.temp.cleanup)
        self.auth = FakeAuth(Path(self.temp.name))
        self.provider = FakeProvider()
        self.now = 1000
        self.account = HomeAccount(self.auth, self.provider, clock=lambda: self.now)
        self.inventory = HomeInventory(FakeManager(), interval=30)
        self.inventory.started = time.time()
        self.addCleanup(self.inventory.close)
        self.servers = {}
        for ingress in ("admin", "proxy"):
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for_home(
                self.inventory, self.account, ingress=ingress, public_origin="https://home.example:8443", capability="host-proof"))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.servers[ingress] = server
            self.addCleanup(lambda s=server, t=thread: (s.shutdown(), s.server_close(), t.join()))

    def request(self, method="GET", path="/api/home/account", *, ingress="admin", headers=None, body=None):
        server = self.servers[ingress]
        origin = f"http://127.0.0.1:{server.server_port}" if ingress == "admin" else "https://home.example:8443"
        fields = {"Host": origin.split("//")[1], "Origin": origin, "Content-Type": "application/json"}
        if ingress == "admin" and headers and "Cookie" in headers and (method == "GET" or "X-Reader-CSRF" in headers):
            fields["X-Reader-Host-Capability"] = "host-proof"
        fields.update(headers or {})
        if fields.get("Origin") is None:
            fields.pop("Origin")
        connection = HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        connection.request(method, path, body=json.dumps(body or {}) if method == "POST" else None, headers=fields)
        response = connection.getresponse()
        payload, out = response.read(), dict(response.getheaders())
        connection.close()
        return response.status, payload, out

    def unlock(self, ingress="admin"):
        status, raw, headers = self.request("POST", "/api/home/session", ingress=ingress,
            headers={"X-Reader-Host-Capability": "host-proof"} if ingress == "admin" else {})
        self.assertEqual(status, 200)
        return headers["Set-Cookie"].split(";")[0], json.loads(raw)

    def test_static_root_is_independent_and_document_routes_stay_document(self):
        self.assertIn(b"\xec\x83\x9d\xea\xb0\x81", self.request(path="/")[1])
        self.assertEqual(self.request(path="/index.html")[0], 200)
        for path in ("/document.html", "/service-worker.js", "/auth/callback?code=fake", "/api/offline"):
            self.assertEqual(self.request(path=path)[0], 404)
        self.assertEqual(self.auth.calls, [])
        self.assertEqual(self.provider.calls, 0)
        self.assertNotEqual(home_assets()["/"], reader_assets()["/"][0])
        actual = reader_assets()["/"][0].read_text()
        homepage = home_assets()["/"].read_text()
        pattern = r'class="reader-logo-base".*?d="([^"]+)"'
        self.assertEqual(re.search(pattern, actual, re.S)[1], re.search(pattern, homepage, re.S)[1])

    def test_exact_host_origin_and_proxy_locality(self):
        for host in ("attacker.invalid", "127.0.0.1", "home.example", "home.example:8443@attacker.invalid"):
            self.assertEqual(self.request(headers={"Host": host})[0], 421)
        for origin in (None, "null", "https://attacker.invalid", "http://127.0.0.1:1", "https://home.example:8443/"):
            self.assertEqual(self.request("POST", "/api/home/session", headers={"Origin": origin})[0], 403)
        cookie, proof = self.unlock()
        for field in ("Forwarded", "X-Forwarded-For", "X-Forwarded-Host", "X-Forwarded-Proto", "Tailscale-User-Login"):
            self.assertEqual(self.request("POST", headers={"Cookie": cookie, "X-Reader-CSRF": proof["csrf"], field: ""}, body={"operation": "login"})[0], 403)
        for ingress in ("admin", "proxy"):
            self.assertEqual(self.request("POST", ingress=ingress, headers={"Cookie": cookie, "X-Reader-CSRF": proof["csrf"]}, body={"operation": "login"})[0], 200 if ingress == "admin" else 403)

    def test_duplicate_host_and_origin_rejected(self):
        server = self.servers["admin"]
        connection = HTTPConnection("127.0.0.1", server.server_port)
        connection.putrequest("GET", "/", skip_host=True)
        connection.putheader("Host", f"127.0.0.1:{server.server_port}")
        connection.putheader("Host", "attacker.invalid")
        connection.endheaders()
        response = connection.getresponse()
        self.assertEqual(response.status, 421)
        response.read(); connection.close()
        connection = HTTPConnection("127.0.0.1", server.server_port)
        connection.putrequest("POST", "/api/home/session")
        connection.putheader("Origin", f"http://127.0.0.1:{server.server_port}")
        connection.putheader("Origin", f"http://127.0.0.1:{server.server_port}")
        connection.putheader("Content-Type", "application/json")
        connection.putheader("Content-Length", "2")
        connection.endheaders(b"{}")
        response = connection.getresponse()
        self.assertEqual(response.status, 403)
        response.read(); connection.close()

    def test_sessions_csrf_rotation_expiry_and_no_remote_identity(self):
        cookie, proof = self.unlock()
        self.assertEqual(len(proof["csrf"]), 43)
        self.assertIsNone(self.account.session(cookie.split("=")[1], "admin", "http://127.0.0.1:1"))
        transport = self.request("POST", "/api/home/session")[2]["Set-Cookie"]
        for attribute in ("Path=/api/home/", "HttpOnly", "SameSite=Strict"):
            self.assertIn(attribute, transport)
        self.assertNotIn("Domain=", transport)
        self.assertNotIn("Secure", transport)
        for csrf in ("", "incorrect"):
            self.assertEqual(self.request("POST", headers={"Cookie": cookie, "X-Reader-CSRF": csrf}, body={"operation": "logout"})[0], 403)
        cookie, proof = self.unlock()
        headers = {"Cookie": cookie, "X-Reader-CSRF": proof["csrf"]}
        status, _, result = self.request("POST", headers=headers, body={"operation": "login"})
        self.assertEqual(status, 200)
        self.assertNotEqual(result["Set-Cookie"].split(";")[0], cookie)
        self.assertEqual(self.request("POST", headers=headers, body={"operation": "cancel"})[0], 403)
        cookie, proof = self.unlock()
        self.now += 901
        self.assertEqual(self.request("POST", headers={"Cookie": cookie, "X-Reader-CSRF": proof["csrf"]}, body={"operation": "logout"})[0], 403)
        remote, remote_proof = self.unlock("proxy")
        self.assertFalse(remote_proof["management"])
        copied = "ReaderHomeAdmin=" + remote.split("=")[1]
        self.assertEqual(self.request("POST", headers={"Cookie": copied, "X-Reader-CSRF": remote_proof["csrf"]}, body={"operation": "login"})[0], 403)
        self.assertIn("Secure", self.request("POST", "/api/home/session", ingress="proxy")[2]["Set-Cookie"])
        self.assertEqual(self.request("POST", headers={"Cookie": remote, "X-Reader-CSRF": remote_proof["csrf"]}, body={"operation": "login"})[0], 403)
        for ingress in ("admin", "proxy"):
            raw = self.request(ingress=ingress)[1]
            for secret in (b"private-registration", b"private@example", b"access_token", b"host-proof"):
                self.assertNotIn(secret, raw)

    def test_logout_invalidates_every_tab_and_reports_unconfirmed_revocation(self):
        self.auth.signed_in = True
        cookie, proof = self.unlock()
        other, _ = self.unlock()
        result = self.request("POST", headers={"Cookie": cookie, "X-Reader-CSRF": proof["csrf"]}, body={"operation": "logout"})
        self.assertFalse(json.loads(result[1])["revocationConfirmed"])
        self.assertFalse(self.auth.pending)
        self.assertFalse(self.account.sessions)
        self.assertIn("Max-Age=0", result[2]["Set-Cookie"])
        self.assertNotIn(other.split("=")[1], self.account.sessions)

    def test_read_only_session_flood_cannot_evict_or_rotate_management(self):
        cookie, proof = self.unlock()
        handle = cookie.split("=")[1]
        for _ in range(257):
            status, raw, headers = self.request("POST", "/api/home/session", ingress="proxy",
                headers={"Cookie": "__Secure-ReaderHomeView=" + handle})
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(raw)["csrf"], "")
            self.assertFalse(json.loads(raw)["management"])
            self.assertIn("Max-Age=0", headers["Set-Cookie"])
        # Even an unprivileged admin request carrying a copied handle cannot
        # remove the existing management session.
        self.request("POST", "/api/home/session", headers={"Cookie": cookie})
        self.assertEqual(set(self.account.sessions), {handle})
        self.assertTrue(json.loads(self.request(headers={"Cookie": cookie})[1])["management"])
        self.assertEqual(self.request("POST", headers={"Cookie": cookie, "X-Reader-CSRF": proof["csrf"]},
            body={"operation": "cancel"})[0], 200)

    def test_sessions_are_invisible_across_ingress_even_with_matching_origin(self):
        origin = "https://same.example"
        # Exercise binding independently of the HTTP cookie names/authorities.
        admin, _ = self.account.create("", "admin", origin, manage=True)
        proxy, proof = self.account.create(admin, "proxy", origin)
        self.assertEqual(proxy, "")
        self.assertFalse(proof["management"])
        self.assertIsNone(self.account.session(admin, "proxy", origin))
        self.assertIsNone(self.account.session(proxy, "admin", origin))
        self.assertIsNotNone(self.account.session(admin, "admin", origin))
        other, _ = self.account.create(admin, "proxy", origin, manage=True)
        self.assertIsNone(self.account.session(other, "admin", origin))
        self.assertIsNotNone(self.account.session(other, "proxy", origin))
        self.assertIsNotNone(self.account.session(admin, "admin", origin))
        for ingress, cookie in (("proxy", "__Secure-ReaderHomeView=" + admin),
                                ("admin", "ReaderHomeAdmin=" + other)):
            result = json.loads(self.request(ingress=ingress, headers={"Cookie": cookie})[1])
            self.assertFalse(result["management"])
            self.assertNotIn("accounts", result)

    def test_proxy_catalog_fetch_does_not_block_status_or_management(self):
        entered, release = threading.Event(), threading.Event()
        original = self.provider.models

        def blocked_models():
            entered.set()
            if not release.wait(5):
                raise TimeoutError("fixture catalog was not released")
            return original()

        self.provider.models = blocked_models
        cookie, proof = self.unlock()
        with ThreadPoolExecutor(max_workers=2) as pool:
            catalog = pool.submit(self.request, path="/api/home/models", ingress="proxy")
            try:
                self.assertTrue(entered.wait(1))
                status = pool.submit(self.request, headers={"Cookie": cookie}).result(timeout=1)
                self.assertTrue(json.loads(status[1])["management"])
                mutation = pool.submit(self.request, "POST", headers={"Cookie": cookie,
                    "X-Reader-CSRF": proof["csrf"]}, body={"operation": "cancel"}).result(timeout=1)
                self.assertEqual(mutation[0], 200)
                self.assertFalse(catalog.done())
            finally:
                release.set()
            result = json.loads(catalog.result(timeout=2)[1])
        self.assertEqual(result["state"], "available")
        self.assertEqual(result["version"], json.loads(mutation[1])["version"])

    def test_configured_loopback_url_matches_exact_admin_authority(self):
        server = self.servers["admin"]
        configured = reader_url(f"http://{LOOPBACK_HOST}:{server.server_port}")
        self.assertEqual(configured, f"http://{LOOPBACK_HOST}:{server.server_port}/")
        self.assertEqual(self.request(path="/", headers={"Host": configured.split("/")[2]})[0], 200)
        for host in ("localhost", "[::1]"):
            self.assertIsNone(reader_url(f"http://{host}:{server.server_port}/"))
            self.assertEqual(self.request(headers={"Host": f"{host}:{server.server_port}"})[0], 421)
        self.inventory.observe()
        self.assertTrue(all(reader_url(v["local"]) == v["local"]
                            for d in self.inventory.documents for v in d["variants"]))
        # The common link adapter must be delivered on both independent origins.
        self.assertEqual(home_assets()["/ui/reader-links.js"], reader_assets()["/ui/reader-links.js"][0])
        self.assertEqual(self.request(path="/ui/reader-links.js")[0], 200)

    def test_no_store_cookie_scope_catalog_uncertainty_and_absolute_expiry(self):
        cookie, proof = self.unlock()
        self.provider.fail = True
        result = self.request(path="/api/home/models")
        self.assertEqual(json.loads(result[1])["state"], "reauthentication")
        self.assertEqual(result[2]["Cache-Control"], "no-store")
        for _ in range(33):
            self.now += 880
            self.request(headers={"Cookie": cookie})
        self.assertEqual(self.request("POST", headers={"Cookie": cookie, "X-Reader-CSRF": proof["csrf"]}, body={"operation": "cancel"})[0], 403)

    def test_inventory_sanitization_empty_error_and_stale(self):
        inventory = self.inventory
        inventory.observe()
        result = inventory.snapshot(local=False)
        raw = json.dumps(result)
        self.assertNotIn("/private/source", raw)
        self.assertNotIn("javascript", raw)
        self.assertEqual(len(result["documents"]), 2)
        original = inventory.manager.parent_profiles
        same_names = original()
        same_names[1]["name"] = same_names[0]["name"]
        inventory.manager.parent_profiles = lambda: same_names
        inventory.observe()
        self.assertEqual(len({item["id"] for item in inventory.snapshot()["documents"]}), 2)
        inventory.manager.parent_profiles = original
        self.assertEqual(result["documents"][0]["state"], "ready")
        inventory.manager.mode = "timeout"
        inventory.observe()
        self.assertEqual(inventory.snapshot()["documents"][0]["state"], "stale")
        inventory.manager.mode = "empty"
        inventory.observe()
        self.assertEqual(inventory.snapshot()["documents"], [])
        inventory.manager.mode = "error"
        inventory.observe()
        self.assertIn("설정", inventory.snapshot()["error"])
        for value in ("javascript:alert(1)", "https://user:password@example.com", "https://example.com/path", "https://example.com?secret=x", "http://remote.example", "//remote.example", "https://example.com:invalid"):
            self.assertIsNone(reader_url(value))


    def test_stopped_unavailable_compiling_unknown_and_nonblocking_observation(self):
        for mode in ("stopped", "unavailable", "compiling"):
            self.inventory.manager.mode = mode
            self.inventory.observe()
            self.assertEqual(self.inventory.snapshot()["documents"][0]["state"], mode)
        self.inventory.observations.clear()
        self.inventory.manager.mode = "timeout"
        self.inventory.observe()
        self.assertEqual(self.inventory.snapshot()["documents"][0]["state"], "unknown")
        blocker = threading.Event()
        previous = self.inventory.manager.request
        self.inventory.manager.request = lambda *_a, **_k: blocker.wait(2)
        self.inventory.started = None
        start = time.monotonic()
        self.inventory.snapshot()
        self.assertLess(time.monotonic() - start, .1)
        blocker.set()
        self.inventory.manager.request = previous

    def test_one_host_owns_pending_login_for_each_auth_directory(self):
        directory = Path(self.temp.name)
        with claim_host(directory):
            with self.assertRaises(BlockingIOError):
                claim_host(directory)
        with claim_host(directory):
            pass

    def test_restart_and_credential_change_invalidate_session(self):
        cookie, proof = self.unlock()
        self.auth.signed_in = True
        self.assertEqual(self.request("POST", headers={"Cookie": cookie, "X-Reader-CSRF": proof["csrf"]}, body={"operation": "logout"})[0], 403)
        cookie, proof = self.unlock()
        fresh = HomeAccount(self.auth, self.provider)
        with self.assertRaises(PermissionError):
            fresh.mutate(cookie.split("=")[1], proof["csrf"], "admin", "http://127.0.0.1", "logout")


if __name__ == "__main__":
    unittest.main()
