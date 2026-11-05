"""Read-only projection of configured ReaderManager inventory and observations."""
from concurrent.futures import ThreadPoolExecutor
import threading
import time
from urllib.parse import urlsplit


LOOPBACK_HOST = "127.0.0.1"


def reader_url(value):
    """Accept configured origins only; never paths, credentials or redirects."""
    try:
        parsed = urlsplit(value)
        if (not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment
                or parsed.path not in {"", "/"} or not parsed.port and parsed.netloc.endswith(":")):
            return None
        if parsed.scheme != "https" and not (parsed.scheme == "http" and
                                              parsed.hostname == LOOPBACK_HOST):
            return None
        if any(c.isspace() or ord(c) < 32 for c in value) or "\\" in value:
            return None
        return parsed._replace(path="/", query="", fragment="").geturl()
    except (ValueError, TypeError, AttributeError):
        return None


def public_reader_url(value):
    url = reader_url(value)
    parsed = urlsplit(url or "")
    return url if parsed.scheme == "https" and parsed.hostname not in {"localhost", LOOPBACK_HOST, "::1"} else None


class HomeInventory:
    """One bounded background observation; reading never invokes manager.control."""
    def __init__(self, manager, *, clock=time.time, interval=30):
        self.manager, self.clock, self.interval = manager, clock, interval
        self.lock = threading.RLock()
        self.documents, self.profiles, self.observations = [], {}, {}
        self.error, self.checked, self.started = None, None, None
        self.refreshing, self.closed = False, False
        self.pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="home-status")

    def refresh(self):
        with self.lock:
            if self.closed or self.refreshing or (self.started is not None and
                                                    self.clock() - self.started < self.interval):
                return
            self.refreshing, self.started = True, self.clock()
        threading.Thread(target=self.observe, daemon=True, name="home-inventory").start()

    def observe(self):
        try:
            parents, profiles = self.manager.parent_profiles(), self.manager.profiles()
            if len(parents) > 128 or len(profiles) > 128:
                raise ValueError("Inventory limit")
            children = {}
            for profile in profiles:
                children.setdefault(profile["parentID"], []).append(profile)
            documents, probes = [], {}
            for parent in parents:
                variants = [{"kind": "paged", "public": public_reader_url(parent.get("publicURL", "")),
                             "local": reader_url(f"http://{LOOPBACK_HOST}:{parent['port']}/")}]
                for profile in children.get(parent["id"], []):
                    variants.append({"kind": "html", "public": public_reader_url(profile.get("publicURL", "")),
                                     "local": reader_url(f"http://{LOOPBACK_HOST}:{profile['port']}/")})
                    probes[profile["id"]] = profile
                name = parent.get("name")
                documents.append({"id": parent["id"], "name": name[:200] if isinstance(name, str) else "이름 없는 문서",
                                  "variants": variants,
                                  "services": [p["id"] for p in children.get(parent["id"], [])]})
            with self.lock:
                self.documents, self.profiles = documents, probes
                self.error, self.checked = None, self.clock()
            futures = [self.pool.submit(self.probe, key, profile) for key, profile in probes.items()]
            for future in futures:
                future.result()
        except Exception:
            # Configuration/errors can contain private paths. Never relay them.
            with self.lock:
                self.error = "문서 설정을 읽지 못했습니다. 이 Mac의 Reader 설정을 확인하세요."
        finally:
            with self.lock:
                self.refreshing = False

    def probe(self, key, profile):
        try:
            if self.manager.job_pid(profile, timeout=.75) is None:
                state = "stopped"
            else:
                response = self.manager.request(f"http://{LOOPBACK_HOST}:{profile['port']}/", "api/state", timeout=.75)
                if not isinstance(response, dict):
                    raise ValueError("Invalid status")
                state = "ready" if response.get("revision") else "unavailable"
                if response.get("compiling"):
                    state = "compiling"
            observation = {"state": state, "checkedAt": self.clock()}
        except Exception:
            with self.lock:
                old = self.observations.get(key)
            observation = {**old, "state": "stale"} if old else {"state": "unknown", "checkedAt": None}
        with self.lock:
            self.observations[key] = observation

    def snapshot(self, *, local=False):
        self.refresh()
        with self.lock:
            documents = []
            for document in self.documents:
                variants = [{"kind": v["kind"], "url": v["public"] or (v["local"] if local else None)}
                            for v in document["variants"]]
                observations = [self.observations.get(key, {"state": "unknown", "checkedAt": None})
                                for key in document["services"]]
                observation = next((o for o in observations if o["state"] == "ready"),
                                   observations[0] if observations else {"state": "unknown", "checkedAt": None})
                observation = dict(observation)
                if self.error or (observation["checkedAt"] is not None and
                                  self.clock() - observation["checkedAt"] > self.interval * 2):
                    observation["state"] = "stale"
                documents.append({"id": document["id"], "name": document["name"],
                                  "variants": variants, **observation})
            return {"documents": documents, "error": self.error, "checkedAt": self.checked,
                    "loading": self.refreshing and self.checked is None,
                    "host": "reachable", "statusScope": "HTML Reader observations; paged readiness is unknown"}

    def close(self):
        with self.lock:
            self.closed = True
        self.pool.shutdown(wait=False, cancel_futures=True)
