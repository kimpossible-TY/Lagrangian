"""HTTP contracts for the synthetic, read-only Homepage fixture."""
from http.server import ThreadingHTTPServer
import json
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from home_preview import ASSETS, CSP, Handler


class HomePreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.server.mode = "empty"
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def get(self, path):
        with urlopen(self.url + path) as response:
            self.assertEqual(response.headers["Content-Security-Policy"], CSP)
            self.assertIsNone(response.headers.get("Set-Cookie"))
            return response.read()

    def test_home_and_assets_are_the_actual_manifest_files(self):
        for route in ("/", "/home/home.css", "/home/home.js"):
            self.assertEqual(self.get(route), ASSETS[route].read_bytes())

    def test_synthetic_destinations_and_home_return(self):
        for path, label in (("/example-html", "합성 HTML 목적지"),
                            ("/example-paged", "합성 Paged 목적지")):
            page = self.get(path).decode()
            self.assertIn(label, page)
            self.assertIn('href="/"', page)

    def test_inventory_modes_are_independent_and_account_is_inert(self):
        read = lambda suffix: json.loads(self.get("/api/home/documents" + suffix))
        self.assertEqual(read("")["documents"], [])
        self.assertEqual(len(read("?mode=documents")["documents"]), 3)
        self.assertTrue(read("?mode=loading")["loading"])
        self.assertTrue(read("?mode=error")["error"])
        self.assertEqual(read("")["documents"], [])
        self.assertFalse(json.loads(self.get("/api/home/account"))["eligible"])
        with self.assertRaises(HTTPError) as error:
            self.get("/api/home/documents?mode=invalid")
        self.assertEqual(error.exception.code, 400)
        error.exception.close()

    def test_post_is_rejected(self):
        with self.assertRaises(HTTPError) as error:
            urlopen(Request(self.url + "/api/home/account", data=b"{}", method="POST"))
        self.assertEqual(error.exception.code, 501)
        error.exception.close()


if __name__ == "__main__":
    unittest.main()
