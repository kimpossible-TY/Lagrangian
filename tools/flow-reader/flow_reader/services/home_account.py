"""Host account presentation and in-memory browser authority, never credentials."""
import hmac
import secrets
import threading
import time

from flow_reader.services.chat_auth import ChatProviderError


class HomeAccount:
    def __init__(self, auth, provider, *, clock=time.monotonic):
        self.auth, self.provider, self.clock = auth, provider, clock
        self.lock = threading.RLock()
        self.sessions = {}
        self.version, self.fingerprint = 0, None
        self.instance = secrets.token_urlsafe(16)

    def sync(self):
        status = self.auth.status()
        # Any credential write (including a rotating refresh in another Reader)
        # invalidates browser proof. Credential contents stay with ChatAuth.
        try:
            stamp = self.auth.path.stat().st_mtime_ns
        except FileNotFoundError:
            stamp = None
        fingerprint = (status["signedIn"], status.get("active"), stamp)
        if self.fingerprint is not None and fingerprint != self.fingerprint:
            self.invalidate()
        self.fingerprint = fingerprint
        return status

    def invalidate(self):
        self.sessions.clear()
        self.version += 1

    def session(self, handle, ingress, origin):
        now = self.clock()
        # Bound memory; expire all namespaces, even when no cookie is presented.
        self.sessions = {k: v for k, v in self.sessions.items()
                         if now - v["seen"] < 900 and now - v["created"] < 28800}
        session = self.sessions.get(handle)
        if session and session["ingress"] == ingress and session["origin"] == origin:
            session["seen"] = now
            return session
        return None

    def create(self, handle, ingress, origin, *, manage=False):
        with self.lock:
            self.sync()
            self.sessions.pop(handle, None)
            if len(self.sessions) >= 256:
                oldest = min(self.sessions, key=lambda k: self.sessions[k]["seen"])
                del self.sessions[oldest]
            handle, csrf, now = secrets.token_urlsafe(32), secrets.token_urlsafe(32), self.clock()
            self.sessions[handle] = {"csrf": csrf, "manage": manage, "ingress": ingress,
                                     "origin": origin, "created": now, "seen": now}
            return handle, {"csrf": csrf, "management": manage, **self.envelope()}

    def envelope(self):
        return {"version": self.version, "instance": self.instance}

    def status(self, handle, ingress, origin, *, eligible=False):
        with self.lock:
            status = self.sync()
            session = self.session(handle, ingress, origin)
            management = bool(eligible and session and session["manage"])
            result = {"signedIn": bool(status["signedIn"]), "planEnabled": bool(status["planEnabled"]),
                      "pending": bool(status.get("pending")), "management": management,
                      "eligible": eligible, **self.envelope()}
            if management:
                result.update({key: status.get(key) for key in ("accounts", "active", "notice")})
            return result

    def models(self):
        with self.lock:
            try:
                models = self.provider.models()
                state, notice = "available", "카탈로그는 실제 모델 사용 가능 여부나 잔여량을 보장하지 않습니다."
            except (ChatProviderError, OSError, ValueError, KeyError, TypeError) as error:
                models = []
                state = "reauthentication" if str(error) == "Sign in again" else "unavailable"
                notice = "다시 로그인하세요." if state == "reauthentication" else "모델 목록을 확인하지 못했습니다."
            self.sync()
            return {"models": models, "state": state, "notice": notice, **self.envelope()}

    def mutate(self, handle, csrf, ingress, origin, operation, registration=None):
        with self.lock:
            self.sync()
            session = self.session(handle, ingress, origin)
            if not session or not session["manage"] or not hmac.compare_digest(csrf, session["csrf"]):
                raise PermissionError("Mac 확인 세션이 만료되었습니다. 다시 확인하세요.")
            if operation not in {"login", "cancel", "logout"}:
                raise ValueError("Unknown account operation")
            # Invalidate before network work, preventing old tabs from retaining
            # authority while sign-out/revocation is in flight.
            self.invalidate()
            if operation == "login":
                result = self.auth.login(registration)
            elif operation == "logout":
                result = self.auth.logout()
            else:
                self.auth.close()
                result = {"notice": "로그인을 취소했습니다."}
            self.sync()
            new_handle, proof = self.create("", ingress, origin, manage=True)
            # Logout leaves no management session, including the initiating tab.
            if operation == "logout":
                self.sessions.pop(new_handle, None)
                new_handle, proof = "", {"management": False, **self.envelope()}
            return new_handle, {**result, **proof}
