"""SIWC public-client PKCE, isolated credentials, renewal and revocation.

No ambient API keys, Codex profiles or browser cookies are used. Network and
signature operations are injected for isolated protocol tests, never via HTTP.
"""
import base64
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import shutil
import subprocess
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request
import uuid
import webbrowser
from urllib.request import HTTPRedirectHandler, build_opener

from flow_reader.services.chat_storage import file_lock, read_json, write_json

ISSUER = "https://auth.openai.com"
RESOURCE = "https://api.openai.com/v1"
SCOPES = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


def open_private(request, timeout):
    return build_opener(NoRedirect).open(request, timeout=timeout)


class ChatProviderError(Exception):
    """Only this public, non-secret message may leave the provider boundary."""


def request_json(url, fields=None, *, bearer=None):
    headers = {"Accept": "application/json"}
    data = None
    if fields is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        data = urlencode(fields).encode()
    if bearer:
        headers["Authorization"] = "Bearer " + bearer
    try:
        with open_private(Request(url, data, headers), timeout=30) as response:
            raw = response.read(1024 * 1024 + 1)
            if len(raw) > 1024 * 1024:
                raise ChatProviderError("Authentication response is too large")
            return json.loads(raw) if raw else {}
    except HTTPError as error:
        # Never relay response bodies or URLs: they can contain secrets.
        code = ""
        try:
            code = json.loads(error.read(65536)).get("error", "")
            if isinstance(code, dict):
                code = code.get("code", "")
        except (ValueError, AttributeError):
            pass
        finally:
            error.close()
        terminal = {"invalid_grant", "invalid_refresh_token", "token_expired",
                    "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"}
        if isinstance(code, str) and code in terminal:
            raise ChatProviderError("Sign in again") from None
        raise ChatProviderError(f"Authentication service returned HTTP {error.code}") from None
    except (URLError, OSError, ValueError):
        raise ChatProviderError("Authentication service is unavailable") from None


def verify_identity(token, keys):
    helper = Path(__file__).with_name("verify-id-token.mjs")
    node = shutil.which("node") or next((path for path in ("/opt/homebrew/bin/node", "/usr/local/bin/node")
                                        if Path(path).is_file()), "node")
    try:
        result = subprocess.run([node, str(helper)],
            input=json.dumps({"token": token, "keys": keys}), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10, check=True)
        return json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        raise ChatProviderError("Could not verify OpenAI identity (Node.js is required)") from None


