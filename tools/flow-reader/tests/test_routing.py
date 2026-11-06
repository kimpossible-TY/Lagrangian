"""Shared-origin HTTP regressions with synthetic documents and fake account only."""
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import unittest

from chat_fixture import FakeOpenAI, SyntheticReader
from test_homepage import FakeAuth, FakeProvider, FakeManager
from flow_reader.server.routing import document_prefix, handler_for_reader, handler_for_legacy
from flow_reader.services.homepage import HomeInventory
from flow_reader.services.home_account import HomeAccount


class RoutingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="shared-reader-test-")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.fake = FakeOpenAI()
        self.addCleanup(self.fake.close)
        self.readers = {}
        for identifier in ("first", "second"):
            directory = self.work / identifier
            directory.mkdir()
            reader = SyntheticReader(directory, self.fake)
            self.readers[identifier] = reader
            self.addCleanup(reader.state.paragraph_chat.auth.close)
            self.addCleanup(reader.close)
        self.documents = {key: reader.state for key, reader in self.readers.items()}
        self.auth = FakeAuth(self.work)
        self.provider = FakeProvider()
        self.account = HomeAccount(self.auth, self.provider)
        self.inventory = HomeInventory(FakeManager())
        self.inventory.observe()
        self.addCleanup(self.inventory.close)
        self.admin = self.serve(handler_for_reader(self.documents, self.inventory, self.account,
                                capability="current-proof"))
        self.proxy = self.serve(handler_for_reader(self.documents, self.inventory, self.account,
                                capability="current-proof", ingress="proxy", public_origin="https://reader.example"))

    def serve(self, handler):
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), thread.join()))
        return server

    def request(self, path="/", *, method="GET", body=None, server=None, headers=None):
        server = server or self.admin
        origin = "https://reader.example" if server is self.proxy else f"http://127.0.0.1:{server.server_port}"
        fields = {"Host": origin.split("//")[1], "Origin": origin, "Content-Type": "application/json"}
        fields.update(headers or {})
        connection = HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        connection.request(method, path, json.dumps(body or {}) if method == "POST" else None, fields)
        result = connection.getresponse()
        response = result.status, result.read(), dict(result.getheaders())
        connection.close()
        return response

    def unlock(self):
        status, raw, headers = self.request("/api/home/session", method="POST",
                                           headers={"X-Reader-Host-Capability": "current-proof"})
        self.assertEqual(status, 200)
        return {"Cookie": headers["Set-Cookie"].split(";")[0], "X-Reader-CSRF": json.loads(raw)["csrf"],
                "X-Reader-Host-Capability": "current-proof"}

    def test_home_and_two_documents_share_listener_and_keep_state(self):
        self.assertIn(b'home/home.js', self.request()[1])
        for key, reader in self.readers.items():
            status, raw, _ = self.request(f"/d/{key}/api/state")
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(raw)["documentID"], reader.state.document_id)
            self.assertEqual(self.request(f"/d/{key}/")[0], 200)
            self.assertEqual(self.request(f"/d/{key}/document.html")[1], reader.html.encode())
        self.assertEqual(self.auth.calls, [])
        self.assertEqual(self.provider.calls, 0)

    def test_relative_assets_worker_manifest_and_sections(self):
        root = "/d/first/"
        for path in ("reader.js", "reader.css", "service-worker.js", "api/manifest", "api/offline",
                     "features/paragraph-chat/controller.js", "reader-common/paragraph-chat/state.js"):
            self.assertEqual(self.request(root + path)[0], 200, path)
        offline = json.loads(self.request(root + "api/offline")[1])
        for resource in offline["resources"]:
            self.assertEqual(self.request(root + resource)[0], 200, resource)
        self.assertEqual(self.request("/service-worker.js")[0], 404)
        self.assertEqual(self.request("/api/state")[0], 404)
        worker = self.request(root + "service-worker.js")[1]
        self.assertNotIn(b"api/home", worker)
        self.assertNotIn("Service-Worker-Allowed", self.request(root + "service-worker.js")[2])

    def test_prefix_canonicalization_unknown_ids_and_traversal(self):
        status, _, headers = self.request("/d/first?mode=terminal")
        self.assertEqual(status, 307)
        self.assertEqual(headers["Location"], "/d/first/?mode=terminal")
        for path in ("/d/nope/", "/d/first/../second/", "/d/first/%2e%2e/api/home/account",
                     "/d/%66irst/", "/d/first/api/home/account", "/d/first/api/home/session"):
            self.assertEqual(self.request(path)[0], 404, path)
        for key in ("../first", "First", "a/b", "", "x" * 65):
            with self.assertRaises(ValueError):
                document_prefix(key)

    def test_prefixed_chat_revision_and_read_only_account(self):
        reader = self.readers["first"]
        status, raw, _ = self.request("/d/first/api/chat/auth", method="POST", body=reader.request())
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw)["homepageURL"], f"http://127.0.0.1:{self.admin.server_port}/")
        for operation in ("login", "cancel", "logout"):
            self.assertEqual(self.request("/d/first/api/chat/auth", method="POST",
                body=reader.request(operation=operation))[0], 403)
        self.assertEqual(self.request("/d/second/api/chat/list", method="POST", body=reader.request())[0], 409)
        self.assertEqual(self.request("/d/first/api/chat/list", method="POST",
            body=reader.request(revision="stale"))[0], 409)
        status, raw, _ = self.request("/d/first/api/chat/open", method="POST",
            body=reader.request(fragments=reader.fragments("First paragraph")))
        self.assertEqual(status, 200, raw)
        self.assertTrue(json.loads(raw))

    def test_cookie_csrf_without_capability_cannot_mutate_or_read_identity(self):
        headers = self.unlock()
        headers.pop("X-Reader-Host-Capability")
        status = json.loads(self.request("/api/home/account", headers=headers)[1])
        self.assertFalse(status["management"])
        self.assertNotIn("accounts", status)
        for operation in ("login", "cancel", "logout"):
            self.assertEqual(self.request("/api/home/account", method="POST", headers=headers,
                body={"operation": operation})[0], 403)
            self.assertEqual(self.request("/d/first/api/home/account", method="POST", headers=headers,
                body={"operation": operation})[0], 404)
        self.assertEqual(self.auth.calls, [])

    def test_non_loopback_and_proxy_deny_copied_proofs_for_every_operation(self):
        base = handler_for_reader(self.documents, self.inventory, self.account, capability="current-proof")
        class RemotePeer(base):
            def setup(self):
                super().setup()
                self.client_address = ("192.0.2.41", self.client_address[1])
        remote = self.serve(RemotePeer)
        headers = self.unlock()
        for server in (remote, self.proxy):
            for operation in ("login", "cancel", "logout"):
                self.assertEqual(self.request("/api/home/account", server=server, method="POST", headers=headers,
                    body={"operation": operation})[0], 403)
            self.assertEqual(self.request("/api/home/session", server=server, method="POST", headers=headers)[0], 403)
        self.assertEqual(self.auth.calls, [])
        for operation in ("login", "cancel", "logout"):
            headers = self.unlock()
            self.assertEqual(self.request("/api/home/account", method="POST", headers=headers,
                body={"operation": operation})[0], 200)
        self.assertEqual(self.auth.calls, ["login", "cancel", "logout"])

    def test_proxy_document_link_stays_on_public_origin(self):
        status, raw, _ = self.request("/d/first/api/chat/auth", server=self.proxy,
            method="POST", body=self.readers["first"].request())
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw)["homepageURL"], "https://reader.example/")
        self.assertEqual(self.request("/d/first/", server=self.proxy)[0], 200)

    def test_legacy_redirects_preserve_method_path_query_and_deny_admin(self):
        legacy = self.serve(handler_for_legacy("first", "https://reader.example/", public_origin="https://old.example"))
        for method in ("GET", "POST"):
            for path in ("/", "/document.html?revision=r1", "/api/chat/list?x=1"):
                status, _, headers = self.request(path, method=method, server=legacy,
                                                  headers={"Host": "old.example"})
                self.assertEqual(status, 307)
                self.assertEqual(headers["Location"], "https://reader.example/d/first" + path)
            self.assertEqual(self.request("/api/home/account", method=method, server=legacy)[0], 403)
        status, raw, headers = self.request("/service-worker.js", server=legacy)
        self.assertEqual(status, 200)
        self.assertIn(b"registration.unregister", raw)
        self.assertIn(b"registration.scope", raw)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(self.request(server=legacy, headers={"Host": "evil.example"})[0], 421)

    def test_paged_entry_keeps_native_destination(self):
        self.documents["first"].original_url = "https://paged.example/"
        server = self.serve(handler_for_reader(self.documents, self.inventory, self.account, capability="proof"))
        status, _, headers = self.request("/d/first/paged/", server=server)
        self.assertEqual(status, 307)
        self.assertEqual(headers["Location"], "https://paged.example/")


if __name__ == "__main__":
    unittest.main()
