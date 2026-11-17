"""Static delivery for the isolated synthetic lifecycle fixture."""
from http.server import ThreadingHTTPServer
import threading
import unittest
from urllib.request import urlopen

from home_lifecycle_preview import LifecycleHandler
from home_preview import ASSETS, CSP


class LifecyclePreviewTests(unittest.TestCase):
    def test_modes_add_only_test_observation_assets(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), LifecycleHandler)
        server.mode = "documents"
        server.inventory_file = None
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            origin = f"http://127.0.0.1:{server.server_port}"
            with urlopen(origin + "/") as response:
                self.assertEqual(response.read(), ASSETS["/"].read_bytes())
            for route, slow in (("/slow/", True), ("/normal/", False)):
                with urlopen(origin + route) as response:
                    html = response.read().decode()
                    self.assertEqual(response.headers["Content-Security-Policy"], CSP)
                self.assertIn('/fixture-observe.js', html)
                self.assertEqual('/fixture-slow.css' in html, slow)
                self.assertIn('/home/home.js', html)
            for route in ("/fixture-slow.css", "/fixture-observe.js"):
                with urlopen(origin + route) as response:
                    self.assertEqual(response.status, 200)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
