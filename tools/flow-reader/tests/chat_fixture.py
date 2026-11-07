"""Synthetic accepted Reader and local OAuth/Responses fixture, never live inference."""
import base64
import gzip
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import threading
import time
from urllib.parse import parse_qs

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from flow_reader.compiler.project import Project
from flow_reader.compiler.inputs import input_fingerprint, source_signature
from flow_reader.document.sections import split_document
from flow_reader.server.state import ReaderState
from flow_reader.services.chat_auth import ChatAuth, request_json
from flow_reader.services.chat_provider import ResponsesProvider
from flow_reader.services.chat_storage import private_directory, write_json
from flow_reader.services.paragraph_chat import ParagraphChat


class FakeOpenAI:
    def __init__(self):
        # A disposable signing key exercises the real Node crypto verifier.
        self.keys = json.loads(subprocess.check_output(["node", "--input-type=module", "-e",
            'import {generateKeyPairSync} from "node:crypto"; const k=generateKeyPairSync("ed25519");'
            'console.log(JSON.stringify({public:k.publicKey.export({format:"jwk"}),private:k.privateKey.export({format:"jwk"})}));'], text=True))
        self.keys["public"].update(kid="fixture", alg="EdDSA", use="sig")
        self.nonce = "fixture"
        self.subject = "fixture-user"
        self.mode = "success"
        self.refreshes = 0
        self.revocations = 0
        self.requests = []
        self.stream_started = threading.Event()
        self.stream_closed = threading.Event()
        owner = self
        class Handler(BaseHTTPRequestHandler):
            def reply(self, result, status=200):
                raw = json.dumps(result).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)
            def do_GET(self):
                if self.path == "/.well-known/openid-configuration":
                    return self.reply({"issuer": owner.url,
                        "authorization_endpoint": owner.url + "/authorize",
                        "token_endpoint": owner.url + "/token", "jwks_uri": owner.url + "/jwks",
                        "revocation_endpoint": owner.url + "/revoke"})
                if self.path == "/jwks":
                    return self.reply({"keys": [owner.keys["public"]]})
                if self.path == "/models":
                    return self.reply({"models": [{"slug": "fixture-model", "display_name": "Fixture model", "visibility": "list"},
                                                  {"slug": "gpt-6-luna", "display_name": "GPT-6 Luna", "visibility": "list"}]})
                self.reply({}, 404)
            def do_POST(self):
                raw = self.rfile.read(int(self.headers["Content-Length"]))
                if self.path == "/token":
                    fields = {k: v[0] for k, v in parse_qs(raw.decode()).items()}
                    owner.requests.append((self.path, fields))
                    if fields["grant_type"] == "refresh_token":
                        owner.refreshes += 1
                        if owner.mode == "revoked":
                            return self.reply({"error": "invalid_grant"}, 400)
                    return self.reply(owner.tokens())
                if self.path == "/revoke":
                    owner.revocations += 1
                    return self.reply({}) if owner.mode != "revoke-failure" else self.reply({}, 503)
                if self.path != "/responses":
                    return self.reply({}, 404)
                body = json.loads(raw)
                owner.requests.append((self.path, body))
                if owner.mode == "http-failure":
                    return self.reply({"secret": "never-relay-this"}, 401)
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                def emit(value):
                    self.wfile.write(("data: " + json.dumps(value) + "\n\n").encode())
                    self.wfile.flush()
                if owner.mode == "stall":
                    emit({"type": "response.in_progress"})
                    owner.stream_started.set()
                    self.connection.settimeout(5)
                    try:
                        self.connection.recv(1)  # Cancellation must close the upstream socket.
                    finally:
                        owner.stream_closed.set()
                    return
                if owner.mode == "disconnect":
                    emit({"type": "response.output_text.delta", "delta": "Incomplete "})
                    return
                context = json.loads(body["input"][0]["content"].split("\n", 1)[1])
                outputs = [item for item in body["input"] if item.get("type") == "function_call_output"]
                if len(outputs) < 2:
                    arguments = {"documentID": context["documentID"], "revision": context["revision"],
                                 "offset": 0, "limit": 5 if not outputs else 8000}
                    if outputs:
                        matches = json.loads(outputs[0]["output"])["matches"]
                        arguments["key"] = matches[0]["key"]
                    else:
                        arguments["query"] = "context"
                    call = {"type": "function_call", "call_id": "call-" + str(len(outputs)),
                            "namespace": "current_document", "name": "read_passage" if outputs else "search_current_document",
                            "arguments": json.dumps(arguments)}
                    if owner.mode == "unsupported-tool":
                        call["name"] = "exec_command"
                    emit({"type": "response.completed", "response": {"status": "completed", "output": [call]}})
                    return
                if owner.mode == "markdown":
                    text = r"""**끝점이 고정되어 있기 때문입니다.** 허용되는 변분은 \(\delta q(t_1)=\delta q(t_2)=0\)을 만족합니다.

\[\left[\frac{\partial L}{\partial \dot q}\delta q\right]_{t_1}^{t_2}=0\]

- 두 끝점에서 변분은 0입니다.
- 경계항의 양 끝값도 0입니다.

<img src=x onerror=alert(1)>

[unsafe](javascript:alert(1))

```html
<script>alert(1)</script>
```
"""
                    emit({"type": "response.output_text.delta", "delta": text})
                    emit({"type": "response.completed", "response": {"status": "completed", "output": []}})
                    return
                emit({"type": "response.in_progress"})
                for delta in ("The accepted context ", "supports this answer. ", "<img src=x onerror=alert(1)>"):
                    emit({"type": "response.output_text.delta", "delta": delta})
                    time.sleep(0.12)
                emit({"type": "response.completed", "response": {"status": "completed", "output": [
                    {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "The accepted context supports this answer."}]}]}})
            def log_message(self, *_args):
                pass
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()

    def tokens(self):
        def b64(value):
            return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
        header = b64({"alg": "EdDSA", "kid": "fixture"})
        payload = b64({"iss": self.url, "sub": self.subject, "aud": "oaiapp_fixture", "iat": time.time(),
                       "exp": time.time() + 3600, "nonce": self.nonce, "email": "fixture@example.invalid"})
        data = header + "." + payload
        signature = subprocess.check_output(["node", "--input-type=module", "-e",
            'import {createPrivateKey,sign} from "node:crypto"; let s=""; for await (const c of process.stdin) s+=c;'
            'const x=JSON.parse(s);process.stdout.write(sign(null,Buffer.from(x.data),createPrivateKey({key:x.key,format:"jwk"})).toString("base64url"));'],
            input=json.dumps({"data": data, "key": self.keys["private"]}).encode()).decode()
        return {"access_token": "fixture-access", "refresh_token": "fixture-refresh-" + str(self.refreshes),
                "id_token": data + "." + signature, "token_type": "Bearer", "expires_in": 3600,
                "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"}

    def auth(self, directory, signed_in=False):
        auth = ChatAuth(private_directory(directory), issuer=self.url, open_browser=None)
        if signed_in:
            record = {"subject": self.subject, "client_id": "oaiapp_fixture", "email": "fixture@example.invalid", "issuer": self.url}
            auth.update_tokens(record, self.tokens())
            write_json(auth.path, {"hostID": "urn:uuid:fixture", "active": "oaiapp_fixture",
                                   "registrations": {"oaiapp_fixture": record}})
        return auth

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.worker.join()


