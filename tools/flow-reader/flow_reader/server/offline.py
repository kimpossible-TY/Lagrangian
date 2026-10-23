"""Public accepted-snapshot inventory and content-versioned web app shell."""
import hashlib
import json
from urllib.parse import quote


def worker_script(assets, vendor_routes):
    files = {name: path for name, (path, _) in assets.items() if name != "/"}
    files.update(vendor_routes)
    digest = hashlib.sha256()
    for name, path in sorted(files.items()):
        digest.update(name.encode())
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    config = {"version": digest.hexdigest(), "files": [name.lstrip("/") for name in sorted(files)]}
    return ('import { runOfflineWorker } from "./features/session/offline-worker.js";\n'
            f'runOfflineWorker(self, {json.dumps(config)});\n').encode()


def snapshot_inventory(state):
    """Capture only accepted public data under its existing publication lock."""
    with state.lock:
        if state.bundle is None or state.revision is None:
            return None
        revision = quote(state.revision, safe="")
        manifest = json.loads(state.manifest_json)
        return {
            "state": {**state.public(), "compiling": False, "offline": True},
            "manifest": manifest,
            "resources": [f"api/sections/{quote(name, safe='')}?revision={revision}"
                          for name in state.bundle.documents]
                         + ["api/assets/" + quote(name, safe="") for name in state.bundle.assets],
        }