class ChatAuth:
    def __init__(self, directory, *, request=request_json, verify=verify_identity, issuer=ISSUER,
                 open_browser=webbrowser.open):
        self.directory = directory
        self.path = directory / "credentials.json"
        self.request, self.verify, self.issuer = request, verify, issuer
        self.open_browser = open_browser
        self.lock = threading.RLock()
        self.pending = None
        self.generation = 0
        self.notice = ""

    def credentials(self):
        return read_json(self.path, {"hostID": "urn:uuid:" + str(uuid.uuid4()),
                                     "active": None, "registrations": {}})

    def status(self):
        with file_lock(self.directory / "auth.lock"), self.lock:
            data = self.credentials()
            account = data["registrations"].get(data["active"], {})
            return {"signedIn": bool(account.get("access_token")),
                    "planEnabled": "chatgpt.tokens.use.direct" in account.get("scopes", []),
                    "active": data["active"],
                    "accounts": [{"id": key, "label": value.get("email") or value["subject"]}
                                 for key, value in data["registrations"].items()],
                    "pending": bool(self.pending), "notice": self.notice}

    def discovery(self):
        metadata = self.request(self.issuer + "/.well-known/openid-configuration")
        if metadata.get("issuer") != self.issuer:
            raise ChatProviderError("OpenAI issuer mismatch")
        # Discovery may not redirect secrets to arbitrary hosts.
        for field in ("authorization_endpoint", "token_endpoint", "jwks_uri", "revocation_endpoint"):
            endpoint = urlsplit(metadata.get(field, ""))
            expected = urlsplit(self.issuer)
            if endpoint.scheme != expected.scheme or endpoint.netloc != expected.netloc:
                raise ChatProviderError("Untrusted OpenAI discovery endpoint")
        return metadata

    def login(self, registration=None, *, open_browser=True):
        generation = self.close()
        metadata = self.discovery()
        with file_lock(self.directory / "auth.lock"):
            data = self.credentials()
            previous = data["registrations"].get(registration) if registration else None
            if registration and not previous:
                raise ValueError("Unknown ChatGPT registration")
            write_json(self.path, data)  # Stable host ID exists before authorization.
        with self.lock:
            if generation != self.generation:
                raise ChatProviderError("Sign-in was cancelled")
            verifier = secrets.token_urlsafe(48)
            attempt = {"state": secrets.token_urlsafe(32), "nonce": secrets.token_urlsafe(32),
                       "verifier": verifier, "previous": previous, "metadata": metadata,
                       "registration": registration, "generation": generation, "expires": time.monotonic() + 300}
            owner = self
            class Callback(BaseHTTPRequestHandler):
                def do_GET(self):
                    parsed = urlsplit(self.path)
                    ok = parsed.path == "/auth/callback" and owner.callback(attempt, parse_qs(parsed.query))
                    body = ("Sign-in complete. Return to Reader." if ok else
                            "Sign-in was not completed. Return to Reader and try again.").encode()
                    self.send_response(200 if ok else 400)
                    self.send_header("Content-Type", "text/plain; charset=utf-8")
                    self.send_header("Content-Length", str(len(body)))
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Referrer-Policy", "no-referrer")
                    self.end_headers()
                    self.wfile.write(body)
                def log_message(self, *_args):
                    pass  # Authorization codes and state must never enter logs.
            server = ThreadingHTTPServer(("127.0.0.1", 0), Callback)
            server.daemon_threads = True
            attempt["server"] = server
            attempt["redirect"] = f"http://127.0.0.1:{server.server_port}/auth/callback"
            self.pending = attempt
            threading.Thread(target=server.serve_forever, daemon=True).start()
            timer = threading.Timer(300, lambda: self.expire(attempt))
            timer.daemon = True
            attempt["timer"] = timer
            timer.start()
            params = {"client_id": registration or "dynamic_agent_client",
                      "ext_agent_host_id": data["hostID"], "response_type": "code",
                      "redirect_uri": attempt["redirect"], "scope": SCOPES, "resource": RESOURCE,
                      "state": attempt["state"], "nonce": attempt["nonce"],
                      "code_challenge_method": "S256",
                      "code_challenge": base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")}
            if not previous:
                params["agent_name_hint"] = "Lagrangian Reader"
            # Deliberately omit ID-token hints: credentials never enter a browser URL.
            self.notice = "Complete sign-in in this Mac's browser. No question is sent automatically."
            url = metadata["authorization_endpoint"] + "?" + urlencode(params)
        # Homepage navigates its current browser; terminal callers retain the
        # default system-browser opener contract.
        if open_browser and self.open_browser:
            self.open_browser(url)
        return {"authUrl": url}

    @staticmethod
    def dispose_attempt(attempt):
        if attempt:
            attempt["timer"].cancel()
            attempt["server"].shutdown()
            attempt["server"].server_close()

    def expire(self, attempt):
        with self.lock:
            if self.pending is not attempt:
                return
            self.pending = None
            self.generation += 1
            self.notice = "Sign-in expired. Try again."
        self.dispose_attempt(attempt)

    def callback(self, attempt, query):
        with self.lock:
            if (self.pending is not attempt or time.monotonic() > attempt["expires"] or
                    len(query.get("state", [])) != 1 or
                    not hmac.compare_digest(query["state"][0].encode(), attempt["state"].encode())):
                return False
            # Consume the attempt before network work; callbacks are one-use.
            self.pending = None
            attempt["timer"].cancel()
        try:
            if query.get("error") or len(query.get("code", [])) != 1:
                raise ChatProviderError("Sign-in was declined")
            client = attempt["registration"]
            returned = query.get("client_id", [client])
            if (len(returned) != 1 or not returned[0] or returned[0] == "dynamic_agent_client"
                    or client and returned[0] != client):
                raise ChatProviderError("Registration did not match")
            client = returned[0]
            tokens = self.request(attempt["metadata"]["token_endpoint"], {
                "grant_type": "authorization_code", "client_id": client,
                "code": query["code"][0], "code_verifier": attempt["verifier"],
                "redirect_uri": attempt["redirect"], "resource": RESOURCE})
            keys = self.request(attempt["metadata"]["jwks_uri"])["keys"]
            claims = self.verify(tokens["id_token"], keys)
            now = time.time()
            audience = claims.get("aud", [])
            audience = [audience] if isinstance(audience, str) else audience
            if (claims.get("iss") != self.issuer or client not in audience
                    or len(audience) > 1 and claims.get("azp") != client
                    or not isinstance(claims.get("sub"), str) or not claims["sub"]
                    or not isinstance(claims.get("nonce"), str)
                    or not hmac.compare_digest(claims["nonce"].encode(), attempt["nonce"].encode())
                    or not isinstance(claims.get("exp"), (int, float)) or claims["exp"] < now - 5
                    or not isinstance(claims.get("iat"), (int, float)) or claims["iat"] > now + 5
                    or claims.get("nbf", 0) > now + 5
                    or attempt["previous"] and claims["sub"] != attempt["previous"]["subject"]):
                raise ChatProviderError("OpenAI identity claims did not match")
            with file_lock(self.directory / "auth.lock"), self.lock:
                if self.generation != attempt["generation"]:
                    return False
                data = self.credentials()
                record = {"subject": claims["sub"], "email": claims.get("email", ""),
                          "client_id": client, "issuer": self.issuer}
                self.update_tokens(record, tokens)
                data["registrations"][client] = record
                data["active"] = client
                write_json(self.path, data)
                self.notice = "Signed in. Select a model before sending your question."
            return True
        except (ChatProviderError, KeyError, ValueError, TypeError):
            with self.lock:
                if self.generation == attempt["generation"]:
                    self.notice = "Sign-in failed or identity could not be verified. Try again."
            return False
        finally:
            # Shutdown waits on serve_forever, never on this callback thread.
            attempt["server"].shutdown()
            attempt["server"].server_close()

    @staticmethod
    def update_tokens(record, tokens):
        refresh_token = tokens.get("refresh_token") or record.get("refresh_token")
        if (tokens.get("token_type", "").lower() != "bearer" or
                not isinstance(tokens.get("access_token"), str) or not tokens["access_token"] or
                not isinstance(refresh_token, str) or not refresh_token or
                not isinstance(tokens.get("expires_in"), (int, float)) or tokens["expires_in"] <= 0):
            raise ChatProviderError("Incomplete OAuth token response")
        record.update({key: tokens[key] for key in ("access_token", "token_type")})
        record["refresh_token"] = refresh_token
        # Identity is verified at login; refreshed ID tokens are never used or retained.
        record.pop("id_token", None)
        record["expires_at"] = time.time() + tokens["expires_in"]
        record["scopes"] = tokens.get("scope", " ".join(record.get("scopes", []))).split()

    def access_token(self):
        # Cross-process lock covers the entire rotating refresh transaction.
        with file_lock(self.directory / "auth.lock"):
            data = self.credentials()
            record = data["registrations"].get(data["active"], {})
            if not record.get("access_token"):
                raise ChatProviderError("Continue with ChatGPT on this Mac to send a question")
            if record["expires_at"] < time.time() + 60:
                try:
                    tokens = self.request(self.discovery()["token_endpoint"], {
                        "grant_type": "refresh_token", "client_id": record["client_id"],
                        "refresh_token": record["refresh_token"], "resource": RESOURCE})
                    self.update_tokens(record, tokens)
                except ChatProviderError as error:
                    if str(error) == "Sign in again":
                        self.clear_tokens(record)
                        write_json(self.path, data)
                    raise
                write_json(self.path, data)
            if "chatgpt.tokens.use.direct" not in record["scopes"]:
                raise ChatProviderError("ChatGPT plan usage was not authorized. Sign in to enable it.")
            return record["access_token"]

    @staticmethod
    def clear_tokens(record):
        for key in ("access_token", "refresh_token", "id_token", "expires_at", "scopes", "token_type"):
            record.pop(key, None)

    def logout(self):
        self.close()
        with file_lock(self.directory / "auth.lock"):
            data = self.credentials()
            record = data["registrations"].get(data["active"], {})
            confirmed = not record.get("refresh_token")
            if not confirmed:
                try:
                    endpoint = self.discovery()["revocation_endpoint"]
                    for delay in (0, 0.2, 0.5):
                        time.sleep(delay)
                        try:
                            self.request(endpoint, {"token": record["refresh_token"],
                                "token_type_hint": "refresh_token", "client_id": record["client_id"]})
                            confirmed = True
                            break
                        except ChatProviderError:
                            continue
                except ChatProviderError:
                    pass
            self.clear_tokens(record)
            write_json(self.path, data)
            with self.lock:
                self.notice = ("Signed out." if confirmed else
                    "Signed out locally. Remote revocation was not confirmed; disconnect the app in ChatGPT Settings.")
                return {"notice": self.notice, "revocationConfirmed": confirmed}

    def close(self):
        with self.lock:
            self.generation += 1
            generation = self.generation
            attempt, self.pending = self.pending, None
        self.dispose_attempt(attempt)
        return generation
