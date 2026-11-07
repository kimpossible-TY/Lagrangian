"""Homepage HTTP handlers and the shared account-owner lease."""
import fcntl
import os
import hmac
from http.cookies import SimpleCookie, CookieError
from http.server import BaseHTTPRequestHandler
import json
from pathlib import Path
from urllib.parse import urlsplit

from flow_reader.resources import READER_ROOT
from flow_reader.server.assets import CONTENT_TYPES
from flow_reader.services.homepage import LOOPBACK_HOST, reader_url
from flow_reader.services.chat_auth import ChatProviderError
from flow_reader.services.home_account import OAUTH_OPERATIONS
from flow_reader.services.chat_storage import private_file


def claim_host(directory):
    """Only one host may own pending OAuth for a shared registration directory."""
    lease = os.fdopen(private_file(directory / "home-owner.lock"), "a+b")
    try:
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BaseException:
        lease.close()
        raise
    return lease


def home_assets():
    web = READER_ROOT / "web"
    manifest = json.loads((web / "home-assets.json").read_text())
    result = {}
    for name, value in manifest.items():
        path = (web / value).resolve()
        if (name.startswith("/") or ".." in Path(name).parts or "?" in name or "#" in name
                or not path.is_relative_to(web.resolve()) or path.suffix not in CONTENT_TYPES or not path.is_file()):
            raise ValueError("Invalid Homepage asset")
        result["/" + name] = path
    result["/"] = result["/index.html"]
    return result


def handler_for_home(inventory, account, *, ingress="admin", public_origin=None, capability=""):
    if ingress not in {"admin", "proxy"}:
        raise ValueError("Unknown ingress")
    if ingress == "proxy" and (not public_origin or not reader_url(public_origin)
                                or urlsplit(public_origin).scheme != "https"):
        raise ValueError("Proxy requires an exact HTTPS origin")
    assets = home_assets()
    cookie_name = "ReaderHomeAdmin" if ingress == "admin" else "__Secure-ReaderHomeView"

    class Handler(BaseHTTPRequestHandler):

        def origin(self):
            return (f"http://{LOOPBACK_HOST}:{self.server.server_port}" if ingress == "admin"
                    else public_origin.rstrip("/"))

        def trusted(self):
            return (len(self.headers.get_all("Host", [])) == 1
                    and self.headers["Host"] == urlsplit(self.origin()).netloc)

        def eligible(self):
            forwarded = any(name.lower() == "forwarded" or name.lower().startswith(
                ("x-forwarded-", "tailscale-")) for name in self.headers)
            return ingress == "admin" and self.client_address[0] == LOOPBACK_HOST and not forwarded

        def capability_valid(self):
            supplied = self.headers.get("X-Reader-Host-Capability", "")
            return (self.eligible() and bool(capability)
                    and len(self.headers.get_all("X-Reader-Host-Capability", [])) == 1
                    and hmac.compare_digest(supplied.encode(), capability.encode()))

        def handle_cookie(self):
            if len(self.headers.get_all("Cookie", [])) > 1:
                return ""
            try:
                raw = self.headers.get("Cookie", "")
                if sum(part.strip().startswith(cookie_name + "=") for part in raw.split(";")) > 1:
                    return ""
                cookie = SimpleCookie(raw)
                return cookie[cookie_name].value if cookie_name in cookie else ""
            except CookieError:
                return ""

        def cookie(self, handle):
            return (f"{cookie_name}={handle}; Path=/api/home/; HttpOnly; SameSite=Strict"
                    + ("; Secure" if ingress == "proxy" else "")
                    + ("; Max-Age=0" if not handle else ""))

        def respond(self, body, status=200, *, mime="application/json; charset=utf-8", cookie=None):
            if not isinstance(body, bytes):
                body = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
            if cookie is not None:
                self.send_header("Set-Cookie", self.cookie(cookie))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if not self.trusted():
                return self.respond({"error": "Unrecognized host"}, 421)
            path = urlsplit(self.path).path
            # No host callback, document shell, worker or offline fallback.
            if path in assets and not urlsplit(self.path).query:
                asset = assets[path]
                return self.respond(asset.read_bytes(), mime=CONTENT_TYPES[asset.suffix])
            try:
                if path in {"/api/home/documents", "/api/home/status"}:
                    return self.respond(inventory.snapshot(local=self.eligible()))
                if path == "/api/home/account":
                    return self.respond({**account.status(self.handle_cookie(), ingress, self.origin(),
                        eligible=self.capability_valid()), "eligible": self.eligible()})
                if path == "/api/home/models":
                    return self.respond(account.models())
            except (OSError, ValueError, ChatProviderError):
                return self.respond({"error": "연결 상태를 확인하지 못했습니다."}, 503)
            return self.respond({"error": "Not found"}, 404)

        def do_POST(self):
            if not self.trusted():
                return self.respond({"error": "Unrecognized host"}, 421)
            path = self.path
            if path not in {"/api/home/session", "/api/home/account"}:
                return self.respond({"error": "Not found"}, 404)
            if len(self.headers.get_all("Origin", [])) != 1 or self.headers["Origin"] != self.origin():
                return self.respond({"error": "Exact same origin required"}, 403)
            if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                return self.respond({"error": "Expected JSON"}, 415)
            try:
                if len(self.headers.get_all("Content-Length", [])) != 1 or self.headers.get("Transfer-Encoding"):
                    raise ValueError("Invalid size")
                size = int(self.headers["Content-Length"])
                if not 0 < size <= 4096:
                    raise ValueError("Invalid size")
                request = json.loads(self.rfile.read(size))
                if not isinstance(request, dict):
                    raise ValueError("Invalid object")
                handle = self.handle_cookie()
                if path.endswith("/session"):
                    supplied = self.headers.get("X-Reader-Host-Capability", "")
                    management = self.capability_valid()
                    if supplied and not management:
                        return self.respond({"error": "이 Mac의 현재 확인값이 필요합니다."}, 403)
                    oauth = request.get("purpose") == "oauth"
                    if oauth and not self.eligible():
                        return self.respond({"error": "이 Mac에서만 로그인하거나 로그아웃할 수 있습니다."}, 403)
                    handle, result = account.create(handle, ingress, self.origin(), manage=management, oauth=oauth)
                else:
                    operation = request.get("operation")
                    oauth_only = operation in OAUTH_OPERATIONS and not (
                        operation == "login" and request.get("registration"))
                    if not (self.eligible() if oauth_only else self.capability_valid()):
                        return self.respond({"error": "이 Mac에서만 계정을 관리할 수 있습니다."}, 403)
                    handle, result = account.mutate(handle, self.headers.get("X-Reader-CSRF", ""), ingress,
                        self.origin(), operation, request.get("registration"))
                return self.respond(result, cookie=handle)
            except PermissionError:
                return self.respond({"error": "Mac 확인 세션이 만료되었습니다. 다시 확인하세요."}, 403, cookie="")
            except (ValueError, TypeError, UnicodeError):
                return self.respond({"error": "Invalid account request"}, 400)
            except (OSError, ChatProviderError):
                return self.respond({"error": "계정 작업을 완료하지 못했습니다. 연결을 확인하고 다시 시도하세요."}, 503)

        def log_message(self, *_args):
            pass

    return Handler


def main():
    """Compatibility entrypoint: Homepage is now part of the Reader runtime."""
    import sys
    from flow_reader.server.cli import main as reader_main
    reader_main(["--managed", *sys.argv[1:]])