class SyntheticReader:
    def __init__(self, work, fake):
        self.work = work
        root = work / "source"
        root.mkdir()
        self.entry = root / "main.typ"
        self.entry.write_text("First paragraph keeps its own question.\n\nA second independent paragraph.\n\nAdditional context can be found by the model.")
        project = Project(root, Path("main.typ"), work / "packages", compiler="never-run")
        self.state = ReaderState(project, work / "output", "https://example.invalid/paged/", False)
        self.html = ('<html><body><h1>Paragraph conversations</h1>'
            '<p id="first">First paragraph keeps its own question.</p>'
            '<p id="second">A second independent paragraph.</p>'
            '<p id="context">Additional context can be found by the model.</p>'
            '<p id="annotated">A paragraph with <span data-flow-mark="m1" data-reader-note="long-note">marked content</span>.</p>'
            '<aside class="flow-notes"><div class="flow-note" id="long-note" data-flow-targets="[&quot;m1&quot;]">'
            'A longer annotation explaining why the adjacent marked content remains associated with its paragraph.</div></aside>'
            '<div class="flow-equation" id="equation"><math display="block"><mrow><mi data-flow-mark="m2">x</mi>'
            '<mo>=</mo><mn>1</mn></mrow></math><span class="flow-equation-number">(1)</span></div>'
            '<aside class="flow-notes"><div data-flow-targets="[&quot;m2&quot;]">kernel</div></aside>'
            '<p id="trailing">Trailing ordinary prose remains selectable.</p>'
            '<p id="unicode-suffix">Suffix case' + 'a' * 63 + '𝑁 end.</p>'
            '<p id="unicode-prefix">𝑁' + 'a' * 62 + ' Prefix case.</p></body></html>')
        self.publish("fixture-r1")
        auth = fake.auth(work / "private", signed_in=True)
        provider = ResponsesProvider(auth, resource=fake.url)
        self.state._paragraph_chat = ParagraphChat(self.state, directory=work / "private", provider=provider)

    def publish(self, revision):
        state = self.state
        state.bundle = split_document(self.html, revision)
        state.bundle.manifest.update(documentID=state.document_id, service=state.focus.service, lastChange=None)
        state.revision = revision
        state.source_stamp = source_signature(state.project, set())
        state.accepted_inputs = input_fingerprint(state.project, set())
        state.manifest_json = json.dumps(state.bundle.manifest).encode()
        state.manifest_compressed = gzip.compress(state.manifest_json)
        state.section_compressed = {k: gzip.compress(v) for k, v in state.bundle.documents.items()}
        state.document = self.html.encode()
        state.compressed = gzip.compress(state.document)

    def request(self, **extra):
        return {"documentID": self.state.document_id, "service": self.state.focus.service,
                "revision": self.state.revision, **extra}

    def fragments(self, text):
        passage = next(p for p in self.state.bundle.passages if text in p["text"])
        return [{"key": passage["key"], "exact": text, "prefix": "", "suffix": "",
                 "revision": self.state.revision, "service": self.state.focus.service}]

    def close(self):
        self.state.close()
